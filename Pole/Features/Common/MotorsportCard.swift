import SwiftUI

private let motorsportCardCornerRadius: CGFloat = 16

/// 通用赛车卡片容器——中央 content + 右侧 trailing accessory。
/// 卡片本体玻璃材质 + 16pt 圆角 + 微阴影,LIVE 状态加红色 stroke。
/// 系列识别:不再用左侧彩条,完全靠 row 内 series shortName 文字的 brandColor 染色区分。
struct MotorsportCard<Content: View, Trailing: View>: View {
    let series: MotorsportSeries
    let isLive: Bool
    @ViewBuilder let content: () -> Content
    @ViewBuilder let trailing: () -> Trailing

    init(
        series: MotorsportSeries,
        isLive: Bool = false,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.series = series
        self.isLive = isLive
        self.content = content
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            content()
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(MotorsportCardSurface(isLive: isLive))
    }
}

/// 卡片底层材质 — iOS 26 用 Liquid Glass 自带 specular + 自适应描边,
/// LIVE 态用 brand color tint 让活跃比赛在长 list 里跳出来;
/// 旧 SDK fallback 走 fill+stroke+gradient+shadow 四层装饰。
private struct MotorsportCardSurface: ViewModifier {
    let isLive: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // glassEffect(in:) 只定义材质形状,不 clip view content。
            // 必须显式 clipShape 让 HStack 第一项的彩条左侧矩形角被裁成卡片圆角弧,
            // 否则彩条会"溢出"到圆角外面看起来像两块独立 view。
            content
                .clipShape(RoundedRectangle(cornerRadius: motorsportCardCornerRadius, style: .continuous))
                .glassEffect(
                    isLive ? .regular.tint(BrandPalette.liveRed.opacity(0.35)) : .regular,
                    in: RoundedRectangle(cornerRadius: motorsportCardCornerRadius, style: .continuous)
                )
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.systemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            isLive ? BrandPalette.liveRed.opacity(0.55) : Color.white.opacity(0.12),
                            lineWidth: isLive ? 1.5 : 0.5
                        )
                )
                .overlay(alignment: .top) {
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), Color.clear],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 18)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
                .shadow(
                    color: isLive ? BrandPalette.liveRed.opacity(0.18) : .clear,
                    radius: 8, x: 0, y: 0
                )
        }
    }
}
