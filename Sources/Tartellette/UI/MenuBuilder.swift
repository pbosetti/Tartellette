import AppKit

/// Keeps a closure alive as an NSMenuItem target.
private final class Handler: NSObject {
  let body: () -> Void
  init(_ body: @escaping () -> Void) { self.body = body }
  @objc func fire() { body() }
}

@MainActor
final class MenuBuilder {
  private let ctx: AppContext
  private var handlers: [Handler] = []
  /// Items showing a spinner, animated by `animation`.
  private var spinning: [NSMenuItem] = []
  private var animation: Timer?
  private var frame = 0

  init(ctx: AppContext) { self.ctx = ctx }

  /// Rebuilds `menu` from the given state. `error` is shown instead of the VM list when set.
  func populate(_ menu: NSMenu, vms: [VM], error: String?) {
    menu.removeAllItems()
    handlers.removeAll()
    spinning.removeAll()
    defer { update_animation() }

    if let error {
      let item = NSMenuItem(title: error, action: nil, keyEquivalent: "")
      item.isEnabled = false
      menu.addItem(item)
    } else {
      let shown = ctx.settings.hide_remote ? vms.filter(\.is_local) : vms
      if shown.isEmpty {
        let title = vms.isEmpty ? "No virtual machines" : "No local virtual machines"
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
      }
      for vm in shown { menu.addItem(vm_item(vm)) }
    }

    menu.addItem(.separator())
    let ctx = self.ctx
    let hide = item("Hide Remote (OCI) Images") {
      ctx.settings.hide_remote.toggle()
      ctx.redraw()
    }
    hide.state = ctx.settings.hide_remote ? .on : .off
    menu.addItem(hide)

    menu.addItem(.separator())
    menu.addItem(item("Quit Tartellette", key: "q") { NSApp.terminate(nil) })
  }

  private func vm_item(_ vm: VM) -> NSMenuItem {
    let item = NSMenuItem(title: vm.name, action: nil, keyEquivalent: "")
    if let busy = ctx.busy[vm.name] {
      spin(item)
      item.toolTip = "\(busy.action)…"
    } else {
      item.image = status_dot(for: vm)
      item.toolTip = vm.state
    }

    let sub = NSMenu()
    sub.autoenablesItems = false
    for group in VMActions.groups {
      let items = group.filter { $0.isVisible(vm) }.map { action_item($0, vm: vm) }
      guard !items.isEmpty else { continue }
      if sub.items.count > 0 { sub.addItem(.separator()) }
      items.forEach(sub.addItem)
    }
    item.submenu = sub
    return item
  }

  private func action_item(_ action: VMAction, vm: VM) -> NSMenuItem {
    let ctx = self.ctx
    let it = item(action.title) {
      ctx.begin(action, on: vm)
      action.perform(vm, ctx)
      ctx.redraw()
    }
    if case .toggle(let is_on) = action.kind { it.state = is_on(vm, ctx) ? .on : .off }
    // While a long running action is in progress, block the others and mark the active one.
    if let busy = ctx.busy[vm.name], action.isDone != nil {
      it.isEnabled = false
      if busy.action == action.title { spin(it) }
    }
    return it
  }

  private func spin(_ item: NSMenuItem) {
    item.image = Spinner.frames[frame]
    spinning.append(item)
  }

  private func update_animation() {
    if spinning.isEmpty {
      animation?.invalidate()
      animation = nil
    } else if animation == nil {
      let t = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated { self?.advance() }
      }
      RunLoop.main.add(t, forMode: .common)  // animate while the menu is tracking
      animation = t
    }
  }

  private func advance() {
    frame = (frame + 1) % Spinner.spokes
    for item in spinning { item.image = Spinner.frames[frame] }
  }

  private func item(_ title: String, key: String = "", _ body: @escaping () -> Void) -> NSMenuItem {
    let h = Handler(body)
    handlers.append(h)
    let it = NSMenuItem(title: title, action: #selector(Handler.fire), keyEquivalent: key)
    it.target = h
    return it
  }

  private func status_dot(for vm: VM) -> NSImage? {
    let color: NSColor = vm.running ? .systemGreen : (vm.state == "suspended" ? .systemOrange : .tertiaryLabelColor)
    let cfg = NSImage.SymbolConfiguration(paletteColors: [color])
    return NSImage(systemSymbolName: "circle.fill", accessibilityDescription: vm.state)?
      .withSymbolConfiguration(cfg)
  }
}
