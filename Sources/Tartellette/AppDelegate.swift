import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  private let status_item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let menu = NSMenu()
  private var ctx: AppContext?
  private var builder: MenuBuilder?
  private var timer: Timer?
  private var vms: [VM] = []
  private var error: String?
  private var refreshing = false

  func applicationDidFinishLaunching(_ notification: Notification) {
    if let button = status_item.button {
      // The logo ships in the .app bundle; `swift run` falls back to an SF Symbol.
      if let logo = Bundle.main.image(forResource: "TartLogo") {
        logo.size = NSSize(width: 18, height: 18)
        button.image = logo
      } else {
        button.image = NSImage(systemSymbolName: "shippingbox", accessibilityDescription: "Tartellette")
      }
    }
    menu.delegate = self
    menu.autoenablesItems = false
    status_item.menu = menu

    do {
      let c = AppContext(tart: try TartClient())
      c.refresh = { [weak self] in self?.refresh() }
      c.redraw = { [weak self] in self?.rebuild() }
      ctx = c
      builder = MenuBuilder(ctx: c)
    } catch {
      self.error = error.localizedDescription
    }
    rebuild()
    refresh()

    // Poll every 5 s, or every second while an action is in progress.
    var ticks = 0
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        ticks += 1
        guard let self, ticks % 5 == 0 || !(self.ctx?.busy.isEmpty ?? true) else { return }
        self.refresh()
      }
    }
    RunLoop.main.add(timer!, forMode: .common)  // keep ticking while the menu is open
  }

  func menuWillOpen(_ menu: NSMenu) { refresh() }

  /// Fetches the VM list in the background and rebuilds the menu if anything changed.
  private func refresh() {
    guard let tart = ctx?.tart, !refreshing else { return }
    refreshing = true
    Task {
      defer { refreshing = false }
      do {
        let new_vms = try await tart.list()
        let busy_changed = ctx?.update_busy(with: new_vms) ?? false
        if new_vms != vms || error != nil || busy_changed { vms = new_vms; error = nil; rebuild() }
      } catch {
        self.error = "tart list failed: \(error.localizedDescription)"
        rebuild()
      }
    }
  }

  private func rebuild() {
    if let builder {
      builder.populate(menu, vms: vms, error: error)
    } else {
      menu.removeAllItems()
      let item = NSMenuItem(title: error ?? "tart unavailable", action: nil, keyEquivalent: "")
      item.isEnabled = false
      menu.addItem(item)
      menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }
  }
}
