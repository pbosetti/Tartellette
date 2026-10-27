import AppKit

/// Actions for OCI images in tart's cache. Images cannot be run, only cloned into local VMs.
enum ImageActions {
  static let groups: [[VMAction]] = [
    [clone],
    [delete],
  ]

  /// Clones the image to a local VM named after it, e.g.
  /// `ghcr.io/cirruslabs/macos-golden-gate-xcode:latest` -> `golden-gate-xcode`.
  static let clone = VMAction(
    title: "Clone",
    isDone: { _ in false }  // spinner until the clone finishes; cleared by `end`
  ) { image, ctx in
    ctx.perform(on: image.name) {
      defer { ctx.end(image.name) }
      let taken = Set(try await ctx.tart.list().map(\.name))
      try await ctx.tart.clone(image.name, to: unique(default_name(for: image.name), among: taken))
    }
  }

  static let delete = VMAction(title: "Delete…") { image, ctx in
    guard Dialogs.confirm(
      title: "Delete “\(image.name)”?",
      message: "The image is removed from tart's cache. VMs already cloned from it are not affected.",
      button: "Delete", destructive: true)
    else { return }
    ctx.perform { try await ctx.tart.delete(image.name) }
  }

  /// Last path component without tag or digest, and without a leading "macos-".
  static func default_name(for image: String) -> String {
    var name = String(image.split(separator: "/").last ?? Substring(image))
    if let i = name.firstIndex(where: { $0 == "@" || $0 == ":" }) { name = String(name[..<i]) }
    if name.hasPrefix("macos-"), name.count > "macos-".count { name.removeFirst("macos-".count) }
    return name
  }

  private static func unique(_ base: String, among taken: Set<String>) -> String {
    var name = base, n = 2
    while taken.contains(name) { name = "\(base)-\(n)"; n += 1 }
    return name
  }
}
