import AppKit

/// The "Shared Folders" submenu: edits the `--dir` list of a VM's config.
/// Only editable while the VM is stopped: shares are part of the VM's device configuration,
/// so changing them on a suspended VM would make its snapshot unrestorable.
enum SharedFolderActions {
  static let menu = VMAction(
    title: "Shared Folders",
    kind: .submenu(children: { vm, ctx in
      let dirs = ctx.settings.config(for: vm.name).dirs
      return [dirs.indices.map { folder($0, dirs[$0]) }, [add]]
    }),
    isEnabled: { $0.state == "stopped" }
  ) { _, _ in }

  static let add = VMAction(title: "Add Folder…") { vm, ctx in
    let urls = Dialogs.choose_folders(title: "Share Folders with “\(vm.name)”")
    let bad = urls.filter { !valid($0.path) }
    if !bad.isEmpty {
      Dialogs.error("Folder paths cannot contain “:” or “,”:\n\n" + bad.map(\.path).joined(separator: "\n"))
    }
    ctx.settings.update_config(for: vm.name) { config in
      for url in urls where valid(url.path) && !config.dirs.contains(where: { $0.path == url.path }) {
        let name = unique_name(url.lastPathComponent, among: config.dirs.map(\.name))
        config.dirs.append(SharedDir(path: url.path, name: name))
      }
    }
  }

  /// One entry per shared folder, with its own submenu of edits.
  private static func folder(_ index: Int, _ dir: SharedDir) -> VMAction {
    VMAction(
      title: "\(dir.name) — \(dir.display_path)" + (dir.read_only ? " (read-only)" : ""),
      kind: .submenu(children: { _, _ in
        [[read_only(index), edit(index)], [reveal(dir)], [remove(index)]]
      }),
      symbol: dir.exists ? "folder" : "exclamationmark.triangle"
    ) { _, _ in }
  }

  private static func read_only(_ index: Int) -> VMAction {
    VMAction(
      title: "Read-Only",
      kind: .toggle(isOn: { vm, ctx in ctx.settings.config(for: vm.name).dirs[index].read_only })
    ) { vm, ctx in
      ctx.settings.update_config(for: vm.name) { $0.dirs[index].read_only.toggle() }
    }
  }

  private static func edit(_ index: Int) -> VMAction {
    VMAction(title: "Name and Tag…") { vm, ctx in
      let dirs = ctx.settings.config(for: vm.name).dirs
      let dir = dirs[index]
      guard let values = Dialogs.form(
        title: "Shared Folder “\(dir.name)”",
        message: "Name is the folder name inside the guest. Leave Tag empty for automatic mounting "
          + "(/Volumes/My Shared Files on macOS guests).",
        fields: [("Name", dir.name), ("Tag", dir.tag ?? "")])
      else { return }
      let name = values[0], tag = values[1]
      guard !name.isEmpty, valid(name), valid(tag) else {
        return Dialogs.error("Name must not be empty, and name and tag cannot contain “:” or “,”.")
      }
      guard !dirs.enumerated().contains(where: { $0.offset != index && $0.element.name == name }) else {
        return Dialogs.error("Another shared folder is already named “\(name)”.")
      }
      ctx.settings.update_config(for: vm.name) {
        $0.dirs[index].name = name
        $0.dirs[index].tag = tag.isEmpty ? nil : tag
      }
    }
  }

  private static func reveal(_ dir: SharedDir) -> VMAction {
    VMAction(title: "Reveal in Finder", isEnabled: { _ in dir.exists }) { _, _ in
      NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: dir.path)])
    }
  }

  private static func remove(_ index: Int) -> VMAction {
    VMAction(title: "Remove") { vm, ctx in
      ctx.settings.update_config(for: vm.name) { $0.dirs.remove(at: index) }
    }
  }

  /// tart separates the fields of `--dir` with ":" and options with ",".
  private static func valid(_ s: String) -> Bool { !s.contains(":") && !s.contains(",") }

  private static func unique_name(_ base: String, among taken: [String]) -> String {
    let base = base.replacingOccurrences(of: ":", with: "_").replacingOccurrences(of: ",", with: "_")
    var name = base, n = 2
    while taken.contains(name) { name = "\(base)-\(n)"; n += 1 }
    return name
  }
}
