import SwiftUI
import UIKit

/// 第三步：排版。一张 A4 上放多个不同的图文：从素材库加、加文字，
/// 拖动改位置，右下角拉大拉小，也能自动排版（按大小归类、最省纸）。
struct LayoutView: View {
    @Environment(PrintJob.self) private var job
    @Environment(LibraryStore.self) private var library
    @State private var showingLibraryPicker = false
    @State private var showingAddText = false
    @State private var newText = ""
    @State private var newFontSize: Double = 16
    @State private var selectedTemplate: LayoutTemplate = .smart
    @FocusState private var focusedField: SizeField?
    @State private var rendering = false
    @State private var note = ""

    /// 尺寸面板里正在输的框（宽 / 高），用来收起键盘。
    private enum SizeField: Hashable { case width, height }

    var body: some View {
        ZStack {
            GlassBackground()
            ScrollView {
                VStack(spacing: 18) {
                    Text("排版")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)

                    toolbarCard
                    canvasCard
                    if let selected = selectedItem {
                        sizePanel(for: selected)
                    }
                    if job.layoutOverflow {
                        GlassCard {
                            Text("有内容超出 A4 纸面，导出时会被裁掉，请拖回来或改小一点。")
                                .font(.footnote)
                                .foregroundStyle(.yellow)
                        }
                    }
                    previewCard
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .toolbar {
            // 数字键盘没有回车键，这里加一个“完成”收起键盘。
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") {
                    focusedField = nil
                    refreshRender()
                }
            }
        }
        .sheet(isPresented: $showingLibraryPicker) {
            LibraryPickerSheet { item in
                if let image = library.image(for: item) {
                    job.addLibraryItem(item, image: image)
                    note = "已加到排版页：\(item.name)，拖动可以改位置。"
                    refreshRender()
                }
            }
            .environment(library)
        }
        .sheet(isPresented: $showingAddText) {
            AddTextSheet(
                text: $newText, fontSize: $newFontSize,
                onAdd: {
                    job.addTextItem(content: newText, fontSizePt: newFontSize)
                    newText = ""
                    note = "文字已加到排版页，拖动可以改位置。"
                    refreshRender()
                })
        }
        .onAppear {
            if !job.pageItems.isEmpty && job.pageImage == nil {
                refreshRender()
            }
        }
    }

    private var selectedItem: PageItem? {
        guard let id = job.selectedPageItemId else { return nil }
        return job.pageItems.first { $0.id == id }
    }

    // MARK: - 工具栏

    private var toolbarCard: some View {
        GlassCard {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        showingLibraryPicker = true
                    } label: {
                        Label("加素材", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    Button {
                        showingAddText = true
                    } label: {
                        Label("加文字", systemImage: "textformat")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                }
                HStack(spacing: 10) {
                    Picker("排版类型", selection: $selectedTemplate) {
                        ForEach(LayoutTemplate.allCases) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.white)
                    Button {
                        note = job.applyLayout(template: selectedTemplate)
                        refreshRender()
                    } label: {
                        Label("自动排版", systemImage: "rectangle.grid.3x2")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    .disabled(job.pageItems.isEmpty)
                }
                HStack(spacing: 10) {
                    Button(role: .destructive) {
                        job.clearPage()
                        note = ""
                    } label: {
                        Label("清空", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .disabled(job.pageItems.isEmpty)
                }
                Text("页上有 \(job.pageItems.count) 项。点一下选中，拖动改位置；同一素材加多次，就能印多张。智能推荐会按图片大小、方向挑裁得最少的排法。")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - A4 画布

    private var canvasCard: some View {
        GlassCard {
            VStack(spacing: 10) {
                Text("A4 画布 · 210×297mm")
                    .font(.headline)
                    .foregroundStyle(.white)
                if job.pageItems.isEmpty {
                    Text("还是空的。点“加素材”从素材库选，或“加文字”写一段文字。")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 40)
                } else {
                    GeometryReader { geo in
                        let scale = geo.size.width / 210.0
                        ZStack(alignment: .topLeading) {
                            Color.white
                            ForEach(job.pageItems) { item in
                                PageItemView(
                                    item: item,
                                    scale: scale,
                                    isSelected: job.selectedPageItemId == item.id,
                                    onSelect: { job.selectedPageItemId = item.id },
                                    onMove: { dx, dy in job.moveItem(id: item.id, dxMM: dx, dyMM: dy) },
                                    onResize: { dw, dh in
                                        job.setItemSize(
                                            id: item.id,
                                            widthMM: item.widthMM + dw,
                                            heightMM: item.heightMM + dh)
                                    },
                                    onEnd: { refreshRender() }
                                )
                            }
                        }
                        .frame(width: geo.size.width, height: geo.size.width * 297 / 210)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .onTapGesture {
                            // 点画布空白处，收起尺寸框的键盘。
                            focusedField = nil
                        }
                    }
                    .aspectRatio(CGSize(width: 210, height: 297), contentMode: .fit)
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

    // MARK: - 选中项的尺寸面板

    private func sizePanel(for item: PageItem) -> some View {
        GlassCard {
            VStack(spacing: 10) {
                HStack {
                    Text("已选：\(item.name)")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Spacer()
                    Button {
                        job.rotateItem(id: item.id)
                        refreshRender()
                    } label: {
                        Label("旋转 90°", systemImage: "rotate.right")
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    Button(role: .destructive) {
                        job.removePageItem(id: item.id)
                        refreshRender()
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
                HStack(spacing: 12) {
                    HStack {
                        Text("宽")
                            .foregroundStyle(.white)
                        TextField(
                            "宽",
                            value: Binding(
                                get: { item.widthMM },
                                set: { job.setItemSize(id: item.id, widthMM: $0, heightMM: item.heightMM) }
                            ),
                            format: .number.precision(.fractionLength(0...1))
                        )
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .width)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 76)
                        Text("mm")
                            .foregroundStyle(.white)
                    }
                    HStack {
                        Text("高")
                            .foregroundStyle(.white)
                        TextField(
                            "高",
                            value: Binding(
                                get: { item.heightMM },
                                set: { job.setItemSize(id: item.id, widthMM: item.widthMM, heightMM: $0) }
                            ),
                            format: .number.precision(.fractionLength(0...1))
                        )
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .height)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 76)
                        Text("mm")
                            .foregroundStyle(.white)
                    }
                    HStack {
                        Text("位置")
                            .foregroundStyle(.white)
                        Text("\(Int(item.xMM)), \(Int(item.yMM))")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                Text("改完尺寸点键盘上的“完成”就重新渲染；点画布空白处、上下滑一下也能收起键盘。宽高只显示一位小数。文字项改大小会自动缩放字号。")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    // MARK: - 渲染预览

    private var previewCard: some View {
        GlassCard {
            VStack(spacing: 10) {
                Text("导出预览")
                    .font(.headline)
                    .foregroundStyle(.white)
                if rendering {
                    ProgressView("渲染中…")
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
                } else if !job.pageItems.isEmpty {
                    Text("点“重新渲染”看导出效果。")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.75))
                }
                Button {
                    refreshRender()
                } label: {
                    Label("重新渲染", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.white)
                .disabled(job.pageItems.isEmpty)
            }
        }
    }

    // MARK: - 渲染

    private func refreshRender() {
        guard !job.pageItems.isEmpty else {
            job.pageImage = nil
            job.pagePDF = nil
            return
        }
        rendering = true
        Task {
            await job.renderPage()
            rendering = false
        }
    }
}

// MARK: - 画布上的一项（可拖动、右下角拉大小）

private struct PageItemView: View {
    let item: PageItem
    let scale: CGFloat // 每毫米对应多少 pt
    let isSelected: Bool
    let onSelect: () -> Void
    let onMove: (Double, Double) -> Void
    let onResize: (Double, Double) -> Void
    let onEnd: () -> Void

    @State private var lastMove: CGSize = .zero
    @State private var lastResize: CGSize = .zero

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            itemContent
            if isSelected {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10))
                            .foregroundStyle(.white)
                    )
                    .offset(x: 11, y: 11)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let dx = value.translation.width - lastResize.width
                                let dy = value.translation.height - lastResize.height
                                lastResize = value.translation
                                onResize(Double(dx / scale), Double(dy / scale))
                            }
                            .onEnded { _ in
                                lastResize = .zero
                                onEnd()
                            }
                    )
            }
        }
        .position(
            x: (item.xMM + item.widthMM / 2) * scale,
            y: (item.yMM + item.heightMM / 2) * scale
        )
        .overlay(
            Rectangle()
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        )
        .gesture(
            DragGesture()
                .onChanged { value in
                    let dx = value.translation.width - lastMove.width
                    let dy = value.translation.height - lastMove.height
                    lastMove = value.translation
                    onMove(Double(dx / scale), Double(dy / scale))
                }
                .onEnded { _ in
                    lastMove = .zero
                    onEnd()
                }
        )
        .onTapGesture {
            onSelect()
        }
    }

    @ViewBuilder
    private var itemContent: some View {
        // 转 90° / 270° 时，先按转之前的框画，再整个转过来。
        let sideways = item.rotation == 90 || item.rotation == 270
        let innerW = sideways ? item.heightMM : item.widthMM
        let innerH = sideways ? item.widthMM : item.heightMM
        Group {
            switch item.kind {
            case .image(let img):
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .clipped()
            case .text(let content, let fontSize):
                Text(content)
                    .font(.system(size: fontSize * 25.4 / 72 * scale))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(Color.white)
            }
        }
        .frame(width: innerW * scale, height: innerH * scale)
        .rotationEffect(.degrees(Double(item.rotation)))
        .frame(width: item.widthMM * scale, height: item.heightMM * scale)
    }
}

// MARK: - 从素材库选（弹窗）

private struct LibraryPickerSheet: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    let onPick: (LibraryItem) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackground()
                ScrollView {
                    VStack(spacing: 14) {
                        if library.items.isEmpty {
                            Text("素材库还是空的。\n先去“抠图”裁好一张，点“存入素材库”。")
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .padding(.vertical, 40)
                        }
                        ForEach(library.items) { item in
                            HStack(spacing: 12) {
                                if let img = library.image(for: item) {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 64, height: 64)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name)
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                    Text("\(Int(item.widthMM))×\(Int(item.heightMM))mm")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.75))
                                }
                                Spacer()
                                Button("添加") {
                                    onPick(item)
                                    dismiss()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.cyan)
                            }
                            .padding()
                            .glassEffect(
                                .regular.tint(.white.opacity(0.14)),
                                in: RoundedRectangle(cornerRadius: 20))
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("素材库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
    }
}

// MARK: - 加文字（弹窗）

private struct AddTextSheet: View {
    @Binding var text: String
    @Binding var fontSize: Double
    @Environment(\.dismiss) private var dismiss
    let onAdd: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackground()
                VStack(spacing: 16) {
                    TextField("输入要印的文字（可换行）", text: $text, axis: .vertical)
                        .lineLimit(3...6)
                        .padding()
                        .glassEffect(
                            .regular.tint(.white.opacity(0.14)),
                            in: RoundedRectangle(cornerRadius: 16))
                        .foregroundStyle(.white)
                    HStack {
                        Text("字号")
                            .foregroundStyle(.white)
                        Picker("字号", selection: $fontSize) {
                            Text("12").tag(12.0)
                            Text("16").tag(16.0)
                            Text("20").tag(20.0)
                            Text("28").tag(28.0)
                            Text("36").tag(36.0)
                        }
                        .pickerStyle(.segmented)
                    }
                    Button {
                        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        onAdd()
                        dismiss()
                    } label: {
                        Label("加到排版页", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("加文字")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
    }
}
