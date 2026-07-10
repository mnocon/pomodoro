import Foundation
import ServiceManagement

/// Registers the app as a login item via SMAppService (macOS 13+).
enum LoginItemManager {
    /// SMAppService only works from a real .app bundle. Under `swift run`
    /// the bare executable has no Info.plist, so bundleIdentifier is nil.
    static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
