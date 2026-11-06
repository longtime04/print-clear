import SwiftUI

struct ContentView: View {
    @State private var job = PrintJob()

    var body: some View {
        TabView {
            Tab("导入", systemImage: "photo.on.rectangle") {
                ImportView()
            }
            Tab("抠图", systemImage: "scissors") {
                CutoutView()
            }
            Tab("排版", systemImage: "doc.text") {
                LayoutView()
            }
            Tab("导出", systemImage: "square.and.arrow.up") {
                ExportView()
            }
        }
        .tint(.white)
        .environment(job)
    }
}
