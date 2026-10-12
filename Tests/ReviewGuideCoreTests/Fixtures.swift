import Foundation

enum Fixture {
    static func text(_ name: String) throws -> String {
        let url = Bundle.module.url(forResource: "Fixtures", withExtension: nil)!.appendingPathComponent(name)
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func diff(_ name: String) throws -> String { try text("diffs/\(name).diff") }
}
