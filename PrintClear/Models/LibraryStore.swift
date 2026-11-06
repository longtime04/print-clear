import SwiftUI
import UIKit

/// 素材库里的一项：裁好的图文，存在本地文件里（PNG + 索引 JSON）。
struct LibraryItem: Identifiable, Codable {
    var id: UUID
    var name: String
    /// 打印尺寸（毫米）。
    var widthMM: Double
    var heightMM: Double
    var fileName: String
    var createdAt: Date
}

/// 素材库（历史库）：先裁好的图文都存在这里，随时加到排版页上。
/// 存在 App 的 Documents/PrintClearLibrary/ 里，不上传、不联网。
@MainActor
@Observable
final class LibraryStore {
    var items: [LibraryItem] = []
    private let folder: URL
    private var indexURL: URL { folder.appendingPathComponent("library.json") }

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        folder = docs.appendingPathComponent("PrintClearLibrary")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([LibraryItem].self, from: data)
        else {
            items = []
            return
        }
        // 只保留图片文件还在的。
        items = decoded.filter {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0.fileName).path)
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: indexURL)
    }

    /// 存入一张裁好的图（已按打印尺寸改好像素的）。返回存好的项。
    @discardableResult
    func save(image: UIImage, name: String, widthMM: Double, heightMM: Double) -> LibraryItem? {
        guard let png = image.pngData() else { return nil }
        let id = UUID()
        let item = LibraryItem(
            id: id, name: name, widthMM: widthMM, heightMM: heightMM,
            fileName: "\(id.uuidString).png", createdAt: Date())
        let url = folder.appendingPathComponent(item.fileName)
        do {
            try png.write(to: url)
        } catch {
            return nil
        }
        items.append(item)
        persist()
        return item
    }

    func image(for item: LibraryItem) -> UIImage? {
        let url = folder.appendingPathComponent(item.fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    func delete(_ item: LibraryItem) {
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(item.fileName))
        items.removeAll { $0.id == item.id }
        persist()
    }

    func rename(_ item: LibraryItem, to name: String) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].name = name
        persist()
    }
}
