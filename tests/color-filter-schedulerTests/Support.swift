import Foundation
import CoreLocation
import ColorFilterEngine
@testable import color_filter_scheduler

final class FakeCityLookup: CityLookingUp {
    struct Pending {
        let query: String
        let completion: (Result<(Coordinates, String), Error>) -> Void
    }

    var invokeCanceledOnCancel = true
    private(set) var pending: [Pending] = []
    private(set) var stale: [Pending] = []
    private(set) var cancelCount = 0

    func cancel() {
        cancelCount += 1
        let old = pending
        pending.removeAll()
        if invokeCanceledOnCancel {
            for item in old {
                item.completion(.failure(CLError(.geocodeCanceled)))
            }
        } else {
            stale.append(contentsOf: old)
        }
    }

    func lookup(_ query: String, completion: @escaping (Result<(Coordinates, String), Error>) -> Void) {
        pending.append(Pending(query: query, completion: completion))
    }

    func succeed(lat: Double, lon: Double, name: String, index: Int = 0) {
        let coords = Coordinates(latitude: lat, longitude: lon)!
        let item = pending.remove(at: index)
        item.completion(.success((coords, name)))
    }

    func fail(_ error: Error, index: Int = 0) {
        let item = pending.remove(at: index)
        item.completion(.failure(error))
    }

    func succeedStale(lat: Double, lon: Double, name: String, index: Int = 0) {
        let coords = Coordinates(latitude: lat, longitude: lon)!
        let item = stale.remove(at: index)
        item.completion(.success((coords, name)))
    }
}

struct ProcessResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

enum IsolatedDefaults {
    static func make() -> (name: String, defaults: UserDefaults, settings: ColorFilterEngine.Settings) {
        let name = "cfs-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (name, defaults, ColorFilterEngine.Settings(defaults: defaults))
    }

    static func remove(_ name: String, _ defaults: UserDefaults) {
        defaults.removePersistentDomain(forName: name)
    }
}

enum Tool {
    static func productsDirectory() -> URL {
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            return bundle.bundleURL.deletingLastPathComponent()
        }
        // Swift Testing runner: walk from this source file to .build/.../debug
        let bin = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/debug/color-filter-scheduler")
        if FileManager.default.isExecutableFile(atPath: bin.path) { return bin.deletingLastPathComponent() }
        let arm = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/arm64-apple-macosx/debug/color-filter-scheduler")
        if FileManager.default.isExecutableFile(atPath: arm.path) { return arm.deletingLastPathComponent() }
        fatalError("couldn't find products directory")
    }

    static func binary() -> URL {
        let url = productsDirectory().appendingPathComponent("color-filter-scheduler")
        precondition(FileManager.default.isExecutableFile(atPath: url.path),
                     "missing executable at \(url.path)")
        return url
    }

    @discardableResult
    static func run(_ arguments: [String]) throws -> ProcessResult {
        let proc = Process()
        proc.executableURL = binary()
        proc.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        try proc.run()
        proc.waitUntilExit()
        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return ProcessResult(status: proc.terminationStatus, stdout: stdout, stderr: stderr)
    }
}

func isoDate(_ iso: String) -> Date {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: iso)!
}
