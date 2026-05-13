import Foundation

public enum MemoProgram {
    public static let id = ProgramAddresses.memo

    public static func memo(_ text: String) -> Instruction {
        Instruction(programAddress: self.id, accounts: [], data: Data(text.utf8))
    }
}

