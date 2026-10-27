import AppKit

enum Terminal {
  /// Writes a .command script and opens it, so macOS picks the user's default terminal handler.
  @MainActor
  static func open_ssh(vm: String, user: String, tart_path: String) throws {
    func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    let script = """
      #!/bin/zsh
      ip=$(\(q(tart_path)) ip \(q(vm))) || { echo "Cannot get IP of VM"; read -k1; exit 1; }
      exec ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \(q(user))@$ip
      """
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Tartellette", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("shell-\(UUID().uuidString).command")
    try script.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    NSWorkspace.shared.open(url)
  }
}
