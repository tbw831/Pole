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
