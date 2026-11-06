import SwiftUI
import UIKit

/// 第四步：导出。PNG / PDF 都是 300 DPI 原图质量；AirPrint 直接打；原图另存。
struct ExportView: View {
    @Environment(PrintJob.self) private var job
    @State private var pngURL: URL?
    @State private var pdfURL: URL?
    @State private var note = ""

    var body: some View {
        ZStack {
            GlassBackground()
            ScrollView {
                VStack(spacing: 18) {
                    Text("导出打印")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)

                    if job.pageImage == nil {
                        GlassCard {
                            Text("请先去“排版”生成 A4 页面。")
                                .foregroundStyle(.white)
                        }
                    } else {
                        if let page = job.pageImage {
                            GlassCard {
                                Image(uiImage: page)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 380)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }

                        GlassCard {
                            VStack(spacing: 12) {
                                if let pngURL {
                                    ShareLink(item: pngURL) {
                                        Label("导出 PNG（300 DPI 原图质量）", systemImage: "photo")
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 4)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.cyan)
                                }

                                if let pdfURL {
                                    ShareLink(item: pdfURL) {
                                        Label("导出 PDF（A4，拿去电脑打）", systemImage: "doc")
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 4)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.cyan)
                                }

                                Button {
                                    airPrint()
                                } label: {
                                    Label("AirPrint 直接打印", systemImage: "printer")
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 4)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)

                                if !note.isEmpty {
                                    Text(note)
                                        .font(.footnote)
                                        .foregroundStyle(.white.opacity(0.85))
                                        .multilineTextAlignment(.center)
                                }
                                Text("导出不压缩：PNG 是 2480×3508 像素，PDF 按 A4 尺寸、图片原分辨率嵌入。")
                                    .font(.footnote)
                                    .foregroundStyle(.white.opacity(0.6))
                                    .multilineTextAlignment(.center)
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .onAppear {
            prepareFiles()
        }
    }

    // MARK: - 文件

    private func prepareFiles() {
        let temp = FileManager.default.temporaryDirectory
        if let page = job.pageImage, let data = page.pngData() {
            let url = temp.appendingPathComponent("印得清-A4.png")
            try? data.write(to: url)
            pngURL = url
        }
        if let pdf = job.pagePDF {
            let url = temp.appendingPathComponent("印得清-A4.pdf")
            try? pdf.write(to: url)
            pdfURL = url
        }
    }

    // MARK: - AirPrint

    private func airPrint() {
        prepareFiles()
        guard let pdfURL else {
            note = "还没有排版好的页面，请先去“排版”。"
            return
        }
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = "印得清 A4"
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = pdfURL
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })
        else {
            note = "打不开打印界面，请再试一次。"
            return
        }
        let presented = controller.present(
            from: window.bounds, in: window, animated: true
        ) { _, completed, _ in
            if completed {
                Task { @MainActor in
                    note = "已发送到打印机。"
                }
            }
        }
        if !presented {
            note = "打不开打印界面，请确认已连接支持 AirPrint 的打印机。"
        }
    }
}
