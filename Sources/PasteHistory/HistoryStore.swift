import AppKit

final class HistoryStore {
    private let fileManager = FileManager.default
    private let appDirectory: URL
    private let imagesDirectory: URL
    private let historyFile: URL

    private(set) var items: [ClipboardHistoryItem] = []

    init() {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        appDirectory = base.appendingPathComponent("Paste History", isDirectory: true)
        imagesDirectory = appDirectory.appendingPathComponent("Images", isDirectory: true)
        historyFile = appDirectory.appendingPathComponent("history.json")
        createDirectories()
        load()
    }

    func add(_ item: ClipboardHistoryItem) {
        let duplicateItems = items.filter { $0.fingerprint == item.fingerprint }
        for duplicate in duplicateItems {
            if let url = imageURL(for: duplicate) {
                try? fileManager.removeItem(at: url)
            }
        }
        items.removeAll { $0.fingerprint == item.fingerprint }
        items.insert(item, at: 0)
        trim()
        save()
    }

    func clear() {
        items.removeAll()
        try? fileManager.removeItem(at: imagesDirectory)
        createDirectories()
        save()
    }

    func remove(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: index)
        if let url = imageURL(for: item) {
            try? fileManager.removeItem(at: url)
        }
        save()
    }

    func imageURL(for item: ClipboardHistoryItem) -> URL? {
        guard let imageFilename = item.imageFilename else { return nil }
        return imagesDirectory.appendingPathComponent(imageFilename)
    }

    func writeImageData(_ data: Data) throws -> String {
        let filename = "\(UUID().uuidString).png"
        try data.write(to: imagesDirectory.appendingPathComponent(filename), options: .atomic)
        return filename
    }

    private func trim() {
        guard items.count > 20 else { return }
        let removed = items.dropFirst(20)
        items = Array(items.prefix(20))
        for item in removed {
            if let url = imageURL(for: item) {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: historyFile) else { return }
        items = (try? JSONDecoder().decode([ClipboardHistoryItem].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: historyFile, options: .atomic)
    }

    private func createDirectories() {
        try? fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
    }
}
