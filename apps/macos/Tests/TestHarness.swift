import Foundation

/// Minimal test harness. Command Line Tools ship neither XCTest nor
/// swift-testing, so ThoughtMeter uses this zero-dependency runner via
/// `swift run thoughtmeter-tests` (wired to `make test`).
/// The assertion API mirrors XCTest naming to ease future migration.

final class T {
    private(set) var failures: [String] = []

    func fail(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let filename = ("\(file)" as NSString).lastPathComponent
        failures.append("\(filename):\(line): \(message)")
    }

    func expect(_ condition: Bool, _ message: String = "expected true",
                file: StaticString = #filePath, line: UInt = #line) {
        if !condition { fail(message, file: file, line: line) }
    }

    func expectEqual<E: Equatable>(_ actual: E, _ expected: E, _ message: String = "",
                                   file: StaticString = #filePath, line: UInt = #line) {
        if actual != expected {
            fail("expected \(expected), got \(actual)\(message.isEmpty ? "" : " — \(message)")",
                 file: file, line: line)
        }
    }

    func expectNil<V>(_ value: V?, _ message: String = "expected nil",
                      file: StaticString = #filePath, line: UInt = #line) {
        if let value { fail("\(message), got \(value)", file: file, line: line) }
    }

    func expectNotNil<V>(_ value: V?, _ message: String = "expected non-nil",
                         file: StaticString = #filePath, line: UInt = #line) -> V? {
        if value == nil { fail(message, file: file, line: line) }
        return value
    }

    func expectNoThrow<R>(_ body: () throws -> R, _ message: String = "unexpected error",
                          file: StaticString = #filePath, line: UInt = #line) -> R? {
        do { return try body() } catch {
            fail("\(message): \(error)", file: file, line: line)
            return nil
        }
    }
}

struct TC {
    let name: String
    let body: (T) throws -> Void

    init(_ name: String, _ body: @escaping (T) throws -> Void) {
        self.name = name
        self.body = body
    }
}

func runSuites(_ suites: [(name: String, cases: [TC])]) -> Int32 {
    var passed = 0
    var failed = 0
    let started = Date()

    for suite in suites {
        print("▸ \(suite.name)")
        for testCase in suite.cases {
            let t = T()
            var thrown: Error?
            do { try testCase.body(t) } catch { thrown = error }

            if t.failures.isEmpty && thrown == nil {
                passed += 1
                print("  ✓ \(testCase.name)")
            } else {
                failed += 1
                print("  ✗ \(testCase.name)")
                for failure in t.failures { print("      \(failure)") }
                if let thrown { print("      threw: \(thrown)") }
            }
        }
    }

    let elapsed = String(format: "%.2f", Date().timeIntervalSince(started))
    print("\n\(passed + failed) tests: \(passed) passed, \(failed) failed (\(elapsed)s)")
    return failed == 0 ? 0 : 1
}

/// Fresh temp directory per test for filesystem-backed suites.
func withTempDirectory<R>(_ body: (URL) throws -> R) throws -> R {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("thoughtmeter-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: url) }
    return try body(url)
}
