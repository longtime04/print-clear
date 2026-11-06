import SwiftUI
import UIKit

/// 第三步：排版。选打印尺寸，排到一张 A4 上（300 DPI，2480×3508 像素）。
struct LayoutView: View {
    @Environment(PrintJob.self) private var job
    @State private var rendering = false
    @State private var note = ""

    var body: some View {
        ZStack {
            GlassBackground()
            ScrollView {
                VStack(spacing: 18) {
                    Text("排版")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)

                    if job.workingImage == nil {
                        GlassCard {
                            Text("请先去“导入”选照片，再去“抠图”处理（也可以跳过抠图直接排版）。")
                                .foregroundStyle(.white)
                        }
                    } else {
                        sizeCard
                        copiesCard
                        if let warning = job.resolutionWarning {
                            GlassCard {
                                Text(warning)
                                    .font(.footnote)
                                    .foregroundStyle(.yellow)
                            }
                        }
                        previewCard
                    }
                }
                .padding()
            }
        }
        .onChange(of: job.preset) { _, _ in renderPage() }
        .onChange(of: job.copiesPerPage) { _, _ in renderPage() }
        .onChange(of: job.customWidthMM) { _, _ in renderPage() }
        .onChange(of: job.customHeightMM) { _, _ in renderPage() }
        .onChange(of: job.workingImage) { _, _ in renderPage() }
    }

    // MARK: - 尺寸

    private var sizeCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("打印尺寸")
                    .font(.headline)
                    .foregroundStyle(.white)
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 10
                ) {
                    ForEach(PrintSizePreset.allCases) { preset in
                        Button {
                            job.preset = preset
                            if preset != .custom {
                                job.copiesPerPage = min(job.copiesPerPage, job.maxCopies)
                            }
                        } label: {
                            VStack(spacing: 2) {
                                Text(preset.name)
                                    .font(.subheadline.bold())
                                Text("\(Int(preset.widthMM))×\(Int(preset.heightMM))mm")
                                    .font(.caption)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                job.preset == preset
                                    ? Color.cyan.opacity(0.35) : Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .foregroundStyle(.white)
                    }
                }
                if job.preset == .custom {
                    HStack(spacing: 12) {
                        HStack {
                            Text("宽")
                                .foregroundStyle(.white)
                            TextField("85.6", value: $job.customWidthMM, format: .number)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                            Text("mm")
                                .foregroundStyle(.white)
                        }
                        HStack {
                            Text("高")
                                .foregroundStyle(.white)
                            TextField("54", value: $job.customHeightMM, format: .number)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                            Text("mm")
                                .foregroundStyle(.white)
                        }
                    }
                }
                Text("打印尺寸 \(String(format: "%.1f", job.targetWidthMM))×\(String(format: "%.1f", job.targetHeightMM)) mm，约 \(Int(job.targetWidthPx))×\(Int(job.targetHeightPx)) 像素 @300 DPI")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
    }

    // MARK: - 每页张数

    private var copiesCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("每页放几张")
                    .font(.headline)
                    .foregroundStyle(.white)
                Stepper(
                    "\(job.copiesPerPage) 张（每页最多 \(job.maxCopies) 张）",
                    value: $job.copiesPerPage, in: 1...max(1, job.maxCopies))
                    .foregroundStyle(.white)
                Text("边距 10mm，间距 5mm，A4 纸 210×297mm。")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
    }

    // MARK: - A4 预览

    private var previewCard: some View {
        GlassCard {
            VStack(spacing: 10) {
                Text("A4 预览")
                    .font(.headline)
                    .foregroundStyle(.white)
                if rendering {
                    ProgressView("排版中…")
                        .foregroundStyle(.white)
                }
                if let page = job.pageImage {
                    Image(uiImage: page)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 420)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Text("A4 · 2480×3508 像素 · 300 DPI · 原图质量")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.75))
                }
                if !note.isEmpty {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.85))
                }
                Button {
                    renderPage()
                } label: {
                    Label("重新排版", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
        }
    }

    // MARK: - 渲染

    private func renderPage() {
        guard let working = job.workingImage,
              let workingData = working.pngData()
        else { return }
        let wMM = job.targetWidthMM
        let hMM = job.targetHeightMM
        let copies = min(job.copiesPerPage, job.maxCopies)
        rendering = true
        Task {
            let outData: (Data, Data)? = await Task.detached {
                guard let image = UIImage(data: workingData)?.normalized() else { return nil }
                let card = ImageProcessing.resizedForPrint(image, widthMM: wMM, heightMM: hMM)
                let page = ImageProcessing.renderA4Page(card: card, copies: copies)
                let pdf = ImageProcessing.renderA4PDF(card: card, copies: copies)
                guard let pageData = page.pngData() else { return nil }
                return (pageData, pdf)
            }.value
            rendering = false
            guard let (pageData, pdf) = outData,
                  let page = UIImage(data: pageData)
            else {
                note = "排版失败，请再试一次。"
                return
            }
            job.pageImage = page
            job.pagePDF = pdf
            note = ""
        }
    }
}
