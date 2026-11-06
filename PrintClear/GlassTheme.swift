import SwiftUI

/// 液态玻璃主题：深色渐变底 + 玻璃卡片（iOS 26 Liquid Glass）。
struct GlassBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.10, blue: 0.26),
                    Color(red: 0.08, green: 0.32, blue: 0.42),
                    Color(red: 0.05, green: 0.12, blue: 0.30),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            Circle()
                .fill(Color.blue.opacity(0.35))
                .frame(width: 320, height: 320)
                .blur(radius: 60)
                .offset(x: -120, y: -280)
            Circle()
                .fill(Color.teal.opacity(0.30))
                .frame(width: 280, height: 280)
                .blur(radius: 60)
                .offset(x: 140, y: 320)
            Circle()
                .fill(Color.purple.opacity(0.22))
                .frame(width: 200, height: 200)
                .blur(radius: 50)
                .offset(x: 120, y: -140)
        }
    }
}

/// 玻璃卡片：内容 + 液态玻璃效果，可交互。
struct GlassCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding()
            .glassEffect(
                .regular.tint(.white.opacity(0.14)).interactive(),
                in: RoundedRectangle(cornerRadius: 24)
            )
    }
}

/// 玻璃小徽章：用于结果、状态等小块内容。
struct GlassPill<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular.tint(.white.opacity(0.10)), in: Capsule())
    }
}
