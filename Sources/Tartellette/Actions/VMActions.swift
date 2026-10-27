import AppKit

/// The per-VM menu, as groups separated by dividers.
enum VMActions {
  static let groups: [[VMAction]] = [
    [start, resume, stop, suspend],
    [gui_toggle, suspendable_toggle, HardwareActions.menu, SharedFolderActions.menu],
    [copy_ip, copy_ssh, open_shell, info],
    [rename, delete],
  ]

  static let start = VMAction(
    title: "Start",
    isVisible: { $0.state == "stopped" },
    isDone: { $0.running },
    perform: start_or_resume)

  static let resume = VMAction(
    title: "Resume",
    isVisible: { $0.state == "suspended" },
    isDone: { $0.running },
    perform: start_or_resume)

  /// `tart run` does both: it restores the snapshot when the VM is suspended.
  @MainActor
  private static func start_or_resume(_ vm: VM, _ ctx: AppContext) {
    let config = ctx.settings.config(for: vm.name)
    let missing = config.dirs.filter { !$0.exists }
    guard missing.isEmpty else {
      ctx.end(vm.name)
      Dialogs.error("Cannot start “\(vm.name)”: these shared folders are missing:\n\n"
        + missing.map { "• \($0.display_path)" }.joined(separator: "\n")
        + "\n\nRestore them or remove them from Shared Folders.")
      return
    }
    launch(vm.name, config: config, resuming: vm.state == "suspended", ctx: ctx)
  }

  @MainActor
  private static func launch(_ name: String, config: VMConfig, resuming: Bool, ctx: AppContext) {
    do {
      try ctx.tart.start(name, config: config, resuming: resuming) { message in
        ctx.end(name)
        ctx.refresh()
        if resuming && message.contains("failed to restore") {
          offer_discard(name, config: config, message: message, ctx: ctx)
        } else {
          Dialogs.error("Could not start “\(name)”:\n\n\(message)")
        }
      }
    } catch {
      ctx.end(name)
      ctx.report(error)
    }
    ctx.refresh()
  }

  /// A snapshot that cannot be restored stays unusable; the only way out is to drop it
  /// (`tart stop` on a suspended VM) and boot normally.
  @MainActor
  private static func offer_discard(_ name: String, config: VMConfig, message: String, ctx: AppContext) {
    guard Dialogs.confirm(
      title: "Cannot resume “\(name)”",
      message: "The saved state could not be restored:\n\n\(message)\n\n"
        + "Discard the saved state and start the VM from scratch? Unsaved work inside the VM is lost, "
        + "as after a power failure.",
      button: "Discard and Start", destructive: true)
    else { return }
    ctx.perform(on: name) {
      try await ctx.tart.stop(name)
      ctx.begin(start, on: name)
      launch(name, config: config, resuming: false, ctx: ctx)
    }
  }

  static let stop = VMAction(
    title: "Stop",
    isVisible: { $0.running || $0.state == "suspended" },
    isDone: { $0.state == "stopped" }
  ) { vm, ctx in
    // Stopping a suspended VM throws away its saved state.
    if vm.state == "suspended" {
      guard Dialogs.confirm(
        title: "Stop “\(vm.name)”?",
        message: "The VM is suspended. Stopping it discards its saved state: "
          + "unsaved work inside the VM is lost, as after a power failure.",
        button: "Stop", destructive: true)
      else { return ctx.end(vm.name) }
    }
    ctx.perform(on: vm.name) { try await ctx.tart.stop(vm.name) }
  }

  static let suspend = VMAction(
    title: "Suspend",
    isVisible: { $0.running },
    isEnabled: { vm, ctx in ctx.settings.config(for: vm.name).suspendable },
    toolTip: "Requires “Allow Suspend” to be on when the VM is started",
    isDone: { $0.state == "suspended" }
  ) { vm, ctx in ctx.perform(on: vm.name) { try await ctx.tart.suspend(vm.name) } }

  static let gui_toggle = VMAction(
    title: "Show GUI on Start",
    kind: .toggle(isOn: { vm, ctx in ctx.settings.config(for: vm.name).gui })
  ) { vm, ctx in
    ctx.settings.update_config(for: vm.name) { $0.gui.toggle() }
  }

  static let suspendable_toggle = VMAction(
    title: "Allow Suspend (No Audio)",
    kind: .toggle(isOn: { vm, ctx in ctx.settings.config(for: vm.name).suspendable }),
    isEnabled: { vm, _ in vm.state == "stopped" },
    toolTip: "Starts the VM with --suspendable. Only a VM started this way can be suspended and resumed."
  ) { vm, ctx in
    ctx.settings.update_config(for: vm.name) { $0.suspendable.toggle() }
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
