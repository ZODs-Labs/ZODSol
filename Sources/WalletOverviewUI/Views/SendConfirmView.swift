import Formatters
import SolanaKit
import SwiftUI
import WalletOverviewDomain

struct SendConfirmView: View {
    @Bindable var viewModel: SendViewModel
    let quote: SendQuote

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let amountFormatter = TokenAmountFormatter(locale: Locale(identifier: "en_US"))
    private let currencyFormatter = CurrencyFormatter(locale: Locale(identifier: "en_US"))

    var body: some View {
        VStack(spacing: 12) {
            YouSendCard(
                amountToken: self.tokenDisplay,
                amountFiat: self.fiatDisplay,
                assetSymbol: self.assetSymbol,
                recipientFull: self.quote.request.recipient.base58,
                recipientShort: self.shortAddress)

            DisclosureGroup("Details", isExpanded: self.$viewModel.detailsExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    DetailRow("Network fee", value: self.feeDisplay)
                    if self.quote.recipientAtaWillBeCreated {
                        DetailRow("Recipient account rent", value: self.rentDisplay)
                    }
                    PriorityTierPicker(selection: self.$viewModel.priorityTier)
                        .padding(.vertical, 4)
                    DetailRow("Total cost", value: self.totalDisplay)
                    if let transferFee = self.transferFeeDisplay {
                        DetailRow("Transfer fee", value: transferFee)
                    }
                }
                .padding(.top, 4)
            }
            .animation(self.reduceMotion ? nil : .easeInOut(duration: 0.22), value: self.viewModel.detailsExpanded)

            if let notice = self.quote.token2022Notice {
                if let bps = notice.transferFeeBasisPoints, bps > 500 {
                    WarningBanner(
                        text: "High transfer fee - \(self.formatBasisPoints(bps)) of the amount stays with the issuer.",
                        style: .amber)
                }
                if notice.permanentDelegate {
                    WarningBanner(
                        text: "This token has a permanent delegate - the issuer can move it at any time.",
                        style: .red)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Button("Back") { self.viewModel.back() }
                    .buttonStyle(.bordered)
                ClusterBadge(network: self.viewModel.cluster)
                Spacer()
                Button {
                    Task { await self.viewModel.confirmSend() }
                } label: {
                    Text("Send on \(self.viewModel.cluster.displayName)")
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(self.viewModel.cluster == .mainnet ? .red : .accentColor)
            }
        }
        .padding(16)
    }

    private var assetSymbol: String {
        switch self.viewModel.intent.asset {
        case .sol: "SOL"
        case let .splToken(_, _, symbol, _): symbol ?? "token"
        }
    }

    private var shortAddress: String {
        let b58 = self.quote.request.recipient.base58
        guard b58.count > 12 else { return b58 }
        return "\(b58.prefix(4))...\(b58.suffix(4))"
    }

    private var tokenDisplay: String {
        self.formattedAmount(of: self.quote.request.asset)
    }

    private var fiatDisplay: String? {
        guard let price = self.viewModel.assetPriceUSD else { return nil }
        let decimals = Int(self.assetDecimals(of: self.quote.request.asset))
        let scale = Self.power10(decimals)
        let amount = self.baseUnits(of: self.quote.request.asset)
        let ui = Decimal(amount) / scale
        return self.currencyFormatter.string(usd: ui * price)
    }

    private var feeDisplay: String {
        self.solString(self.quote.networkFeeLamports)
    }

    private var rentDisplay: String {
        self.solString(self.quote.rentForRecipientAta)
    }

    private var totalDisplay: String {
        if case let .sol(amount) = self.quote.request.asset {
            let combined = amount.rawValue
                &+ self.quote.networkFeeLamports.rawValue
                &+ (self.quote.recipientAtaWillBeCreated ? self.quote.rentForRecipientAta.rawValue : 0)
            return self.solString(Lamports(rawValue: combined))
        }
        let combined = self.quote.networkFeeLamports.rawValue
            &+ (self.quote.recipientAtaWillBeCreated ? self.quote.rentForRecipientAta.rawValue : 0)
        return "\(self.tokenDisplay) + \(self.solString(Lamports(rawValue: combined)))"
    }

    private var transferFeeDisplay: String? {
        guard let notice = self.quote.token2022Notice, let fee = notice.transferFeeAmount, fee > 0 else {
            return nil
        }
        let decimals = self.assetDecimals(of: self.quote.request.asset)
        let scale = Self.power10(Int(decimals))
        let ui = Decimal(fee) / scale
        return "\(self.amountFormatter.largeNumber(ui)) \(self.assetSymbol)"
    }

    private func formatBasisPoints(_ bps: UInt16) -> String {
        String(format: "%.2f%%", Double(bps) / 100.0)
    }

    private func solString(_ lamports: Lamports) -> String {
        let sol = Decimal(lamports.rawValue) / Self.power10(9)
        return "\(self.amountFormatter.largeNumber(sol)) SOL"
    }

    private func formattedAmount(of asset: SendAsset) -> String {
        switch asset {
        case let .sol(amount):
            return self.solString(amount)
        case let .splToken(_, amount, decimals):
            let ui = Decimal(amount) / Self.power10(Int(decimals))
            return "\(self.amountFormatter.largeNumber(ui)) \(self.assetSymbol)"
        }
    }

    private func assetDecimals(of asset: SendAsset) -> UInt8 {
        switch asset {
        case .sol: 9
        case let .splToken(_, _, decimals): decimals
        }
    }

    private func baseUnits(of asset: SendAsset) -> UInt64 {
        switch asset {
        case let .sol(amount): amount.rawValue
        case let .splToken(_, amount, _): amount
        }
    }

    private static func power10(_ exponent: Int) -> Decimal {
        var result = Decimal(1)
        var base = Decimal(10)
        var remaining = exponent
        while remaining > 0 {
            if remaining & 1 == 1 { result *= base }
            remaining >>= 1
            if remaining > 0 { base *= base }
        }
        return result
    }
}

private struct YouSendCard: View {
    let amountToken: String
    let amountFiat: String?
    let assetSymbol: String
    let recipientFull: String
    let recipientShort: String

    var body: some View {
        self.cardContent
    }

    @ViewBuilder
    private var cardContent: some View {
        let inner = VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("You send")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            HStack(spacing: 12) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.accentColor.opacity(0.85))
                VStack(alignment: .leading, spacing: 2) {
                    Text(self.amountToken)
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(self.assetSymbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let fiat = self.amountFiat {
                        Text(fiat)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            Divider()
            HStack(spacing: 8) {
                Text("To")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(self.recipientShort)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
                Spacer()
                CopyButton(text: self.recipientFull)
            }
        }
        .padding(14)

        if #available(macOS 26.0, *) {
            inner.glassEffect(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            inner
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.background.opacity(0.6)))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        }
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    init(_ label: String, value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack {
            Text(self.label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(self.value)
                .foregroundStyle(.primary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .font(.callout)
    }
}

private struct WarningBanner: View {
    enum Style {
        case amber
        case red
    }

    let text: String
    let style: Style

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(self.iconColor)
            Text(self.text)
                .font(.callout)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(self.backgroundColor.opacity(0.12)))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(self.backgroundColor.opacity(0.30), lineWidth: 0.5))
    }

    private var iconColor: Color {
        switch self.style {
        case .amber: .yellow
        case .red: .red
        }
    }

    private var backgroundColor: Color {
        switch self.style {
        case .amber: .yellow
        case .red: .red
        }
    }
}

extension SolanaNetwork {
    fileprivate var displayName: String {
        switch self {
        case .mainnet: "Mainnet"
        case .devnet: "Devnet"
        case .testnet: "Testnet"
        }
    }
}

#if DEBUG

#Preview("YouSendCard - SOL devnet") {
    YouSendCard(
        amountToken: "0.25",
        amountFiat: "$37.50",
        assetSymbol: "SOL",
        recipientFull: "5x38Kp4hvdomTCnCrAny4UtMUt5rQBdB6px2K1Ui45Wq",
        recipientShort: "5x38…45Wq")
        .padding(16)
        .frame(width: 380)
}

#Preview("YouSendCard - long token name") {
    YouSendCard(
        amountToken: "12.5",
        amountFiat: "$12.50",
        assetSymbol: "Wrapped Solana Stablecoin V2",
        recipientFull: "5x38Kp4hvdomTCnCrAny4UtMUt5rQBdB6px2K1Ui45Wq",
        recipientShort: "5x38…45Wq")
        .padding(16)
        .frame(width: 380)
}

#Preview("WarningBanner - amber") {
    WarningBanner(
        text: "High transfer fee - 6.00% of the amount stays with the issuer.",
        style: .amber)
        .padding(16)
        .frame(width: 380)
}

#Preview("WarningBanner - red") {
    WarningBanner(
        text: "This token has a permanent delegate - the issuer can move it at any time.",
        style: .red)
        .padding(16)
        .frame(width: 380)
}

#Preview("DetailRow") {
    VStack(alignment: .leading, spacing: 8) {
        DetailRow("Network fee", value: "0.000005 SOL")
        DetailRow("Recipient account rent", value: "0.002 SOL")
        DetailRow("Total cost", value: "0.250 SOL + 0.002 SOL")
    }
    .padding(16)
    .frame(width: 380)
}

#endif
