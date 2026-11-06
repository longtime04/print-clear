import SwiftUI
import UIKit

/// 印得清的共享状态：原图 → 抠图/裁剪后的工作图 → A4 排版 → 导出。
/// 全程只在内存里处理原图数据，不上传、不联网。
@MainActor
@Observable
final class PrintJob {
    /// 导入的原图（已摆正方向，原始像素）。
    var originalImage: UIImage?
    /// 原图的原始文件数据（用于“保存原图”）。
    var originalData: Data?
    /// 原图文件名（相册里一般拿不到，显示占位）。
    var originalFileName: String = "原图"
    /// 抠图/裁剪后的工作图，用于排版。
    var workingImage: UIImage?
    /// 当前选中的打印尺寸预设。
    var preset: PrintSizePreset = .idCard
    /// 自定义尺寸（毫米），preset 为 .custom 时用。
    var customWidthMM: Double = 85.6
    var customHeightMM: Double = 54.0
    /// 每页放几张。
    var copiesPerPage: Int = 8
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

    /// 这张纸每页最多能放几张。
    var maxCopies: Int {
        ImageProcessing.maxCopies(
            cardWidthMM: targetWidthMM, cardHeightMM: targetHeightMM)
    }

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
