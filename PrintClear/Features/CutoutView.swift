import SwiftUI
import UIKit

/// 第二步：抠图。两种都做：
/// 1. 证件抠边：自动认出证件边缘，拖四角微调，透视拉正。
/// 2. 人像去背景：只认得出人像，背景变透明（打印默认白底）。
struct CutoutView: View {
    @Environment(PrintJob.self) private var job
    @State private var mode: CutoutMode = .document
    @State private var corners: [CGPoint] = [
        CGPoint(x: 0.02, y: 0.02), CGPoint(x: 0.98, y: 0.02),
        CGPoint(x: 0.98, y: 0.98), CGPoint(x: 0.02, y: 0.98),
    ]
    @State private var cutoutImage: UIImage?
    @State private var whiteBackground = true
    @State private var note = ""

    enum CutoutMode: String, CaseIterable, Identifiable {
        case document = "证件抠边"
        case portrait = "人像去背景"
        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            GlassBackground()
            ScrollView {
                VStack(spacing: 18) {
                    Text("抠图")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)

                    Picker("抠图方式", selection: $mode) {
                        ForEach(CutoutMode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)

                    if job.originalImage == nil {
                        GlassCard {
                            Text("请先去“导入”选一张照片。")
                                .foregroundStyle(.white)
                        }
                    } else if mode == .document {
                        documentMode
                    } else {
                        portraitMode
                    }

                    if let working = job.workingImage {
                        GlassCard {
                            HStack(spacing: 12) {
                                Image(uiImage: working)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("当前排版图")
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                    Text("\(Int(working.size.width * working.scale))×\(Int(working.size.height * working.scale)) 像素")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.75))
                                    Text("下一步去“排版”选尺寸、排到 A4 上。")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.75))
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
    }

    // MARK: - 证件抠边

    private var documentMode: some View {
        VStack(spacing: 14) {
            GlassCard {
                VStack(spacing: 10) {
                    if let image = job.originalImage {
                        CornerEditor(image: image, corners: $corners)
                            .frame(height: 340)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    Text("拖动四个角对准证件边缘，黄线就是抠出来的范围。")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                }
            }

            GlassCard {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Button {
                            autoDetect()
                        } label: {
                            Label("自动认边", systemImage: "viewfinder")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.cyan)
                        .disabled(job.isBusy)
                        Button {
                            resetCorners()
                        } label: {
                            Label("重置四角", systemImage: "arrow.counterclockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    }
                    Button {
                        warpAndCrop()
                    } label: {
                        Label("拉正并裁剪", systemImage: "crop")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(job.isBusy)
                    Button {
                        rotateWorking()
                    } label: {
                        Label("旋转 90°", systemImage: "rotate.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .disabled(job.workingImage == nil)
                    if job.isBusy {
                        ProgressView("处理中…")
                            .foregroundStyle(.white)
                    }
                    if !note.isEmpty {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
    }

    // MARK: - 人像去背景

    private var portraitMode: some View {
        VStack(spacing: 14) {
            GlassCard {
                VStack(spacing: 10) {
                    if let cutout = cutoutImage {
                        ZStack {
                            if whiteBackground {
                                Color.white
                            } else {
                                Color.gray.opacity(0.4)
                            }
                            Image(uiImage: cutout)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 320)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        Toggle("白底（打印默认）", isOn: $whiteBackground)
                            .foregroundStyle(.white)
                            .tint(.cyan)
                    } else if let image = job.originalImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 320)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    Text("只认得出人像：拍证件照里的人才有效。拍整张身份证、户口本请用“证件抠边”。")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                }
            }

            GlassCard {
                VStack(spacing: 10) {
                    Button {
                        removeBackground()
                    } label: {
                        Label("去背景", systemImage: "person.crop.circle")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    .disabled(job.isBusy)
                    Button {
                        setCutoutAsWorking()
                    } label: {
                        Label("设为排版图", systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(cutoutImage == nil)
                    if job.isBusy {
                        ProgressView("处理中…")
                            .foregroundStyle(.white)
                    }
                    if !note.isEmpty {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
    }

    // MARK: - 动作

    private func autoDetect() {
        guard let data = job.originalData else { return }
        job.isBusy = true
        note = ""
        Task {
            let found: [CGPoint]? = await Task.detached {
                guard let image = UIImage(data: data)?.normalized() else { return nil }
                return ImageProcessing.detectDocumentCorners(in: image)
            }.value
            job.isBusy = false
            if let found {
                corners = found
                note = "已认出证件边缘，拖四角可以微调，再点“拉正并裁剪”。"
            } else {
                note = "没认出证件边缘，请手动拖四个角对准证件。"
            }
        }
    }

    private func resetCorners() {
        corners = [
            CGPoint(x: 0.02, y: 0.02), CGPoint(x: 0.98, y: 0.02),
            CGPoint(x: 0.98, y: 0.98), CGPoint(x: 0.02, y: 0.98),
        ]
        note = ""
    }

    private func warpAndCrop() {
        guard let data = job.originalData else { return }
        let pts = corners
        job.isBusy = true
        note = ""
        Task {
            let outData = await Task.detached {
                guard let image = UIImage(data: data)?.normalized(),
                      let warped = ImageProcessing.perspectiveCorrect(image, corners: pts)
                else { return nil as Data? }
                return warped.pngData()
            }.value
            job.isBusy = false
            guard let outData, let image = UIImage(data: outData) else {
                note = "拉正失败，请检查四角是不是都在证件上。"
                return
            }
            job.workingImage = image
            job.pageImage = nil
            job.pagePDF = nil
            note = "已拉正裁剪：\(Int(image.size.width))×\(Int(image.size.height)) 像素。去“排版”选尺寸。"
        }
    }

    private func rotateWorking() {
        guard let working = job.workingImage else { return }
        job.workingImage = ImageProcessing.rotated90(working)
        job.pageImage = nil
        job.pagePDF = nil
        note = "已旋转 90°。"
    }

    private func removeBackground() {
        guard let data = job.originalData else { return }
        job.isBusy = true
        note = ""
        Task {
            let outData = await Task.detached {
                guard let image = UIImage(data: data)?.normalized(),
                      let cut = ImageProcessing.removePersonBackground(from: image)
                else { return nil as Data? }
                return cut.pngData()
            }.value
            job.isBusy = false
            guard let outData, let image = UIImage(data: outData) else {
                note = "没认出人像。请确认照片里有人，并且人占画面比较大。"
                return
            }
            cutoutImage = image
            note = "已去掉背景，点“设为排版图”就能去排版。"
        }
    }

    private func setCutoutAsWorking() {
        guard let cutout = cutoutImage else { return }
        job.workingImage = whiteBackground
            ? ImageProcessing.compositeOnWhite(cutout) : cutout
        job.pageImage = nil
        job.pagePDF = nil
        note = "已设为排版图，去“排版”选尺寸。"
    }
}

// MARK: - 四角拖动编辑器

private struct CornerEditor: View {
    let image: UIImage
    @Binding var corners: [CGPoint]

    var body: some View {
        GeometryReader { geo in
            let frame = aspectFitRect(imageSize: image.size, in: geo.size)
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                Path { path in
                    path.move(to: displayPoint(corners[0], in: frame))
                    path.addLine(to: displayPoint(corners[1], in: frame))
                    path.addLine(to: displayPoint(corners[2], in: frame))
                    path.addLine(to: displayPoint(corners[3], in: frame))
                    path.closeSubpath()
                }
                .stroke(Color.yellow, lineWidth: 2)
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(Color.white)
                        .frame(width: 30, height: 30)
                        .overlay(Circle().stroke(Color.blue, lineWidth: 2))
                        .position(displayPoint(corners[i], in: frame))
                        .gesture(
                            DragGesture(coordinateSpace: .named("cornerEditor"))
                                .onChanged { value in
                                    let nx = (value.location.x - frame.minX) / frame.width
                                    let ny = (value.location.y - frame.minY) / frame.height
                                    corners[i] = CGPoint(
                                        x: min(max(nx, 0), 1), y: min(max(ny, 0), 1))
                                }
                        )
                }
            }
            .coordinateSpace(name: "cornerEditor")
        }
    }

    private func displayPoint(_ p: CGPoint, in frame: CGRect) -> CGPoint {
        CGPoint(x: frame.minX + p.x * frame.width, y: frame.minY + p.y * frame.height)
    }

    private func aspectFitRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        return CGRect(
            x: (container.width - w) / 2, y: (container.height - h) / 2,
            width: w, height: h)
    }
}

