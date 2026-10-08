import Foundation

extension Notification.Name {
    static let showNewEnvironmentSheet = Notification.Name("showNewEnvironmentSheet")
    static let showEditEnvironmentSheet = Notification.Name("showEditEnvironmentSheet")
    static let reloadZone = Notification.Name("reloadZone")
    static let addRecord = Notification.Name("addRecord")
    static let providerCredentialsDidChange = Notification.Name("providerCredentialsDidChange")
}

enum NotificationUserInfoKey {
    static let environmentID = "environmentID"
}
