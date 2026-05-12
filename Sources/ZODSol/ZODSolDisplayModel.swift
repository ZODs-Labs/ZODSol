import Foundation

struct ZODSolDisplayModel: Equatable, Sendable {
    let appName: String
    let statusItemTitle: String
    let panelLabel: String

    static let initial = ZODSolDisplayModel(
        appName: "ZODSol",
        statusItemTitle: "ZODs",
        panelLabel: "ZODs")
}
