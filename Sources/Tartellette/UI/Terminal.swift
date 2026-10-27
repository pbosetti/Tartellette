import AppKit
import UniformTypeIdentifiers

enum Terminal {
  /// The user's default terminal: the app that opens executable files. iTerm2's
  /// "Make iTerm2 Default Term" registers for these, while `.command` files stay with Terminal.
  static var app: URL {
    NSWorkspace.shared.urlForApplication(toOpen: .unixExecutable)
      ?? URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
  }

  /// Writes an executable script and has the default terminal run it.
  @MainActor
  static func open_ssh(vm: String, user: String, tart_path: String) throws {
    func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    let script = """
      #!/bin/zsh
      rm -f "$0"
      ip=$(\(q(tart_path)) ip \(q(vm))) || { echo "Cannot get IP of VM"; read -k1; exit 1; }
      exec ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \(q(user))@$ip
      """
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Tartellette", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    // No extension: a ".command" file would always go to Terminal.
    let url = dir.appendingPathComponent("ssh-\(vm.filter { $0.isLetter || $0.isNumber || $0 == "-" })-\(UUID().uuidString.prefix(8))")
    try script.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)

    NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
      guard let error else { return }
      Task { @MainActor in Dialogs.error("Could not open a terminal:\n\n\(error.localizedDescription)") }
    }
  }
}
