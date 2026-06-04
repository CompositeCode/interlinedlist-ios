//
//  DataCache.swift
//  InterlinedList
//

import Foundation

final class DataCache {
    static let shared = DataCache()

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let cacheDir: URL

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDir = base.appendingPathComponent("ILDataCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url(for: key), options: .atomic)
    }

    func load<T: Decodable>(key: String) -> T? {
        guard let data = try? Data(contentsOf: url(for: key)) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    func clearAll(prefix: String) {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: cacheDir.path) else { return }
        for file in files where file.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: cacheDir.appendingPathComponent(file))
        }
    }

    private func url(for key: String) -> URL {
        cacheDir.appendingPathComponent("\(key).json")
    }
}
