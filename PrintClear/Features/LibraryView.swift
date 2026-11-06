import SwiftUI
import UIKit

/// 素材库（历史库）：先裁好的图文都存在这里，随时加到排版页上。
/// 点名字可以改名；左滑或点垃圾桶删除。
struct LibraryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PrintJob.self) private var job
    @State private var renameItem: LibraryItem?
    @State private var renameText = ""
    @State private var note = ""

    var body: some View {
        ZStack {
            GlassBackground()
            ScrollView {
                VStack(spacing: 18) {
                    Text("素材库")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                    Text("先裁好的图文都存在这里，随时加到排版页上。")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)

                    if library.items.isEmpty {
                        GlassCard {
                            Text("还是空的。\n去“抠图”裁好一张，点“存入素材库”。")
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .padding(.vertical, 20)
                        }
                    }

                    ForEach(library.items) { item in
                        GlassCard {
                            HStack(spacing: 12) {
                                if let img = library.image(for: item) {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 72, height: 72)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name)
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                        .onTapGesture {
                                            renameItem = item
                                            renameText = item.name
                                        }
                                    Text("\(Int(item.widthMM))×\(Int(item.heightMM))mm · \(item.createdAt, format: .dateTime.month().day().hour().minute())")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.75))
                                    Text("点名字可以改名")
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                                Spacer()
                                Button("加到排版") {
                                    if let image = library.image(for: item) {
                                        job.addLibraryItem(item, image: image)
                                        note = "已加到排版页：\(item.name)，去“排版”拖动位置。"
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.cyan)
                                Button(role: .destructive) {
                                    library.delete(item)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.bordered)
                                .tint(.white)
                            }
                        }
                    }

                    if !note.isEmpty {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding()
            }
        }
        .alert("改名字", isPresented: Binding(
            get: { renameItem != nil },
            set: { if !$0 { renameItem = nil } }
        )) {
            TextField("名字", text: $renameText)
            Button("确定") {
                if let item = renameItem, !renameText.isEmpty {
                    library.rename(item, to: renameText)
                }
                renameItem = nil
            }
            Button("取消", role: .cancel) { renameItem = nil }
        }
    }
}
