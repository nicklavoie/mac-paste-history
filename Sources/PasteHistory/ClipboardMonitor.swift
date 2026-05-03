import AppKit

protocol ClipboardMonitorDelegate: AnyObject {
    func clipboardMonitorDidCaptureItem(_ item: ClipboardHistoryItem)
}

final class ClipboardMonitor {
    weak var delegate: ClipboardMonitorDelegate?

    private let pasteboard = NSPasteboard.general
    private let store: HistoryStore
    private var timer: Timer?
    private var lastChangeCount: Int
    private var ignoredFingerprints = Set<String>()

    init(store: HistoryStore) {
        self.store = store
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func restore(_ item: ClipboardHistoryItem) {
        pasteboard.clearContents()

        switch item.kind {
        case .text:
            if let text = item.text {
                pasteboard.setString(text, forType: .string)
            }
        case .image:
            if let url = store.imageURL(for: item), let data = try? Data(contentsOf: url) {
                pasteboard.setData(data, forType: .png)
                if let image = NSImage(data: data) {
                    pasteboard.writeObjects([image])
                }
            }
        case .files:
            let urls = (item.filePaths ?? []).map(URL.init(fileURLWithPath:))
            pasteboard.writeObjects(urls as [NSURL])
        }

        ignoredFingerprints.insert(item.fingerprint)
        lastChangeCount = pasteboard.changeCount
    }

    private func poll() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        guard let item = captureCurrentPasteboardItem() else { return }
        guard ignoredFingerprints.remove(item.fingerprint) == nil else { return }

        store.add(item)
        delegate?.clipboardMonitorDidCaptureItem(item)
    }

    private func captureCurrentPasteboardItem() -> ClipboardHistoryItem? {
        if let fileItem = captureFileURLs() {
            return fileItem
        }

        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            return .text(text)
        }

        if let imageItem = captureImage() {
            return imageItem
        }

        return nil
    }

    private func captureFileURLs() -> ClipboardHistoryItem? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]

        var urls: [URL] = []

        if let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [NSURL] {
            urls.append(contentsOf: objects.map { $0 as URL }.filter(\.isFileURL))
        }

        for item in pasteboard.pasteboardItems ?? [] {
            if let value = item.string(forType: .fileURL),
               let url = URL(string: value),
               url.isFileURL {
                urls.append(url)
            }
        }

        let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        if let paths = pasteboard.propertyList(forType: filenamesType) as? [String] {
            urls.append(contentsOf: paths.map(URL.init(fileURLWithPath:)))
        }

        let uniqueURLs = Array(Dictionary(grouping: urls, by: \.path).compactMap { $0.value.first })
        return uniqueURLs.isEmpty ? nil : .files(uniqueURLs)
    }

    private func captureImage() -> ClipboardHistoryItem? {
        let imageData: Data?
        if let pngData = pasteboard.data(forType: .png) {
            imageData = pngData
        } else if let tiffData = pasteboard.data(forType: .tiff),
                  let bitmap = NSBitmapImageRep(data: tiffData) {
            imageData = bitmap.representation(using: .png, properties: [:])
        } else if let image = NSImage(pasteboard: pasteboard),
                  let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff) {
            imageData = bitmap.representation(using: .png, properties: [:])
        } else {
            imageData = nil
        }

        guard let data = imageData,
              let image = NSImage(data: data),
              let filename = try? store.writeImageData(data) else {
            return nil
        }

        return .image(filename: filename, size: image.size, data: data)
    }
}
