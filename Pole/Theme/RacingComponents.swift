import SwiftUI

// MARK: - SeriesTopAccent
//
// 卡片顶部 3px 系列品牌色条 + 右端拖尾渐变到透明(赛旗末端语义)。
// 用法: 在 dsListCard / MotorsportCard / driver / team 卡片顶部叠加。

public struct SeriesTopAccent: View {
    let series: MotorsportSeries
    var height: CGFloat = 3

    public init(series: MotorsportSeries, height: CGFloat = 3) {
        self.series = series
        self.height = height
    }

    public var body: some View {
        LinearGradient(
            colors: [series.brandColor, series.brandColor.opacity(0.0)],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

#Preview("SeriesTopAccent · all series") {
    VStack(spacing: 8) {
        SeriesTopAccent(series: .f1)
        SeriesTopAccent(series: .motogp)
        SeriesTopAccent(series: .wssp)
        SeriesTopAccent(series: .fe)
    }
    .padding()
    .background(DS.Palette.tarmacBg)
}

// MARK: - CheckerStripe
//
// 黑白(双模色差感知)棋盘格。
// Layout: horizontal(底部一条) / vertical(右侧一条) / fill(满铺背景纹理)
// trait-aware: Dark 用 white@opacity, Light 用 black@opacity 在透明背景上画格

public struct CheckerStripe: View {
    public enum Layout { case horizontal, vertical, fill }

    let layout: Layout
    var cellSize: CGFloat
    var opacity: Double

    @Environment(\.colorScheme) private var colorScheme

    public init(_ layout: Layout, cellSize: CGFloat = 6, opacity: Double = 1.0) {
        self.layout = layout
        self.cellSize = cellSize
        self.opacity = opacity
    }

    public var body: some View {
        Canvas { context, size in
            let color = (colorScheme == .dark ? Color.white : Color.black).opacity(opacity)
            let cols = Int(ceil(size.width / cellSize))
            let rows = Int(ceil(size.height / cellSize))
            for r in 0..<rows {
                for c in 0..<cols {
                    if (r + c).isMultiple(of: 2) {
                        let rect = CGRect(x: CGFloat(c) * cellSize,
                                          y: CGFloat(r) * cellSize,
                                          width: cellSize,
                                          height: cellSize)
                        context.fill(Path(rect), with: .color(color))
                    }
                }
            }
        }
        .frame(maxWidth: layout == .vertical ? cellSize * 2 : .infinity,
               maxHeight: layout == .horizontal ? cellSize * 2 : .infinity)
        .accessibilityHidden(true)
    }
}

#Preview("CheckerStripe · variants") {
    VStack(spacing: 16) {
        CheckerStripe(.horizontal)
            .frame(height: 12)
        CheckerStripe(.vertical)
            .frame(width: 12, height: 60)
        CheckerStripe(.fill, opacity: 0.06)
            .frame(width: 200, height: 100)
            .background(DS.Palette.tarmacBg)
    }
    .padding()
    .background(DS.Palette.tarmacBg)
}

// MARK: - StartLightGrid
//
// F1 起跑灯阵列 — 5 个红圆灯。
// .countdown(litCount: 0..5): 递进点亮,模拟 5-1 倒计时
// .lightsOut: 全灭,模拟起步瞬间
// .idle: 全灭,无动画(Empty state 用)

public struct StartLightGrid: View {
    public enum Mode: Equatable {
        case countdown(litCount: Int)
        case lightsOut
        case idle
    }

    let mode: Mode
    var size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(mode: Mode, size: CGFloat = 14) {
        self.mode = mode
        self.size = size
    }

    public var body: some View {
        HStack(spacing: size * 0.5) {
            ForEach(0..<5, id: \.self) { idx in
                Circle()
                    .fill(isLit(idx) ? DS.Palette.racingRed : DS.Palette.tarmacHairline)
                    .frame(width: size, height: size)
                    .shadow(
                        color: isLit(idx) ? DS.Palette.racingRed.opacity(0.6) : .clear,
                        radius: size * 0.4
                    )
                    .animation(reduceMotion ? nil : DS.Motion.countdown, value: mode)
            }
        }
        .accessibilityLabel(accessibilityText)
    }

    private func isLit(_ idx: Int) -> Bool {
        switch mode {
        case .idle, .lightsOut: return false
        case .countdown(let litCount): return idx < litCount
        }
    }

    private var accessibilityText: String {
        switch mode {
        case .idle: return L10n.t(zh: "起跑灯待机", en: "Start lights idle")
        case .lightsOut: return L10n.t(zh: "起跑灯熄灭, 比赛已开始", en: "Lights out, race started")
        case .countdown(let n): return L10n.t(zh: "起跑倒计时 \(n) 灯", en: "Countdown, \(n) lights lit")
        }
    }
}

#Preview("StartLightGrid · all modes") {
    VStack(spacing: 24) {
        StartLightGrid(mode: .idle)
        StartLightGrid(mode: .countdown(litCount: 1))
        StartLightGrid(mode: .countdown(litCount: 3))
        StartLightGrid(mode: .countdown(litCount: 5))
        StartLightGrid(mode: .lightsOut)
    }
    .padding(32)
    .background(DS.Palette.tarmacBg)
}
