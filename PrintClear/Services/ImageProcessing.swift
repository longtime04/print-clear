import CoreImage
import UIKit
import Vision

/// 图像处理：全部本地离线。
/// 300 DPI 是打印的基准；A4 纸 210×297mm 对应 2480×3508 像素。
enum ImageProcessing {
    static let dpi: CGFloat = 300
    static let mmPerInch: CGFloat = 25.4
    static let a4WidthPx: CGFloat = 2480 // 210mm
    static let a4HeightPx: CGFloat = 3508 // 297mm
    static let a4WidthPt: CGFloat = 595.28 // A4 点数
    static let a4HeightPt: CGFloat = 841.89

    static func px(forMM mm: Double) -> CGFloat {
        CGFloat(mm) / mmPerInch * dpi
    }

    // MARK: - 证件抠边（自动认边 + 透视拉正）

    /// 用 Vision 找图里最大的矩形（证件边缘），返回归一化四角点
    /// （UIKit 坐标：左上、右上、右下、左下，x/y 均为 0...1）。找不到返回 nil。
    static func detectDocumentCorners(in image: UIImage) -> [CGPoint]? {
        guard let small = image.downscaled(toMax: 1024),
              let cg = small.cgImage
        else { return nil }
        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = 0.3
        request.maximumAspectRatio = 3.0
        request.minimumSize = 0.15
        request.maximumObservations = 3
        request.minimumConfidence = 0.5
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let rect = request.results?.first else { return nil }
        // Vision 归一化坐标原点在左下角，转成 UIKit 左上角。
        let corners = [
            CGPoint(x: rect.topLeft.x, y: 1 - rect.topLeft.y),
            CGPoint(x: rect.topRight.x, y: 1 - rect.topRight.y),
            CGPoint(x: rect.bottomRight.x, y: 1 - rect.bottomRight.y),
            CGPoint(x: rect.bottomLeft.x, y: 1 - rect.bottomLeft.y),
        ]
        // 认出的框往往比证件实际边缘小一圈（贴着里面的印线）：
        // 从中心往外放 3%，把证件的边沿完整含进来，再拖四角微调。
        let cx = corners.map { $0.x }.reduce(0, +) / 4
        let cy = corners.map { $0.y }.reduce(0, +) / 4
        return corners.map { p in
            CGPoint(
                x: min(max(cx + (p.x - cx) * 1.03, 0), 1),
                y: min(max(cy + (p.y - cy) * 1.03, 0), 1))
        }
    }

    /// 按四角点做透视拉正，输出一张长方形的图。
    /// corners 为归一化点（UIKit 左上角原点），顺序：左上、右上、右下、左下。
    static func perspectiveCorrect(_ image: UIImage, corners: [CGPoint]) -> UIImage? {
        guard corners.count == 4, let cgImage = image.cgImage else { return nil }
        let ci = CIImage(cgImage: cgImage)
        let w = ci.extent.width
        let h = ci.extent.height
        func ciPoint(_ p: CGPoint) -> CIVector {
            CIVector(x: p.x * w, y: h - p.y * h)
        }
        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filter.setValue(ci, forKey: kCIInputImageKey)
        filter.setValue(ciPoint(corners[0]), forKey: "inputTopLeft")
        filter.setValue(ciPoint(corners[1]), forKey: "inputTopRight")
        filter.setValue(ciPoint(corners[2]), forKey: "inputBottomRight")
        filter.setValue(ciPoint(corners[3]), forKey: "inputBottomLeft")
        guard let out = filter.outputImage else { return nil }
        let context = CIContext(options: nil)
        guard let outCG = context.createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: outCG, scale: 1.0, orientation: .up)
    }

    // MARK: - 人像去背景

    /// 只认得出人像：把人抠出来，背景变透明。
    /// 拍证件照里的人像才有效；拍整张身份证请用“证件抠边”。
    /// 找不到人返回 nil。
    static func removePersonBackground(from image: UIImage) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let observation = request.results?.first else { return nil }
        let instances = observation.allInstances
        guard !instances.isEmpty else { return nil }
        do {
            let buffer = try observation.generateMaskedImage(
                ofInstances: instances, from: handler, croppedToInstancesExtent: false)
            let ci = CIImage(cvPixelBuffer: buffer)
            let context = CIContext(options: nil)
            guard let outCG = context.createCGImage(ci, from: ci.extent) else { return nil }
            return UIImage(cgImage: outCG, scale: 1.0, orientation: .up)
        } catch {
            return nil
        }
    }

    /// 把带透明通道的图合成到白底上（打印证件照常用白底）。
    static func compositeOnWhite(_ image: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: image.size))
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    // MARK: - 改尺寸（不变形，等比裁切填满目标框）

    /// 把图改到目标打印尺寸（毫米，300 DPI），等比填满、不拉伸。
    static func resizedForPrint(
        _ image: UIImage, widthMM: Double, heightMM: Double
    ) -> UIImage {
        let targetW = px(forMM: widthMM)
        let targetH = px(forMM: heightMM)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: targetW, height: targetH), format: format)
        return renderer.image { context in
            context.cgContext.interpolationQuality = .high
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: targetW, height: targetH))
            // 等比完整放下：整张图都保留，不够的地方补白边，绝不裁内容。
            let scale = min(targetW / image.size.width, targetH / image.size.height)
            let drawW = image.size.width * scale
            let drawH = image.size.height * scale
            let drawX = (targetW - drawW) / 2
            let drawY = (targetH - drawH) / 2
            image.draw(in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH))
        }
    }

    /// 顺时针转 90 度。
    static func rotated90(_ image: UIImage) -> UIImage {
        let newSize = CGSize(width: image.size.height, height: image.size.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { context in
            context.cgContext.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            context.cgContext.rotate(by: .pi / 2)
            image.draw(in: CGRect(
                x: -image.size.width / 2, y: -image.size.height / 2,
                width: image.size.width, height: image.size.height))
        }
    }

    // MARK: - 文字

    /// 一段文字在某个字号下的占地（毫米）。支持换行，每行单独算。
    static func textSizeMM(content: String, fontSizePt: Double) -> (width: Double, height: Double) {
        let font = UIFont.systemFont(ofSize: fontSizePt)
        let lines = content.components(separatedBy: "\n")
        var maxW: CGFloat = 0
        for line in lines {
            let w = (line as NSString).size(withAttributes: [.font: font]).width
            maxW = max(maxW, w)
        }
        let lineH = font.lineHeight
        let widthMM = Double(maxW) * 25.4 / 72
        let heightMM = Double(lineH) * Double(lines.count) * 25.4 / 72
        return (widthMM, heightMM)
    }

    // MARK: - A4 排版（多图文混排）

    /// 渲染用的项：图片或文字，位置和大小都是毫米。
    struct RenderItem: Sendable {
        var imageData: Data?
        var text: String?
        var fontSizePt: Double
        var xMM: Double
        var yMM: Double
        var widthMM: Double
        var heightMM: Double
        /// 旋转角度（0 / 90 / 180 / 270，顺时针）。
        var rotation: Int = 0
    }

    /// 渲染 A4 页面图（300 DPI，2480×3508 像素，无损 PNG 级别）。
    static func renderA4Page(items: [RenderItem]) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: a4WidthPx, height: a4HeightPx), format: format)
        return renderer.image { context in
            context.cgContext.interpolationQuality = .high
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: a4WidthPx, height: a4HeightPx))
            for item in items {
                let rect = CGRect(
                    x: px(forMM: item.xMM), y: px(forMM: item.yMM),
                    width: px(forMM: item.widthMM), height: px(forMM: item.heightMM))
                drawRenderItem(item, in: rect, context: context.cgContext, scale: dpi / 72)
            }
        }
    }

    /// 渲染 A4 PDF（A4 页面，图片按原分辨率嵌入）。
    static func renderA4PDF(items: [RenderItem]) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: a4WidthPt, height: a4HeightPt)
        let format = UIGraphicsPDFRendererFormat()
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        // 像素 → 点数：300 DPI 的像素除以 300 再乘 72。
        let scale = 72.0 / dpi
        return renderer.pdfData { context in
            context.beginPage()
            let cg = context.cgContext
            cg.interpolationQuality = .high
            UIColor.white.setFill()
            cg.fill(pageRect)
            for item in items {
                let rect = CGRect(
                    x: px(forMM: item.xMM) * scale, y: px(forMM: item.yMM) * scale,
                    width: px(forMM: item.widthMM) * scale,
                    height: px(forMM: item.heightMM) * scale)
                drawRenderItem(item, in: rect, context: cg, scale: 1.0)
            }
        }
    }

    /// 画一项（图片或文字），带旋转。旋转绕着格子中心转。
    private static func drawRenderItem(
        _ item: RenderItem, in rect: CGRect, context: CGContext, scale: CGFloat
    ) {
        let rot = item.rotation % 360
        if rot == 0 {
            drawItemContent(item, in: rect, scale: scale)
            return
        }
        // 转之前的格子（中心和格子重合，长宽互换）。
        let preW = (rot == 90 || rot == 270) ? rect.height : rect.width
        let preH = (rot == 90 || rot == 270) ? rect.width : rect.height
        let preRect = CGRect(
            x: rect.midX - preW / 2, y: rect.midY - preH / 2,
            width: preW, height: preH)
        context.saveGState()
        context.translateBy(x: rect.midX, y: rect.midY)
        context.rotate(by: CGFloat(rot) * .pi / 180)
        context.translateBy(x: -rect.midX, y: -rect.midY)
        drawItemContent(item, in: preRect, scale: scale)
        context.restoreGState()
    }

    /// 在指定框里画一项的内容（不处理旋转）。
    private static func drawItemContent(_ item: RenderItem, in rect: CGRect, scale: CGFloat) {
        if let data = item.imageData, let image = UIImage(data: data) {
            image.draw(in: aspectFillRect(imageSize: image.size, into: rect))
        } else if let text = item.text {
            drawText(text, fontSizePt: item.fontSizePt, in: rect, scale: scale)
        }
    }

    /// 等比填满：按比例放大到盖住目标框，居中裁（不拉伸）。
    private static func aspectFillRect(imageSize: CGSize, into rect: CGRect) -> CGRect {
        let scale = max(rect.width / imageSize.width, rect.height / imageSize.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        return CGRect(x: rect.minX + (rect.width - w) / 2, y: rect.minY + (rect.height - h) / 2, width: w, height: h)
    }

    /// 在指定框里画多行文字。scale 是“点数→当前坐标单位”的倍数
    /// （PNG 渲染用 300/72，PDF 渲染用 1.0）。
    private static func drawText(_ text: String, fontSizePt: Double, in rect: CGRect, scale: CGFloat) {
        let font = UIFont.systemFont(ofSize: fontSizePt * scale)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: UIColor.black,
        ]
        let lines = text.components(separatedBy: "\n")
        let lineH = font.lineHeight
        for (i, line) in lines.enumerated() {
            let attributed = NSAttributedString(string: line, attributes: attributes)
            attributed.draw(at: CGPoint(x: rect.minX, y: rect.minY + CGFloat(i) * lineH))
        }
    }
}

// MARK: - UIImage 小工具

extension UIImage {
    /// 把方向摆正（照片的方向信息在 EXIF 里，直接拿 cgImage 会歪）。
    func normalized() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// 等比缩小到最长边不超过 maxDim（像素），只做缩小不放大。
    func downscaled(toMax maxDim: CGFloat) -> UIImage? {
        let m = max(size.width, size.height)
        guard m > maxDim else { return self }
        let scale = maxDim / m
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
