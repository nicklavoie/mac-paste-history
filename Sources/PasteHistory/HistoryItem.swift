import AppKit
import UniformTypeIdentifiers

enum ClipboardItemKind: String, Codable {
    case text
    case image
    case files
}

struct ClipboardHistoryItem: Codable, Identifiable, Equatable {
    let id: UUID
    var kind: ClipboardItemKind
    var title: String
    var subtitle: String
    var createdAt: Date
    var text: String?
    var imageFilename: String?
    var filePaths: [String]?
    var fingerprint: String

    var displayTitle: String {
        title.isEmpty ? "Untitled" : title
    }
}

extension ClipboardHistoryItem {
    static func text(_ value: String) -> ClipboardHistoryItem {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = normalized.isEmpty ? value : normalized
        let firstLine = preview.components(separatedBy: .newlines).first ?? "Text"
        let title = firstLine.isEmpty ? "Text" : String(firstLine.prefix(80))
        let lineCount = value.components(separatedBy: .newlines).count
        let subtitle = lineCount > 1 ? "\(lineCount) lines" : "\(value.count) characters"

        return ClipboardHistoryItem(
            id: UUID(),
            kind: .text,
            title: title,
            subtitle: subtitle,
            createdAt: Date(),
            text: value,
            imageFilename: nil,
            filePaths: nil,
            fingerprint: "text:\(value.stableHash)"
        )
    }

    static func image(filename: String, size: NSSize, data: Data) -> ClipboardHistoryItem {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())

        return ClipboardHistoryItem(
            id: UUID(),
            kind: .image,
            title: "Image \(width)x\(height)",
            subtitle: ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file),
            createdAt: Date(),
            text: nil,
            imageFilename: filename,
            filePaths: nil,
            fingerprint: "image:\(data.stableHash)"
        )
    }

    static func files(_ urls: [URL]) -> ClipboardHistoryItem {
        let paths = urls.map(\.path)
        let title: String
        if urls.count == 1 {
            title = urls[0].lastPathComponent
        } else {
            title = "\(urls.count) files"
        }

        let folderCount = urls.filter { url in
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            return isDirectory.boolValue
        }.count

        let subtitle: String
        if folderCount == urls.count {
            subtitle = urls.count == 1 ? "Folder" : "\(urls.count) folders"
        } else if folderCount > 0 {
            subtitle = "\(urls.count) items, \(folderCount) folders"
        } else {
            subtitle = urls.count == 1 ? (urls[0].pathExtension.uppercased().isEmpty ? "File" : urls[0].pathExtension.uppercased()) : "\(urls.count) files"
        }

        return ClipboardHistoryItem(
            id: UUID(),
            kind: .files,
            title: title,
            subtitle: subtitle,
            createdAt: Date(),
            text: nil,
            imageFilename: nil,
            filePaths: paths,
            fingerprint: "files:\(paths.joined(separator: "\u{1F}").stableHash)"
        )
    }
}

extension String {
    var stableHash: String {
        data(using: .utf8)?.stableHash ?? String(hashValue)
    }
}

extension Data {
    var stableHash: String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in self {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
