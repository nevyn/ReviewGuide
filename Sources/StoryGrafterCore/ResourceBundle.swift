import Foundation

/// Finds SwiftPM resource bundles next to the real executable.
///
/// `Bundle.module` and `Bundle.main` look beside the path the process was launched through, so they miss
/// bundles when Homebrew links `bin/storygrafter` to `libexec/storygrafter`. This resolves the symlink first.
public enum ResourceBundle {
    /// The bundle `<name>.bundle` beside the resolved executable, or `nil` when there is none (as in `swift test`,
    /// where callers fall back to `Bundle.module`). `name` is SwiftPM's `<Package>_<Target>`, e.g. `StoryGrafter_Render`.
    public static func named(_ name: String) -> Bundle? {
        guard let dir = executableDirectory else { return nil }
        return Bundle(url: dir.appendingPathComponent("\(name).bundle"))
    }

    static var executableDirectory: URL? {
        var size: UInt32 = 0
        _NSGetExecutablePath(nil, &size)
        var buffer = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&buffer, &size) == 0, let real = realpath(buffer, nil) else { return nil }
        defer { free(real) }
        return URL(fileURLWithPath: String(cString: real)).deletingLastPathComponent()
    }
}
