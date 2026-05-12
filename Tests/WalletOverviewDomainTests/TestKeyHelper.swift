import CryptoKit
import Foundation
import SolanaKit
@testable import WalletOverviewDomain

struct TestKeyMaterial {
    let seed: Data
    let pubKey: Data
    let secretKey64: Data
    let base58Key: String
    let base58Address: String
}

func makeTestPrivateKey() -> TestKeyMaterial {
    let pk = Curve25519.Signing.PrivateKey()
    let seed = pk.rawRepresentation
    let pub = pk.publicKey.rawRepresentation
    var key64 = Data(seed)
    key64.append(pub)
    return TestKeyMaterial(
        seed: Data(seed),
        pubKey: Data(pub),
        secretKey64: key64,
        base58Key: Base58.encode(key64),
        base58Address: Base58.encode(Data(pub)))
}
