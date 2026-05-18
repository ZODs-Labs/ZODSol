import Foundation
import Kit

public enum Base58 {
    public static func decode(_ string: String) throws -> Data {
        do {
            return try Kit.getBase58Encoder().encode(string)
        } catch {
            throw SolanaProviderError.invalidInput("invalid base58 value")
        }
    }

    public static func encode(_ data: Data) -> String {
        do {
            return try Kit.getBase58Decoder().read(data, at: 0).0
        } catch {
            return ""
        }
    }
}
