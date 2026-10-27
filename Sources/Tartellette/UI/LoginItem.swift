import AppKit
import ServiceManagement

/// Launch at login, via the system's login items (System Settings › General › Login Items).
/// The state lives in the system, not in our settings, so it stays in sync if the user
/// changes it there. Off unless the user turns it on.
@MainActor
enum LoginItem {
  static var enabled: Bool { SMAppService.mainApp.status == .enabled }

  static func toggle() {
    let service = SMAppService.mainApp
    do {
      if service.status == .enabled {
        try service.unregister()
      } else {
        try service.register()
        if service.status == .requiresApproval {
          Dialogs.error("Allow Tartellette in System Settings › General › Login Items to start it at login.")
          SMAppService.openSystemSettingsLoginItems()
        }
      }
    } catch {
      // Fails when not running from an .app bundle (e.g. `swift run`).
      Dialogs.error("Could not change the login item:\n\n\(error.localizedDescription)")
    }
  }
}
