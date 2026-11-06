import SwiftUI
import UIKit

/// 印得清的共享状态：原图 → 抠图/裁剪后的工作图 → 素材库 → A4 排版 → 导出。
/// 全程只在内存里处理原图数据，不上传、不联网。
@MainActor
@Observable
final class PrintJob {
    /// 导入的原图（已摆正方向，原始像素）。
    var originalImage: UIImage?
    /// 原图的原始文件数据（用于“保存原图”）。
    var originalData: Data?
    /// 抠图/裁剪后的工作图，用于存入素材库。
    var workingImage: UIImage?
    /// 当前选中的打印尺寸预设（裁剪/存入素材库时用）。
    var preset: PrintSizePreset = .idCard
    /// 自定义尺寸（毫米），preset 为 .custom 时用。
    var customWidthMM: Double = 85.6
    var customHeightMM: Double = 54.0
    /// 当前 A4 页上的所有图文（不同内容可以混排）。
    var pageItems: [PageItem] = []
    /// 当前选中的排版项。
    var selectedPageItemId: UUID?
    /// 渲染好的 A4 页面图（300 DPI）。
    var pageImage: UIImage?
    /// 渲染好的 A4 PDF 数据。
    var pagePDF: Data?
    /// 处理中。
    var isBusy: Bool = false
    /// 状态/提示文字。
    var statusMessage: String = ""

    var hasOriginal: Bool { originalImage != nil }
    var hasWorking: Bool { workingImage != nil }

    /// 当前目标打印尺寸（毫米）。
    var targetWidthMM: Double {
        preset == .custom ? customWidthMM : preset.widthMM
    }
    var targetHeightMM: Double {
        preset == .custom ? customHeightMM : preset.heightMM
    }

    /// 目标尺寸换算成像素（300 DPI）。
    var targetWidthPx: CGFloat { ImageProcessing.px(forMM: targetWidthMM) }
    var targetHeightPx: CGFloat { ImageProcessing.px(forMM: targetHeightMM) }

    /// 原图裁剪后像素够不够印到目标尺寸（低于 300 DPI 会发虚）。
    var resolutionWarning: String? {
        guard let img = workingImage else { return nil }
        let w = img.size.width * img.scale
        let h = img.size.height * img.scale
        if w < targetWidthPx || h < targetHeightPx {
            return "原图裁剪后只有 \(Int(w))×\(Int(h)) 像素，印到 \(preset.name) 需要 \(Int(targetWidthPx))×\(Int(targetHeightPx)) 像素，印出来会发虚。建议用像素更大的原图，或选更小的打印尺寸。"
        }
        return nil
    }

    /// 有没有超出 A4 纸的项（会被裁掉）。
    var layoutOverflow: Bool {
        pageItems.contains {
            $0.xMM + $0.widthMM > 210 + 0.01 || $0.yMM + $0.heightMM > 297 + 0.01
        }
    }

    func setOriginal(image: UIImage, data: Data?) {
        originalImage = image
        originalData = data
        workingImage = image
        pageImage = nil
        pagePDF = nil
        statusMessage = "已导入原图 \(Int(image.size.width * image.scale))×\(Int(image.size.height * image.scale)) 像素，未压缩。"
    }

    func clearAll() {
        originalImage = nil
        originalData = nil
        workingImage = nil
        pageImage = nil
        pagePDF = nil
        statusMessage = ""
    }

    // MARK: - 排版页操作

    /// 把素材库里的一项加到排版页（放在当前内容下方，超了就放左上角再拖）。
    func addLibraryItem(_ lib: LibraryItem, image: UIImage) {
        let maxBottom = pageItems.map { $0.yMM + $0.heightMM }.max() ?? 0
        var y = maxBottom > 0 ? maxBottom + 5 : 10
        if y + lib.heightMM > 297 - 10 {
            y = 10
        }
        let item = PageItem(
            name: lib.name, kind: .image(image),
            xMM: 10, yMM: y, widthMM: lib.widthMM, heightMM: lib.heightMM)
        pageItems.append(item)
        selectedPageItemId = item.id
        pageImage = nil
        pagePDF = nil
    }

    /// 加一段文字到排版页。
    func addTextItem(content: String, fontSizePt: Double) {
        let size = ImageProcessing.textSizeMM(content: content, fontSizePt: fontSizePt)
        let item = PageItem(
            name: String(content.prefix(8)), kind: .text(content, fontSizePt),
            xMM: 10, yMM: 10,
            widthMM: max(size.width, 10), heightMM: max(size.height, 5))
        pageItems.append(item)
        selectedPageItemId = item.id
        pageImage = nil
        pagePDF = nil
    }

    /// 移动一项（毫米），不超出纸面。
    func moveItem(id: UUID, dxMM: Double, dyMM: Double) {
        guard let i = pageItems.firstIndex(where: { $0.id == id }) else { return }
        let w = pageItems[i].widthMM
        let h = pageItems[i].heightMM
        pageItems[i].xMM = min(max(pageItems[i].xMM + dxMM, 0), 210 - w)
        pageItems[i].yMM = min(max(pageItems[i].yMM + dyMM, 0), 297 - h)
    }

    /// 改一项的大小（毫米）；文字项按比例缩放字号。
    func setItemSize(id: UUID, widthMM: Double, heightMM: Double) {
        guard let i = pageItems.firstIndex(where: { $0.id == id }) else { return }
        let oldW = pageItems[i].widthMM
        let oldH = pageItems[i].heightMM
        let w = min(max(widthMM, 10), 210 - pageItems[i].xMM)
        let h = min(max(heightMM, 5), 297 - pageItems[i].yMM)
        pageItems[i].widthMM = w
        pageItems[i].heightMM = h
        if case .text(let content, let fontSize) = pageItems[i].kind, oldW > 0, oldH > 0 {
            let s = min(w / oldW, h / oldH)
            pageItems[i].kind = .text(content, max(fontSize * s, 6))
        }
        pageImage = nil
        pagePDF = nil
    }

    func removePageItem(id: UUID) {
        pageItems.removeAll { $0.id == id }
        if selectedPageItemId == id { selectedPageItemId = nil }
        pageImage = nil
        pagePDF = nil
    }

    func clearPage() {
        pageItems.removeAll()
        selectedPageItemId = nil
        pageImage = nil
        pagePDF = nil
    }

    /// 自动排版：按面积从大到小，一行一行摆满，留 10mm 边距、5mm 间距。
    /// 单张比一页还大的，等比缩小到能放下。排完还能手动改。
    func autoLayout() {
        let margin = 10.0
        let spacing = 5.0
        let maxW = 210 - 2 * margin
        let maxH = 297 - 2 * margin
        let sorted = pageItems.sorted { $0.widthMM * $0.heightMM > $1.widthMM * $1.heightMM }
        var x = margin
        var y = margin
        var rowH = 0.0
        var placed: [UUID: PageItem] = [:]
        for var item in sorted {
            if item.widthMM > maxW || item.heightMM > maxH {
                let s = min(maxW / item.widthMM, maxH / item.heightMM)
                item.widthMM *= s
                item.heightMM *= s
                if case .text(let content, let fontSize) = item.kind {
                    item.kind = .text(content, max(fontSize * s, 6))
                }
            }
            if x + item.widthMM > 210 - margin + 0.01, x > margin {
                x = margin
                y += rowH + spacing
                rowH = 0
            }
            item.xMM = x
            item.yMM = y
            placed[item.id] = item
            x += item.widthMM + spacing
            rowH = max(rowH, item.heightMM)
        }
        pageItems = pageItems.map { placed[$0.id] ?? $0 }
        pageImage = nil
        pagePDF = nil
    }
}

/// 排版页上的一项：图片或文字。
struct PageItem: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var kind: Kind
    /// 在 A4 上的位置和大小（毫米，左上角原点）。
    var xMM: Double
    var yMM: Double
    var widthMM: Double
    var heightMM: Double

    enum Kind: Equatable {
        case image(UIImage)
        case text(String, Double) // 内容，字号 pt

        static func == (a: Kind, b: Kind) -> Bool {
            switch (a, b) {
            case (.image(let i1), .image(let i2)):
                return i1 === i2
            case (.text(let t1, let f1), .text(let t2, let f2)):
                return t1 == t2 && f1 == f2
            default:
                return false
            }
        }
    }

    static func == (a: PageItem, b: PageItem) -> Bool {
        a.id == b.id && a.name == b.name && a.kind == b.kind
            && a.xMM == b.xMM && a.yMM == b.yMM
            && a.widthMM == b.widthMM && a.heightMM == b.heightMM
    }
}

/// 常用打印尺寸预设（毫米）。
enum PrintSizePreset: String, CaseIterable, Identifiable {
    case idCard = "身份证"
    case hukou = "户口本整页"
    case oneInch = "一寸"
    case twoInch = "二寸"
    case a5 = "A5"
    case custom = "自定义"

    var id: String { rawValue }
    var name: String { rawValue }

    var widthMM: Double {
        switch self {
        case .idCard: return 85.6
        case .hukou: return 148
        case .oneInch: return 25
        case .twoInch: return 35
        case .a5: return 148
        case .custom: return 85.6
        }
    }
    var heightMM: Double {
        switch self {
        case .idCard: return 54
        case .hukou: return 210
        case .oneInch: return 35
        case .twoInch: return 49
        case .a5: return 210
        case .custom: return 54
        }
    }
}
