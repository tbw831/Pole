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
