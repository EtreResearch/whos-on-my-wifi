import Foundation

struct CountSample: Codable, Identifiable {
    let date: Date
    let network: String
    let count: Int
    var id: Date { date }
}

func recentSamples(_ samples: [CountSample], now: Date) -> [CountSample] {
    samples.filter { $0.date >= now.addingTimeInterval(-86400) && $0.date <= now && $0.count >= 1 }
        .sorted { $0.date < $1.date }.suffix(1440).map { $0 }
}

func loadHistory(from file: URL, now: Date = Date()) throws -> [CountSample] {
    guard FileManager.default.fileExists(atPath: file.path) else { return [] }
    return recentSamples(try JSONDecoder().decode([CountSample].self, from: Data(contentsOf: file)), now: now)
}

func saveHistory(_ samples: [CountSample], to file: URL) throws {
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(samples).write(to: file, options: .atomic)
}
