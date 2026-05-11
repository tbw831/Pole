import SwiftUI

/// 统一状态徽章——LIVE 状态加微弱 pulse 动画。
/// 用户开启"减少动态效果"(`accessibilityReduceMotion`)时改静态高亮圆点,
/// 不再 60Hz 重绘,符合 HIG 可访问性规范。
struct StatusBadge: View {
    let status: EventStatus

    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if status == .live {
            HStack(spacing: 4) {
                Circle()
                    .fill(DS.Palette.live)
                    .frame(width: 6, height: 6)
                    .scaleEffect(reduceMotion ? 1.0 : (pulse ? 1.0 : 0.7))
                    .opacity(reduceMotion ? 1.0 : (pulse ? 1.0 : 0.5))
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                        value: pulse
                    )
                    .onAppear { if !reduceMotion { pulse = true } }
                    .onDisappear { pulse = false }
                Text(status.displayLabel)
                    .font(.caption2.weight(.bold))
            }
            .dsLiveBadge()
        } else {
            HStack(spacing: 4) {
                Text(status.displayLabel)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.brandColor, in: Capsule())
        }
    }
}
