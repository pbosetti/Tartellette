import AppKit

/// Modal helpers. The app is an accessory (no Dock icon), so each one activates it first.
@MainActor
enum Dialogs {
  static func error(_ message: String) {
    NSApp.activate(ignoringOtherApps: true)
    let a = NSAlert()
    a.alertStyle = .warning
    a.messageText = "Tart error"
    a.informativeText = message
    a.runModal()
  }

  static func confirm(title: String, message: String, button: String, destructive: Bool = false) -> Bool {
    NSApp.activate(ignoringOtherApps: true)
    let a = NSAlert()
    a.alertStyle = destructive ? .critical : .informational
    a.messageText = title
    a.informativeText = message
    let b = a.addButton(withTitle: button)
    if destructive { b.hasDestructiveAction = true }
    a.addButton(withTitle: "Cancel")
    return a.runModal() == .alertFirstButtonReturn
  }

  static func prompt(title: String, message: String, initial: String) -> String? {
    NSApp.activate(ignoringOtherApps: true)
    let a = NSAlert()
    a.messageText = title
    a.informativeText = message
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
    field.stringValue = initial
    a.accessoryView = field
    a.addButton(withTitle: "OK")
    a.addButton(withTitle: "Cancel")
    a.window.initialFirstResponder = field
    guard a.runModal() == .alertFirstButtonReturn else { return nil }
    return field.stringValue.trimmingCharacters(in: .whitespaces)
  }

  /// Shows (label, value) rows as a two-column table. Values are selectable for copying.
  static func info(title: String, rows: [(String, String)]) {
    NSApp.activate(ignoringOtherApps: true)
    let a = NSAlert()
    a.messageText = title
    let grid = NSGridView(views: rows.map { label, value in
      let l = NSTextField(labelWithString: label)
      l.textColor = .secondaryLabelColor
      let v = NSTextField(labelWithString: value)
      v.isSelectable = true
      v.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
      return [l, v]
    })
    grid.rowSpacing = 4
    grid.columnSpacing = 12
    grid.column(at: 0).xPlacement = .trailing
    grid.rowAlignment = .firstBaseline
    grid.frame.size = grid.fittingSize
    a.accessoryView = grid
    a.addButton(withTitle: "OK")
    a.runModal()
  }
}
