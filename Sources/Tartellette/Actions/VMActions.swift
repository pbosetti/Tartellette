import AppKit

/// The per-VM menu, as groups separated by dividers.
enum VMActions {
  static let groups: [[VMAction]] = [
    [start, stop, suspend],
    [gui_toggle, SharedFolderActions.menu],
    [copy_ip, copy_ssh, open_shell, info],
    [rename, delete],
  ]

  static let start = VMAction(
    title: "Start",
    isVisible: { !$0.running },
    isDone: { $0.running }
  ) { vm, ctx in
    let config = ctx.settings.config(for: vm.name)
    let missing = config.dirs.filter { !$0.exists }
    guard missing.isEmpty else {
      ctx.end(vm.name)
      Dialogs.error("Cannot start “\(vm.name)”: these shared folders are missing:\n\n"
        + missing.map { "• \($0.display_path)" }.joined(separator: "\n")
        + "\n\nRestore them or remove them from Shared Folders.")
      return
    }
    do {
      try ctx.tart.start(vm.name, config: config, resuming: vm.state == "suspended") {
        ctx.end(vm.name)
        Dialogs.error("Could not start “\(vm.name)”:\n\n\($0)")
        ctx.refresh()
      }
    } catch {
      ctx.end(vm.name)
      ctx.report(error)
    }
    ctx.refresh()
  }

  static let stop = VMAction(
    title: "Stop",
    isVisible: { $0.running },
    isDone: { !$0.running }
  ) { vm, ctx in ctx.perform(on: vm.name) { try await ctx.tart.stop(vm.name) } }

  static let suspend = VMAction(
    title: "Suspend",
    isVisible: { $0.running },
    isDone: { $0.state == "suspended" }
  ) { vm, ctx in ctx.perform(on: vm.name) { try await ctx.tart.suspend(vm.name) } }

  static let gui_toggle = VMAction(
    title: "Show GUI on Start",
    kind: .toggle(isOn: { vm, ctx in ctx.settings.config(for: vm.name).gui })
  ) { vm, ctx in
    ctx.settings.update_config(for: vm.name) { $0.gui.toggle() }
  }

  static let copy_ip = VMAction(
    title: "Copy IP Address",
    isVisible: { $0.running }
  ) { vm, ctx in
    ctx.perform {
      let ip = try await ctx.tart.ip(vm.name)
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(ip, forType: .string)
    }
  }

  static let copy_ssh = VMAction(
    title: "Copy SSH Command",
    isVisible: { $0.running }
  ) { vm, ctx in
    ctx.perform {
      let ip = try await ctx.tart.ip(vm.name)
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString("ssh \(ctx.settings.ssh_user)@\(ip)", forType: .string)
    }
  }

  static let open_shell = VMAction(
    title: "Open Shell in Terminal",
    isVisible: { $0.running }
  ) { vm, ctx in
    do { try Terminal.open_ssh(vm: vm.name, user: ctx.settings.ssh_user, tart_path: ctx.tart.path) }
    catch { ctx.report(error) }
  }

  static let info = VMAction(title: "Info…") { vm, ctx in
    ctx.perform {
      let rows = try await ctx.tart.info(vm.name)
      Dialogs.info(title: vm.name, rows: rows)
    }
  }

  static let rename = VMAction(
    title: "Rename…",
    isVisible: { $0.is_local && !$0.running }
  ) { vm, ctx in
    guard let new_name = Dialogs.prompt(title: "Rename “\(vm.name)”", message: "New name:", initial: vm.name),
      !new_name.isEmpty, new_name != vm.name
    else { return }
    ctx.perform {
      try await ctx.tart.rename(vm.name, to: new_name)
      ctx.settings.move_settings(from: vm.name, to: new_name)
    }
  }

  static let delete = VMAction(
    title: "Delete…",
    isVisible: { !$0.running }
  ) { vm, ctx in
    guard Dialogs.confirm(
      title: "Delete “\(vm.name)”?",
      message: "The VM and its disk will be permanently removed. This cannot be undone.",
      button: "Delete", destructive: true)
    else { return }
    ctx.perform {
      try await ctx.tart.delete(vm.name)
      ctx.settings.remove_settings(for: vm.name)
    }
  }
}
