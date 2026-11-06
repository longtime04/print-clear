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
        return [
            CGPoint(x: rect.topLeft.x, y: 1 - rect.topLeft.y),
            CGPoint(x: rect.topRight.x, y: 1 - rect.topRight.y),
            CGPoint(x: rect.bottomRight.x, y: 1 - rect.bottomRight.y),
            CGPoint(x: rect.bottomLeft.x, y: 1 - rect.bottomLeft.y),
        ]
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
            // 等比填满：按比例放大到盖住目标框，居中裁。
            let scale = max(targetW / image.size.width, targetH / image.size.height)
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

    // MARK: - A4 排版

    /// 这张卡片在 A4 上每页最多放几张（边距 10mm、间距 5mm）。
    static func maxCopies(
        cardWidthMM: Double, cardHeightMM: Double,
        marginMM: Double = 10, spacingMM: Double = 5
    ) -> Int {
        let cardW = px(forMM: cardWidthMM)
        let cardH = px(forMM: cardHeightMM)
        let margin = px(forMM: marginMM)
        let spacing = px(forMM: spacingMM)
        let cols = max(1, Int((a4WidthPx - 2 * margin + spacing) / (cardW + spacing)))
        let rows = max(1, Int((a4HeightPx - 2 * margin + spacing) / (cardH + spacing)))
        return cols * rows
    }

    /// 渲染 A4 页面图（300 DPI，2480×3508 像素，无损 PNG 级别）。
    /// card 必须是已经改到目标打印尺寸的图。
    static func renderA4Page(
        card: UIImage, copies: Int,
        marginMM: Double = 10, spacingMM: Double = 5
    ) -> UIImage {
        let cardW = card.size.width
        let cardH = card.size.height
        let margin = px(forMM: marginMM)
        let spacing = px(forMM: spacingMM)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: a4WidthPx, height: a4HeightPx), format: format)
        return renderer.image { context in
            context.cgContext.interpolationQuality = .high
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: a4WidthPx, height: a4HeightPx))
            let cols = max(1, Int((a4WidthPx - 2 * margin + spacing) / (cardW + spacing)))
            var placed = 0
            var y = margin
            while placed < copies && y + cardH <= a4HeightPx - margin + 1 {
                var x = margin
                for _ in 0..<cols {
                    guard placed < copies else { break }
                    card.draw(in: CGRect(x: x, y: y, width: cardW, height: cardH))
                    placed += 1
                    x += cardW + spacing
                }
                y += cardH + spacing
            }
        }
    }

    /// 渲染 A4 PDF（A4 页面，图片按原分辨率嵌入）。
    static func renderA4PDF(card: UIImage, copies: Int) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: a4WidthPt, height: a4HeightPt)
        let format = UIGraphicsPDFRendererFormat()
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        // 像素 → 点数：300 DPI 的像素除以 300 再乘 72。
        let scale = 72.0 / dpi
        let cardW = card.size.width * scale
        let cardH = card.size.height * scale
        let margin = px(forMM: 10) * scale
        let spacing = px(forMM: 5) * scale
        return renderer.pdfData { context in
            context.beginPage()
            let cg = context.cgContext
            cg.interpolationQuality = .high
            UIColor.white.setFill()
            cg.fill(pageRect)
            let cols = max(1, Int((a4WidthPt - 2 * margin + spacing) / (cardW + spacing)))
            var placed = 0
            var y = margin
            while placed < copies && y + cardH <= a4HeightPt - margin + 1 {
                var x = margin
                for _ in 0..<cols {
                    guard placed < copies else { break }
                    card.draw(in: CGRect(x: x, y: y, width: cardW, height: cardH))
                    placed += 1
                    x += cardW + spacing
                }
                y += cardH + spacing
            }
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
