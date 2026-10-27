import Foundation

/// Hardware settings of a local VM, read from its config.json. Changes go through `tart set`.
struct VMHardware {
  var cpu: Int
  var cpu_min: Int
  var memory_mb: Int
  var memory_min_mb: Int
  var display_width: Int
  var display_height: Int
  var display_refit: Bool

  var display: String { "\(display_width)x\(display_height)" }

  /// Reads `$TART_HOME/vms/<name>/config.json` (TART_HOME defaults to ~/.tart).
  /// Returns nil for VMs without a local config (e.g. OCI images).
  static func load(vm name: String) -> VMHardware? {
    let home = ProcessInfo.processInfo.environment["TART_HOME"]
      ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".tart").path
    let url = URL(fileURLWithPath: home).appendingPathComponent("vms").appendingPathComponent(name)
      .appendingPathComponent("config.json")
    guard let data = try? Data(contentsOf: url),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    let display = json["display"] as? [String: Any] ?? [:]
    let mb = 1024 * 1024
    return VMHardware(
      cpu: json["cpuCount"] as? Int ?? 0,
      cpu_min: json["cpuCountMin"] as? Int ?? 1,
      memory_mb: (json["memorySize"] as? Int ?? 0) / mb,
      memory_min_mb: (json["memorySizeMin"] as? Int ?? 0) / mb,
      display_width: display["width"] as? Int ?? 0,
      display_height: display["height"] as? Int ?? 0,
      display_refit: json["displayRefit"] as? Bool ?? false)
  }

  // MARK: - Choices offered in the menu

  static let resolutions = [
    "1024x768", "1280x720", "1280x800", "1280x1024", "1366x768",
    "1440x900", "1600x900", "1680x1050", "1920x1080",
  ]

  /// From 2 (or the VM's minimum) to all host cores but one.
  var cpu_choices: [Int] {
    let low = max(2, cpu_min)
    return Array(low...max(low, ProcessInfo.processInfo.processorCount - 1))
  }

  /// In MB, from 4 GB (or the VM's minimum) to half the host memory, in whole GB steps
  /// (2 GB steps when the list would get long).
  var memory_choices_mb: [Int] {
    let gb = 1024
    let low = max(4, (memory_min_mb + gb - 1) / gb)
    let high = max(low, Int(ProcessInfo.processInfo.physicalMemory / 1024 / 1024) / 2 / gb)
    let step = high - low > 24 ? 2 : 1
    return stride(from: low, through: high, by: step).map { $0 * gb }
  }
}
