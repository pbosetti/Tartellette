import Foundation

/// A host directory shared with the guest via `tart run --dir`.
struct SharedDir: Codable, Equatable {
  var path: String
  /// Directory name under the guest mount point. Required by tart when several dirs share a tag.
  var name: String
  var read_only = false
  /// Mount tag; nil uses tart's default automount tag ("/Volumes/My Shared Files" on macOS guests).
  var tag: String?

  /// The value for `--dir`: `name:path[:ro,tag=x]`.
  var argument: String {
    var options: [String] = []
    if read_only { options.append("ro") }
    if let tag { options.append("tag=\(tag)") }
    return "\(name):\(path)" + (options.isEmpty ? "" : ":" + options.joined(separator: ","))
  }

  var exists: Bool {
    var is_dir: ObjCBool = false
    return FileManager.default.fileExists(atPath: path, isDirectory: &is_dir) && is_dir.boolValue
  }

  /// Path with the home directory abbreviated to ~.
  var display_path: String { (path as NSString).abbreviatingWithTildeInPath }
}

/// Per-VM options used when starting it. Add new `tart run` options here.
struct VMConfig: Codable, Equatable {
  var gui = true
  /// Boot with `--suspendable` (no audio/entropy devices). A VM cold-booted without it can be
  /// suspended, but its snapshot then fails to restore (VZErrorDomain Code=12), because tart
  /// always restores with the suspendable device set.
  var suspendable = true
  var dirs: [SharedDir] = []

  var run_arguments: [String] {
    (gui ? [] : ["--no-graphics"]) + (suspendable ? ["--suspendable"] : []) + dirs.map { "--dir=\($0.argument)" }
  }

  init() {}

  // Tolerate configs saved by older versions that lack newer keys.
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    gui = try c.decodeIfPresent(Bool.self, forKey: .gui) ?? true
    suspendable = try c.decodeIfPresent(Bool.self, forKey: .suspendable) ?? true
    dirs = try c.decodeIfPresent([SharedDir].self, forKey: .dirs) ?? []
  }
}
