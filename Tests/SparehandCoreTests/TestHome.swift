import Foundation

/// A throwaway directory tree for file tests.
struct TestDir {
    let url: URL
    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("sh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    @discardableResult
    func file(_ rel: String, _ text: String = "x", created: Date? = nil) throws -> URL {
        let u = url.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: u)
        if let created { try FileManager.default.setAttributes([.creationDate: created, .modificationDate: created], ofItemAtPath: u.path) }
        return u
    }
    func exists(_ rel: String) -> Bool { FileManager.default.fileExists(atPath: url.appendingPathComponent(rel).path) }
    func read(_ rel: String) -> String? { try? String(contentsOf: url.appendingPathComponent(rel), encoding: .utf8) }
    func at(_ rel: String) -> URL { url.appendingPathComponent(rel) }
}
