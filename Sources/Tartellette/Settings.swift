import Foundation

/// Persistent per-user preferences (UserDefaults backed).
final class Settings {
  private let defaults = UserDefaults.standard

  /// Whether `tart run` opens a GUI window for this VM. Defaults to true.
  func gui_enabled(for vm: String) -> Bool {
    (defaults.dictionary(forKey: "gui") as? [String: Bool])?[vm] ?? true
  }

  func set_gui_enabled(_ on: Bool, for vm: String) {
    var d = (defaults.dictionary(forKey: "gui") as? [String: Bool]) ?? [:]
    d[vm] = on
    defaults.set(d, forKey: "gui")
  }

  func move_settings(from old: String, to new: String) {
    guard var d = defaults.dictionary(forKey: "gui") as? [String: Bool], let v = d.removeValue(forKey: old) else { return }
    d[new] = v
    defaults.set(d, forKey: "gui")
  }

  /// Hide VMs whose source is an OCI registry.
  var hide_remote: Bool {
    get { defaults.bool(forKey: "hideRemote") }
    set { defaults.set(newValue, forKey: "hideRemote") }
  }

  /// Guest account used when opening a shell. Tart's stock images use "admin".
  var ssh_user: String { defaults.string(forKey: "sshUser") ?? "admin" }
}
