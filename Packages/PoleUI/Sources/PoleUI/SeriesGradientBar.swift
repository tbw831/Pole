import SwiftUI
import PoleDomain
import PoleDesignSystem

/// 卡片左侧系列彩条——快速识别 series。
/// 默认不限定 height,在 HStack 里靠外层 padding 控制上下边距,让 Capsule 自动跟 sibling 等高,
/// 端帽视觉与卡片 16pt 圆角对上。
public struct SeriesGradientBar: View {
    public let series: MotorsportSeries
    public var width: CGFloat
    public var height: CGFloat?

    public init(series: MotorsportSeries, width: CGFloat = 5, height: CGFloat? = nil) {
        self.series = series
        self.width = width
        self.height = height
    }

    public var body: some View {
        Capsule()
            .fill(series.brandGradient)
            .frame(width: width)
            .frame(maxHeight: height ?? .infinity)
    }
}
