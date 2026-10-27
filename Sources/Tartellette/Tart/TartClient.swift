import Foundation

struct TartError: LocalizedError {
  let message: String
  var errorDescription: String? { message }
}

/// Thin wrapper around the `tart` command line tool.
/// New tart subcommands (create, clone, pull, ...) should be added here as methods.
@MainActor
final class TartClient {
  private let executable: URL
  /// VMs whose `tart run` is still bringing the VM up. Running any other tart command
  /// (even `tart list`) while a VM boots or restores from a snapshot makes it fail with
  /// VZErrorDomain Code=1, so `run` holds every command until this is empty.
  private var starting: Set<String> = []
  /// Cold boots log nothing when the VM is up; polling from 3 s on proved safe.
  private let boot_hold: TimeInterval = 5

  init() throws {
    guard let url = TartClient.locate() else {
      throw TartError(message: "Cannot find the `tart` executable. Install it with `brew install cirruslabs/cli/tart`.")
    }
    executable = url
  }

  var path: String { executable.path }

  private static func locate() -> URL? {
    var dirs = ["/opt/homebrew/bin", "/usr/local/bin"]
    dirs += (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
    for dir in dirs {
      let candidate = URL(fileURLWithPath: dir).appendingPathComponent("tart")
      if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
    }
    return nil
  }

  // MARK: - Queries

  func list() async throws -> [VM] {
    let out = try await run(["list", "--format", "json"])
    return try JSONDecoder().decode([VM].self, from: Data(out.utf8))
  }

  /// `tart get --format json` as display-ready (label, value) rows: well-known keys first, then the rest alphabetically.
  func info(_ name: String) async throws -> [(String, String)] {
    let out = try await run(["get", name, "--format", "json"])
    guard let dict = try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any] else {
      throw TartError(message: "Unexpected output from tart get:\n\(out)")
    }
    let order = ["State", "OS", "CPU", "Memory", "Disk", "Size", "DiskFormat", "Display", "MACAddress"]
    let units = ["Memory": "MB", "Disk": "GB", "Size": "GB"]
    let keys = order.filter { dict[$0] != nil } + dict.keys.filter { !order.contains($0) }.sorted()
    return keys.map { key in
      var value: String
      if let n = dict[key] as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() {
        value = n.boolValue ? "yes" : "no"
      } else {
        value = dict[key].map { "\($0)" } ?? ""
      }
      if let unit = units[key] { value += " \(unit)" }
      return (key, value)
    }
  }

  func ip(_ name: String) async throws -> String {
    try await run(["ip", name])
  }

  // MARK: - Commands

  func stop(_ name: String) async throws { _ = try await run(["stop", name]) }
  func suspend(_ name: String) async throws { _ = try await run(["suspend", name]) }
  func delete(_ name: String) async throws { _ = try await run(["delete", name]) }
  func rename(_ name: String, to new_name: String) async throws {
    _ = try await run(["rename", name, new_name])
  }

  /// `tart run` is long lived: launch it detached and only report an early failure.
  /// Output goes to ~/Library/Logs/Tartellette/<vm>.log.
  /// Other commands are held until the VM is up: `resuming` (VM is suspended) waits for the
  /// restore to finish, a cold boot waits `boot_hold` seconds.
  func start(_ name: String, config: VMConfig, resuming: Bool, onEarlyFailure: @escaping @MainActor (String) -> Void) throws {
    let log_url = try logURL(for: name)
    FileManager.default.createFile(atPath: log_url.path, contents: nil)
    let log = try FileHandle(forWritingTo: log_url)

    let p = Process()
    p.executableURL = executable
    p.arguments = ["run"] + config.run_arguments + [name]
    p.standardOutput = log
    p.standardError = log
    p.standardInput = FileHandle.nullDevice
    let started = Date()
    p.terminationHandler = { proc in
      try? log.close()
      guard proc.terminationStatus != 0, Date().timeIntervalSince(started) < 30 else { return }
      let text = (try? String(contentsOf: log_url, encoding: .utf8)) ?? ""
      let msg = text.trimmingCharacters(in: .whitespacesAndNewlines)
      Task { @MainActor in onEarlyFailure(msg.isEmpty ? "tart run exited with status \(proc.terminationStatus)" : msg) }
    }
    try p.run()
    hold_until_up(name, process: p, log: log_url, resuming: resuming)
  }

  private func hold_until_up(_ name: String, process: Process, log: URL, resuming: Bool) {
    starting.insert(name)
    let since = Date()
    Task {
      defer { starting.remove(name) }
      while Date().timeIntervalSince(since) < 60 {
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard process.isRunning else { return }
        if resuming {
          if let text = try? String(contentsOf: log, encoding: .utf8), text.contains("resuming VM") { return }
        } else if Date().timeIntervalSince(since) >= boot_hold {
          return
        }
      }
    }
  }

  private func logURL(for name: String) throws -> URL {
    let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Logs/Tartellette")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let safe = name.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." ? $0 : "_" }
    return dir.appendingPathComponent(String(safe) + ".log")
  }

  // MARK: - Process plumbing

  /// Runs tart to completion and returns trimmed stdout. Throws with stderr on non-zero exit.
  func run(_ args: [String]) async throws -> String {
    while !starting.isEmpty { try await Task.sleep(nanoseconds: 250_000_000) }
    let exe = executable
    return try await withCheckedThrowingContinuation { cont in
      DispatchQueue.global(qos: .userInitiated).async {
        let p = Process()
        p.executableURL = exe
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return cont.resume(throwing: error) }

        var err_data = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
          err_data = err.fileHandleForReading.readDataToEndOfFile()
          group.leave()
        }
        let out_data = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        p.waitUntilExit()

        let stdout = String(decoding: out_data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = String(decoding: err_data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if p.terminationStatus == 0 {
          cont.resume(returning: stdout)
        } else {
          cont.resume(throwing: TartError(message: stderr.isEmpty ? "tart \(args.first ?? "") failed (status \(p.terminationStatus))" : stderr))
        }
      }
    }
  }
}
