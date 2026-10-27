import AppKit

/// Everything an action may need. Passed to actions instead of reaching for globals.
@MainActor
final class AppContext {
  /// A long running action on a VM, shown with a spinner until `isDone` holds.
  struct Busy {
    let action: String
    let isDone: (VM) -> Bool
    let since = Date()
  }

  let tart: TartClient
  let settings = Settings()
  /// Re-reads the VM list from tart.
  var refresh: () -> Void = {}
  /// Rebuilds the menu from cached state (e.g. after a display setting changed).
  var redraw: () -> Void = {}
  /// In-progress actions, keyed by VM name.
  private(set) var busy: [String: Busy] = [:]

  init(tart: TartClient) { self.tart = tart }

  func report(_ error: Error) {
    Dialogs.error(error.localizedDescription)
  }

  /// Runs `body`, shows any error, and refreshes the VM list afterwards.
  /// On error the busy state of `vm` (if any) is cleared.
  func perform(on vm: String? = nil, _ body: @escaping () async throws -> Void) {
    Task {
      do { try await body() } catch {
        if let vm { end(vm) }
        report(error)
      }
      refresh()
    }
  }

  func begin(_ action: VMAction, on vm: VM) { begin(action, on: vm.name) }

  func begin(_ action: VMAction, on name: String) {
    guard let isDone = action.isDone else { return }
    busy[name] = Busy(action: action.title, isDone: isDone)
    redraw()
  }

  func end(_ vm: String) {
    if busy.removeValue(forKey: vm) != nil { redraw() }
  }

  /// Clears busy entries that completed, vanished, or timed out. Returns true if any changed.
  func update_busy(with vms: [VM]) -> Bool {
    let before = busy.count
    busy = busy.filter { name, b in
      guard let vm = vms.first(where: { $0.name == name }) else { return false }
      return !b.isDone(vm) && Date().timeIntervalSince(b.since) < 120
    }
    return busy.count != before
  }
}

/// A command shown in a VM's submenu. To add a feature, append a VMAction to a group in
/// `VMActions.groups`; the menu builder needs no change.
struct VMAction {
  enum Kind {
    case command
    case toggle(isOn: @MainActor (VM, AppContext) -> Bool)
    /// A nested menu whose entries (groups separated by dividers) are computed when the menu is built.
    case submenu(children: @MainActor (VM, AppContext) -> [[VMAction]])
  }

  let title: String
  var kind: Kind = .command
  /// SF Symbol shown beside the title.
  var symbol: String? = nil
  var isVisible: (VM) -> Bool = { _ in true }
  var isEnabled: @MainActor (VM, AppContext) -> Bool = { _, _ in true }
  /// Shown on hover, e.g. to explain why the entry is disabled.
  var toolTip: String? = nil
  /// For long running actions: the VM shows a spinner until this holds.
  var isDone: ((VM) -> Bool)? = nil
  /// Unused for `.submenu` actions.
  let perform: @MainActor (VM, AppContext) -> Void
}
