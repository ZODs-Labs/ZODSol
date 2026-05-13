import Foundation

/// Compatibility profile for a Token-2022 mint, used by the send-assets
/// orchestrator to decide whether the mint can be transferred and which
/// instruction (`transferChecked` vs `transferCheckedWithFee`) to emit.
public struct Token2022MintProfile: Sendable, Equatable {
    /// Outcome of the parse + extension audit.
    public enum Compatibility: Sendable, Equatable {
        /// Mint can be transferred. Use `transferFee` to pick the instruction.
        case ok
        /// Mint has an extension we do not support in v1. The associated reason
        /// is a short, log-safe string suitable for an error banner.
        case refused(reason: String)
    }

    /// The active per-epoch transfer fee. `nil` means: no `TransferFeeConfig`
    /// extension, OR a fee with `basisPoints == 0`. In either case the caller
    /// uses plain `transferChecked` and the recipient receives the full amount.
    public struct TransferFeeForEpoch: Sendable, Equatable, Hashable {
        public let basisPoints: UInt16
        public let maximumFee: UInt64
        public let epoch: UInt64

        public init(basisPoints: UInt16, maximumFee: UInt64, epoch: UInt64) {
            self.basisPoints = basisPoints
            self.maximumFee = maximumFee
            self.epoch = epoch
        }

        /// Compute the fee for `amount`, exactly as the program does:
        /// `min(amount * bps / 10_000, maximumFee)`. Uses 128-bit math via
        /// `multipliedFullWidth` so the multiplication cannot overflow.
        public func fee(for amount: UInt64) -> UInt64 {
            let product = amount.multipliedFullWidth(by: UInt64(self.basisPoints))
            let divisor: UInt64 = 10000
            // basisPoints is capped at 10_000 by the program, so product.high <
            // divisor, satisfying dividingFullWidth's precondition. The
            // explicit guard keeps the function correct even if a future caller
            // passes a wider value.
            guard product.high < divisor else { return self.maximumFee }
            let (quotient, _) = divisor.dividingFullWidth(product)
            return min(quotient, self.maximumFee)
        }
    }

    public let compatibility: Compatibility
    /// The mint's decimals, copied from the legacy `Mint` base struct so the
    /// orchestrator never has to parse mint bytes a second time.
    public let decimals: UInt8
    /// Active per-epoch transfer fee, or `nil` (no fee or fee == 0).
    public let transferFee: TransferFeeForEpoch?
    /// `true` if the mint has a `PermanentDelegate` set. Informational only;
    /// surface as a banner so the user knows the issuer can sweep tokens.
    public let permanentDelegate: Bool

    public init(
        compatibility: Compatibility,
        decimals: UInt8,
        transferFee: TransferFeeForEpoch?,
        permanentDelegate: Bool)
    {
        self.compatibility = compatibility
        self.decimals = decimals
        self.transferFee = transferFee
        self.permanentDelegate = permanentDelegate
    }
}

/// Parser for Token-2022 mint accounts (TLV extension envelope).
public enum Token2022Mint {
    public enum ParseError: Error, Sendable, Equatable {
        /// The account data is shorter than the legacy `Mint` (82 bytes), so
        /// it cannot be a mint of any kind.
        case tooShort
        /// The account-type discriminator at offset 165 is not `1` (Mint).
        case notMint(accountType: UInt8)
        /// A TLV extension entry's length pointed past the end of the buffer
        /// or otherwise failed to deserialize.
        case malformedExtension(typeId: UInt16)
        /// The legacy `Mint` base struct claims uninitialized (`is_initialized == 0`).
        case mintUninitialized
    }

    // MARK: - Extension type identifiers (subset relevant to mints)

    private enum ExtensionType: UInt16 {
        case uninitialized = 0
        case transferFeeConfig = 1
        case mintCloseAuthority = 3
        case confidentialTransferMint = 4
        case defaultAccountState = 6
        case nonTransferable = 9
        case interestBearingConfig = 10
        case permanentDelegate = 12
        case transferHook = 14
        case metadataPointer = 18
        case tokenMetadata = 19
        case groupPointer = 20
        case tokenGroup = 21
        case groupMemberPointer = 22
        case tokenGroupMember = 23
    }

    private static let mintAccountType: UInt8 = 1
    private static let baseMintSize = 82
    private static let extensionsStart = 166 // base (82) + padding (83) + 1-byte discriminator

    // MARK: - Parse

    /// Parse a Token-2022 mint account's bytes, returning a profile that
    /// summarises whether the mint can be transferred and what its current
    /// fee is for `currentEpoch`. The legacy `Mint` base struct is also
    /// validated.
    public static func parse(_ accountData: Data, currentEpoch: UInt64) throws -> Token2022MintProfile {
        guard accountData.count >= self.baseMintSize else { throw ParseError.tooShort }

        // 1. Base Mint struct.
        let isInitialized = self.byte(accountData, at: 45)
        guard isInitialized == 1 else { throw ParseError.mintUninitialized }
        let decimals = self.byte(accountData, at: 44)

        // 2. If the buffer is exactly the legacy size, there are no extensions.
        if accountData.count == self.baseMintSize {
            return Token2022MintProfile(
                compatibility: .ok,
                decimals: decimals,
                transferFee: nil,
                permanentDelegate: false)
        }

        // 3. Token-2022 mints carry a discriminator at offset 165.
        guard accountData.count > 165 else { throw ParseError.tooShort }
        let accountType = self.byte(accountData, at: 165)
        guard accountType == self.mintAccountType else {
            throw ParseError.notMint(accountType: accountType)
        }

        // 4. Walk the TLV extension list.
        var permanentDelegate = false
        var transferFee: Token2022MintProfile.TransferFeeForEpoch?
        var refusal: String?

        var offset = self.extensionsStart
        while offset + 4 <= accountData.count {
            let typeIdRaw = self.readU16(accountData, at: offset)
            let length = Int(readU16(accountData, at: offset + 2))
            let dataStart = offset + 4
            let dataEnd = dataStart + length

            // Uninitialized sentinel marks the end of the extension list.
            if typeIdRaw == 0 { break }

            guard dataEnd <= accountData.count else {
                throw ParseError.malformedExtension(typeId: typeIdRaw)
            }

            let body = accountData.subdata(in: dataStart..<dataEnd)
            if let typeId = ExtensionType(rawValue: typeIdRaw) {
                switch typeId {
                case .transferFeeConfig:
                    transferFee = try self.parseTransferFeeConfig(body, currentEpoch: currentEpoch)

                case .transferHook:
                    if self.hasNonZeroPubkeyAtTransferHookProgramOffset(body) {
                        refusal = "This token uses a transfer hook ZODSol does not support."
                    }

                case .nonTransferable:
                    refusal = "This token is non-transferable."

                case .defaultAccountState:
                    let state = body.first ?? 0
                    if state == 2 {
                        refusal = "Recipients of this token are frozen by default."
                    }

                case .confidentialTransferMint:
                    refusal = "Confidential transfers are not supported."

                case .permanentDelegate:
                    if self.hasNonZeroPubkey(body) { permanentDelegate = true }

                case .uninitialized, .mintCloseAuthority, .interestBearingConfig,
                     .metadataPointer, .tokenMetadata, .groupPointer, .tokenGroup,
                     .groupMemberPointer, .tokenGroupMember:
                    break
                }
            } else {
                refusal = "This token uses an unknown Token-2022 extension."
            }

            offset = dataEnd
        }

        let compatibility: Token2022MintProfile.Compatibility = refusal.map { .refused(reason: $0) } ?? .ok

        return Token2022MintProfile(
            compatibility: compatibility,
            decimals: decimals,
            transferFee: transferFee,
            permanentDelegate: permanentDelegate)
    }

    // MARK: - Extension body parsers

    private static func parseTransferFeeConfig(
        _ body: Data,
        currentEpoch: UInt64) throws -> Token2022MintProfile.TransferFeeForEpoch?
    {
        // Layout (108 bytes):
        // 0..32   transfer_fee_config_authority (OptionalNonZeroPubkey)
        // 32..64  withdraw_withheld_authority   (OptionalNonZeroPubkey)
        // 64..72  withheld_amount               u64 LE
        // 72..90  older_transfer_fee (TransferFee, 18 bytes)
        // 90..108 newer_transfer_fee
        //
        // TransferFee layout (18 bytes):
        //   0..8   epoch                       u64 LE
        //   8..16  maximum_fee                 u64 LE
        //   16..18 transfer_fee_basis_points   u16 LE
        guard body.count >= 108 else {
            throw ParseError.malformedExtension(typeId: ExtensionType.transferFeeConfig.rawValue)
        }
        let older = self.parseTransferFee(body.subdata(in: 72..<90))
        let newer = self.parseTransferFee(body.subdata(in: 90..<108))

        let effective = currentEpoch >= newer.epoch ? newer : older

        if effective.basisPoints == 0 {
            return nil
        }
        return effective
    }

    private static func parseTransferFee(_ body: Data) -> Token2022MintProfile.TransferFeeForEpoch {
        let epoch = self.readU64(body, at: 0)
        let maximumFee = self.readU64(body, at: 8)
        let basisPoints = self.readU16(body, at: 16)
        return Token2022MintProfile.TransferFeeForEpoch(
            basisPoints: basisPoints,
            maximumFee: maximumFee,
            epoch: epoch)
    }

    /// Returns `true` if the body has any non-zero byte. Token-2022's
    /// `OptionalNonZeroPubkey` represents "None" as 32 zero bytes.
    private static func hasNonZeroPubkey(_ body: Data) -> Bool {
        guard body.count >= 32 else { return false }
        return !body.prefix(32).allSatisfy { $0 == 0 }
    }

    /// For TransferHook: layout is [authority (32) || program_id (32)]. The
    /// hook is active only when `program_id` is non-zero.
    private static func hasNonZeroPubkeyAtTransferHookProgramOffset(_ body: Data) -> Bool {
        guard body.count >= 64 else { return false }
        return !body.subdata(in: 32..<64).allSatisfy { $0 == 0 }
    }

    // MARK: - Byte helpers

    private static func byte(_ data: Data, at offset: Int) -> UInt8 {
        data[data.startIndex + offset]
    }

    private static func readU16(_ data: Data, at offset: Int) -> UInt16 {
        let lo = UInt16(byte(data, at: offset))
        let hi = UInt16(byte(data, at: offset + 1))
        return (hi << 8) | lo
    }

    private static func readU64(_ data: Data, at offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<8 {
            value |= UInt64(self.byte(data, at: offset + index)) << (8 * index)
        }
        return value
    }
}
