import Foundation

/// Persistent per-user preferences (UserDefaults backed).
final class Settings {
  private let defaults = UserDefaults.standard
  private let configs_key = "vmConfigs"

  init() {
    migrate_gui_flags()
  }

  // MARK: - Per-VM configuration

  func config(for vm: String) -> VMConfig {
    configs[vm] ?? VMConfig()
  }

  func update_config(for vm: String, _ body: (inout VMConfig) -> Void) {
    var all = configs
    var c = all[vm] ?? VMConfig()
    body(&c)
    all[vm] = c
    configs = all
  }

  func move_settings(from old: String, to new: String) {
    var all = configs
    guard let c = all.removeValue(forKey: old) else { return }
    all[new] = c
    configs = all
  }

  func remove_settings(for vm: String) {
    var all = configs
    if all.removeValue(forKey: vm) != nil { configs = all }
  }

  private var configs: [String: VMConfig] {
    get {
      guard let data = defaults.data(forKey: configs_key) else { return [:] }
      return (try? JSONDecoder().decode([String: VMConfig].self, from: data)) ?? [:]
    }
    set { defaults.set(try? JSONEncoder().encode(newValue), forKey: configs_key) }
  }

  /// Earlier versions stored only the GUI flag, in a "gui" dictionary.
  private func migrate_gui_flags() {
    guard let legacy = defaults.dictionary(forKey: "gui") as? [String: Bool] else { return }
    for (vm, on) in legacy { update_config(for: vm) { $0.gui = on } }
    defaults.removeObject(forKey: "gui")
  }

  // MARK: - Global

  /// Hide VMs whose source is an OCI registry.
  var hide_remote: Bool {
    get { defaults.bool(forKey: "hideRemote") }
    set { defaults.set(newValue, forKey: "hideRemote") }
  }

  /// Guest account used when opening a shell. Tart's stock images use "admin".
  var ssh_user: String { defaults.string(forKey: "sshUser") ?? "admin" }
}
