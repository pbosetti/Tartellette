import Foundation

/// One entry of `tart list --format json`.
struct VM: Decodable, Equatable {
  enum Source: String, Decodable {
    case local = "local"
    case oci = "OCI"
  }

  let name: String
  let state: String
  let running: Bool
  let source: Source
  let disk: Int?
  let size: Int?

  var is_local: Bool { source == .local }

  private enum CodingKeys: String, CodingKey {
    case name = "Name"
    case state = "State"
    case running = "Running"
    case source = "Source"
    case disk = "Disk"
    case size = "Size"
  }
}
