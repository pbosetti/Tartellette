import AppKit

/// The "Settings" submenu: display, CPU and memory of a local VM, changed with `tart set`.
/// Only enabled while the VM is stopped: a suspended VM must resume with the hardware it
/// was saved with.
enum HardwareActions {
  static let menu = VMAction(
    title: "Settings",
    kind: .submenu(children: { vm, _ in
      guard let hw = VMHardware.load(vm: vm.name) else { return [] }
      return [[display(hw), cpu(hw), memory(hw)]]
    }),
    isVisible: { $0.is_local },
    isEnabled: { vm, _ in vm.state == "stopped" }
  ) { _, _ in }

  private static func display(_ hw: VMHardware) -> VMAction {
    let current = hw.display_refit ? "Free" : pretty(hw.display)
    return VMAction(
      title: "Display: \(current)",
      kind: .submenu(children: { _, _ in
        var sizes = VMHardware.resolutions
        if !sizes.contains(hw.display) { sizes.append(hw.display) }  // keep a custom size selectable
        let fixed = sizes.map { size in
          choice(pretty(size), selected: !hw.display_refit && size == hw.display,
            options: ["--display", size, "--no-display-refit"])
        }
        let free = choice("Free (resize with window)", selected: hw.display_refit, options: ["--display-refit"])
        return [fixed, [free]]
      })
    ) { _, _ in }
  }

  private static func cpu(_ hw: VMHardware) -> VMAction {
    VMAction(
      title: "CPU Cores: \(hw.cpu)",
      kind: .submenu(children: { _, _ in
        var counts = hw.cpu_choices
        if !counts.contains(hw.cpu) { counts = (counts + [hw.cpu]).sorted() }
        return [counts.map { choice("\($0)", selected: $0 == hw.cpu, options: ["--cpu", "\($0)"]) }]
      })
    ) { _, _ in }
  }

  private static func memory(_ hw: VMHardware) -> VMAction {
    VMAction(
      title: "Memory: \(gb(hw.memory_mb))",
      kind: .submenu(children: { _, _ in
        var sizes = hw.memory_choices_mb
        if !sizes.contains(hw.memory_mb) { sizes = (sizes + [hw.memory_mb]).sorted() }
        return [sizes.map { choice(gb($0), selected: $0 == hw.memory_mb, options: ["--memory", "\($0)"]) }]
      })
    ) { _, _ in }
  }

  /// A checkmarked entry that runs `tart set <vm> <options>` when picked.
  private static func choice(_ title: String, selected: Bool, options: [String]) -> VMAction {
    VMAction(title: title, kind: .toggle(isOn: { _, _ in selected })) { vm, ctx in
      guard !selected else { return }
      ctx.perform {
        try await ctx.tart.set(vm.name, options)
        ctx.redraw()
      }
    }
  }

  private static func pretty(_ size: String) -> String { size.replacingOccurrences(of: "x", with: " × ") }

  private static func gb(_ mb: Int) -> String {
    mb % 1024 == 0 ? "\(mb / 1024) GB" : String(format: "%.1f GB", Double(mb) / 1024)
  }
}
