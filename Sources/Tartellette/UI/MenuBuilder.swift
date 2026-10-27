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
      let local = vms.filter(\.is_local)
      let images = vms.filter { !$0.is_local }
      if local.isEmpty {
        let item = NSMenuItem(title: "No virtual machines", action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
      }
      for vm in local { menu.addItem(vm_item(vm, actions: VMActions.groups)) }

      // OCI images cannot be run directly, only cloned into a local VM.
      if !images.isEmpty {
        menu.addItem(.separator())
        let header = NSMenuItem(title: "OCI Images", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for image in images { menu.addItem(vm_item(image, actions: ImageActions.groups)) }
      }
    }

    menu.addItem(.separator())
    menu.addItem(item("Quit Tartellette", key: "q") { NSApp.terminate(nil) })
  }

  private func vm_item(_ vm: VM, actions: [[VMAction]]) -> NSMenuItem {
    let title = vm.is_local ? vm.name : short_image_name(vm.name)
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    if let busy = ctx.busy[vm.name] {
      spin(item)
      item.toolTip = "\(busy.action)…"
    } else {
      item.image = vm.is_local ? status_dot(for: vm) : NSImage(systemSymbolName: "shippingbox", accessibilityDescription: "OCI image")
      item.toolTip = vm.is_local ? vm.state : vm.name
    }

    item.submenu = submenu(actions, vm: vm)
    return item
  }

  private func submenu(_ groups: [[VMAction]], vm: VM) -> NSMenu {
    let sub = NSMenu()
    sub.autoenablesItems = false
    for group in groups {
      let items = group.filter { $0.isVisible(vm) }.map { action_item($0, vm: vm) }
      guard !items.isEmpty else { continue }
      if sub.items.count > 0 { sub.addItem(.separator()) }
      items.forEach(sub.addItem)
    }
    return sub
  }

  private func action_item(_ action: VMAction, vm: VM) -> NSMenuItem {
    let ctx = self.ctx
    let it: NSMenuItem
    switch action.kind {
    case .submenu(let children):
      it = NSMenuItem(title: action.title, action: nil, keyEquivalent: "")
      it.submenu = submenu(children(vm, ctx), vm: vm)
    case .toggle(let is_on):
      it = item(action.title) { action.perform(vm, ctx); ctx.redraw() }
      it.state = is_on(vm, ctx) ? .on : .off
    case .command:
      it = item(action.title) {
        ctx.begin(action, on: vm)
        action.perform(vm, ctx)
        ctx.redraw()
      }
    }
    if let symbol = action.symbol {
      it.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    }
    it.isEnabled = action.isEnabled(vm, ctx)
    it.toolTip = action.toolTip
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

  /// OCI names are long registry paths: keep the last component, and shorten a digest to its
  /// last 7 hex digits (`img@sha256:…d9b61b9` -> `img:d9b61b9`). The full name is in the tooltip.
  private func short_image_name(_ name: String) -> String {
    let last = String(name.split(separator: "/").last ?? Substring(name))
    guard let at = last.range(of: "@sha256:") else { return last }
    return last[..<at.lowerBound] + ":" + last[at.upperBound...].suffix(7)
  }

  private func status_dot(for vm: VM) -> NSImage? {
    let color: NSColor = vm.running ? .systemGreen : (vm.state == "suspended" ? .systemOrange : .tertiaryLabelColor)
    let cfg = NSImage.SymbolConfiguration(paletteColors: [color])
    return NSImage(systemSymbolName: "circle.fill", accessibilityDescription: vm.state)?
      .withSymbolConfiguration(cfg)
  }
}
