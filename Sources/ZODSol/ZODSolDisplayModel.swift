import Foundation

struct ZODSolDisplayModel: Equatable, Sendable {
    let appName: String
    let statusItemTitle: String
    let panelLabel: String
    let panelWidth: Double
    let panelHeight: Double

    static let initial = ZODSolDisplayModel(
        appName: "ZODSol",
        statusItemTitle: "ZODs",
        panelLabel: "ZODs",
        panelWidth: 360,
        panelHeight: 600)
}
