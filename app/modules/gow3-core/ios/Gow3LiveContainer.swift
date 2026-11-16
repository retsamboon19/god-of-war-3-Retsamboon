// SPDX-License-Identifier: GPL-3.0-or-later
// Running inside LiveContainer: the app is loaded into LiveContainer's own process, so
// - Bundle.main is this app's bundle, but iOS (canOpenURL, StikDebug's app lookup) sees LiveContainer;
// - Documents is this app's LiveContainer data container (LiveContainer/Data/Application/<UUID>/Documents),
//   which users rarely find, so a gow3 folder at LiveContainer's top level is accepted too;
// - the JIT helper extension cannot be started (it is not registered with iOS), so JIT goes through
//   StikDebug attached to LiveContainer's process, or through LiveContainer's own "Launch with JIT".
import Foundation
import MachO

enum Gow3LiveContainer {
  /// LiveContainer sets LC_HOME_PATH to its own home folder before it loads a guest app.
  static var isActive: Bool { getenv("LC_HOME_PATH") != nil }

  /// LiveContainer's own home folder (its Documents is the top level in the Files app).
  static var hostHome: URL? {
    guard let raw = getenv("LC_HOME_PATH") else { return nil }
    let path = String(cString: raw)
    return path.isEmpty ? nil : URL(fileURLWithPath: path, isDirectory: true)
  }

  /// The bundle ID iOS knows this process by: LiveContainer's, read from the Info.plist next to the
  /// main executable (image 0), not through Bundle.main, which LiveContainer points at the guest app.
  static var hostBundleIdentifier: String? {
    guard isActive, let name = _dyld_get_image_name(0) else { return nil }
    let app = URL(fileURLWithPath: String(cString: name)).deletingLastPathComponent()
    let plist = NSDictionary(contentsOf: app.appendingPathComponent("Info.plist"))
    return plist?["CFBundleIdentifier"] as? String
  }

  /// gow3 folders to look in, in order. The first one that holds game files is used.
  static var gameRootCandidates: [URL] {
    let own = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("gow3")
    var roots = [own]
    if let home = hostHome {
      for root in [home.appendingPathComponent("Documents/gow3"), home.appendingPathComponent("gow3")]
      where root.standardizedFileURL != own.standardizedFileURL && !roots.contains(root) {
        roots.append(root)
      }
    }
    return roots
  }
}
