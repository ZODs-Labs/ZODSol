import Foundation

/// Builders for the Compute Budget program.
///
/// Both `SetComputeUnitLimit` and `SetComputeUnitPrice` are appended at the
/// start of every transaction we sign:
///
///  - `SetComputeUnitLimit` caps the work the runtime will do for the tx,
///    and must be sized after simulation (otherwise we either underbudget
///    and the tx fails, or overpay for unused CU).
///  - `SetComputeUnitPrice` is the priority-fee bid (microLamports per CU).
public enum ComputeBudgetProgram {
    public static let id = ProgramAddresses.computeBudget

    /// Wire data: 1-byte discriminator `2`, 4-byte LE u32 units.
    public static func setComputeUnitLimit(units: UInt32) -> Instruction {
        var data = Data()
        data.reserveCapacity(5)
        data.append(0x02)
        LittleEndianEncoder.appendUInt32(units, to: &data)
        return Instruction(programAddress: self.id, accounts: [], data: data)
    }

    /// Wire data: 1-byte discriminator `3`, 8-byte LE u64 microLamports.
    public static func setComputeUnitPrice(microLamports: UInt64) -> Instruction {
        var data = Data()
        data.reserveCapacity(9)
        data.append(0x03)
        LittleEndianEncoder.appendUInt64(microLamports, to: &data)
        return Instruction(programAddress: self.id, accounts: [], data: data)
    }
}
