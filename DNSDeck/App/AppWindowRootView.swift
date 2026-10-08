import SwiftUI

struct ZoneWindowRequest: Hashable, Codable {
    static let sceneID = "zone-window"
    static let placeholder = ZoneWindowRequest(environmentId: UUID(), zoneId: "", zoneName: "")

    let environmentId: UUID
    let zoneId: String
    let zoneName: String

    init(environmentId: UUID, zoneId: String, zoneName: String) {
        self.environmentId = environmentId
        self.zoneId = zoneId
        self.zoneName = zoneName
    }

    init(zone: ProviderZone) {
        self.init(
            environmentId: zone.environmentId,
            zoneId: zone.id,
            zoneName: zone.name
        )
    }
}

struct AppWindowRootView: View {
    @StateObject private var model: AppModel
    @ObservedObject private var lockController: AppLockController
    @ObservedObject private var settingsManager: SettingsManager

    private let zoneWindowRequest: ZoneWindowRequest?

    init(
        lockController: AppLockController,
        settingsManager: SettingsManager,
        zoneWindowRequest: ZoneWindowRequest? = nil
    ) {
        _model = StateObject(wrappedValue: AppModel(lockController: lockController))
        _lockController = ObservedObject(wrappedValue: lockController)
        _settingsManager = ObservedObject(wrappedValue: settingsManager)
        self.zoneWindowRequest = zoneWindowRequest
    }

    var body: some View {
        ContentView(zoneWindowRequest: zoneWindowRequest)
            .environmentObject(model)
            .environmentObject(lockController)
            .environmentObject(settingsManager)
            .focusedSceneObject(model)
    }
}
