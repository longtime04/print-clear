import Photos
import PhotosUI
import SwiftUI

/// 第一步：导入。只从相册拿原图，不压缩；原图数据留着，可随时另存。
struct ImportView: View {
    @Environment(PrintJob.self) private var job
    @State private var pickerItem: PhotosPickerItem?
    @State private var savingOriginal = false
    @State private var saveResult = ""

    var body: some View {
        ZStack {
            GlassBackground()
            ScrollView {
                VStack(spacing: 18) {
                    Text("印得清")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                    Text("身份证、户口本排版打印 · 原图质量")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))

                    GlassCard {
                        VStack(spacing: 12) {
                            PhotosPicker(
                                selection: $pickerItem, matching: .images,
                                photoLibrary: .shared()
                            ) {
                                Label("从相册导入照片", systemImage: "photo.on.rectangle")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.cyan)
                            .disabled(job.isBusy)

                            if job.isBusy {
                                ProgressView("处理中…")
                                    .foregroundStyle(.white)
                            }
                            if !job.statusMessage.isEmpty {
                                Text(job.statusMessage)
                                    .font(.footnote)
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                        }
                    }

                    if let image = job.originalImage {
                        GlassCard {
                            VStack(spacing: 10) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 320)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                HStack(spacing: 8) {
                                    GlassPill {
                                        Text("原图 \(Int(image.size.width * image.scale))×\(Int(image.size.height * image.scale)) 像素")
                                            .font(.caption)
                                            .foregroundStyle(.white)
                                    }
                                    if let data = job.originalData {
                                        GlassPill {
                                            Text("文件约 \(String(format: "%.1f", Double(data.count) / 1024 / 1024)) MB")
                                                .font(.caption)
                                                .foregroundStyle(.white)
                                        }
                                    }
                                }
                                Text("已按原始像素导入，没有压缩。下一步去“抠图”把证件抠出来，或直接去“排版”。")
                                    .font(.footnote)
                                    .foregroundStyle(.white.opacity(0.75))
                                    .multilineTextAlignment(.center)
                            }
                        }

                        GlassCard {
                            VStack(spacing: 10) {
                                Button {
                                    saveOriginalToPhotos()
                                } label: {
                                    Label("保存原图到相册", systemImage: "square.and.arrow.down")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .tint(.white)
                                .disabled(job.originalData == nil || savingOriginal)
                                if !saveResult.isEmpty {
                                    Text(saveResult)
                                        .font(.footnote)
                                        .foregroundStyle(.white.opacity(0.85))
                                }
                                Button(role: .destructive) {
                                    job.clearAll()
                                } label: {
                                    Label("换一张", systemImage: "arrow.counterclockwise")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .tint(.white)
                            }
                        }
                    } else {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("用法")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                Text("1. 导入拍好的身份证、户口本照片\n2. 抠图：证件自动认边拉正，或人像去背景\n3. 排版：选尺寸，排到一张 A4 上\n4. 导出：PNG / PDF 原图质量，或 AirPrint 直接打")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.85))
                                Text("全程离线，照片不出手机。")
                                    .font(.footnote)
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                job.isBusy = true
                job.statusMessage = "正在读取原图…"
                defer { job.isBusy = false }
                guard let data = try? await newItem.loadTransferable(type: Data.self),
                      let image = UIImage(data: data)?.normalized()
                else {
                    job.statusMessage = "读取失败，请换一张照片再试。"
                    return
                }
                job.setOriginal(image: image, data: data)
            }
        }
    }

    private func saveOriginalToPhotos() {
        guard let data = job.originalData else { return }
        savingOriginal = true
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in
                    savingOriginal = false
                    saveResult = "没有相册权限，请在设置里允许“添加照片”。"
                }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(
                    with: .photo, data: data, options: nil)
            } completionHandler: { success, _ in
                Task { @MainActor in
                    savingOriginal = false
                    saveResult = success ? "原图已存到相册。" : "保存失败，请再试一次。"
                }
            }
        }
    }
}
