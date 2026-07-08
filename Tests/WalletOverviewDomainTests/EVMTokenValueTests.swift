import SolanaKit
import XCTest
@testable import WalletOverviewDomain

final class EVMTokenValueTests: XCTestCase {
    private let baseUSDC = "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913"

    // MARK: - EVMAddress

    func testNormalizeLowercasesValidAddress() {
        XCTAssertEqual(EVMAddress.normalized(self.baseUSDC), self.baseUSDC)
    }

    func testNormalizeAcceptsMixedCaseAndUppercasePrefix() {
        XCTAssertEqual(EVMAddress.normalized("  0X833589FCD6EDB6E08F4C7C32D4F71B54BDA02913 "), self.baseUSDC)
    }

    func testNormalizeRejectsWrongLengthAndNonHex() {
        XCTAssertNil(EVMAddress.normalized("0x1234"))
        XCTAssertNil(EVMAddress.normalized("0x833589fcd6edb6e08f4c7c32d4f71b54bda029zz"))
        XCTAssertNil(EVMAddress.normalized("833589fcd6edb6e08f4c7c32d4f71b54bda02913"))
    }

    func testFirstAddressExtractsFromExplorerURL() {
        let url = "https://basescan.org/token/0x833589fcd6edb6e08f4c7c32d4f71b54bda02913?a=1"
        XCTAssertEqual(EVMAddress.firstAddress(in: url), self.baseUSDC)
    }

    func testFirstAddressIgnoresTransactionHash() {
        let txHash = "0x" + String(repeating: "a", count: 64)
        XCTAssertNil(EVMAddress.firstAddress(in: txHash))
    }

    // MARK: - EVMTokenRef

    func testRefRoundTripsThroughSourceIdentifier() throws {
        let ref = EVMTokenRef(chain: .base, address: self.baseUSDC)
        XCTAssertEqual(ref.sourceIdentifier, "evm:base:\(self.baseUSDC)")
        let parsed = try XCTUnwrap(EVMTokenRef(sourceIdentifier: ref.sourceIdentifier))
        XCTAssertEqual(parsed, ref)
    }

    func testRefLowercasesAddress() {
        let ref = EVMTokenRef(chain: .ethereum, address: "0xA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48")
        XCTAssertEqual(ref.address, "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48")
    }

    func testRefRejectsNonEVMOrUnsupportedIdentifiers() {
        XCTAssertNil(EVMTokenRef(sourceIdentifier: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"))
        XCTAssertNil(EVMTokenRef(sourceIdentifier: "XXBTZUSD"))
        XCTAssertNil(EVMTokenRef(sourceIdentifier: "evm:fantom:\(self.baseUSDC)"))
    }

    // MARK: - EVMChain

    func testSupportedLookups() {
        XCTAssertEqual(EVMChain.supported(slug: "bsc"), .bsc)
        XCTAssertEqual(EVMChain.supported(dexScreenerId: "avalanche"), .avalanche)
        XCTAssertEqual(EVMChain.supported(dexScreenerId: "robinhood"), .robinhood)
        XCTAssertNil(EVMChain.supported(slug: "linea"))
    }

    func testChainMapCompleteness() {
        var slugs = Set<String>()
        for chain in EVMChain.supported {
            XCTAssertFalse(chain.slug.isEmpty, "empty slug")
            XCTAssertFalse(chain.displayName.isEmpty, "empty displayName for \(chain.slug)")
            XCTAssertFalse(chain.dexScreenerId.isEmpty, "empty dexScreenerId for \(chain.slug)")
            XCTAssertFalse(chain.defiLlamaId.isEmpty, "empty defiLlamaId for \(chain.slug)")
            XCTAssertFalse(chain.nativeSymbol.isEmpty, "empty nativeSymbol for \(chain.slug)")
            XCTAssertTrue(slugs.insert(chain.slug).inserted, "duplicate slug \(chain.slug)")
        }
    }

    func testRobinhoodRefRoundTrips() throws {
        let ref = EVMTokenRef(chain: .robinhood, address: "0x79fe86b963255ce884bdcac6388c50a599ba277f")
        XCTAssertEqual(ref.sourceIdentifier, "evm:robinhood:0x79fe86b963255ce884bdcac6388c50a599ba277f")
        XCTAssertEqual(EVMTokenRef(sourceIdentifier: ref.sourceIdentifier), ref)
    }

    // MARK: - PasteClassifier

    func testClassifierRoutesInputFamilies() {
        XCTAssertEqual(PasteClassifier.classify(""), .empty)
        XCTAssertEqual(PasteClassifier.classify("   "), .empty)
        XCTAssertEqual(PasteClassifier.classify("  \(self.baseUSDC)  "), .evm(address: self.baseUSDC))
        XCTAssertEqual(
            PasteClassifier.classify("https://etherscan.io/token/\(self.baseUSDC)"),
            .evm(address: self.baseUSDC))
        XCTAssertEqual(PasteClassifier.classify("vitalik.eth"), .ensName)
        XCTAssertEqual(
            PasteClassifier.classify("EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"),
            .solanaMint(mint: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"))
        XCTAssertEqual(PasteClassifier.classify("not an address!!!"), .unrecognized)
    }
}
