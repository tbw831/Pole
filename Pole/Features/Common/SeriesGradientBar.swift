import SwiftUI
import PoleDomain
import PoleDesignSystem

/// 卡片左侧系列彩条——快速识别 series。
/// 默认不限定 height,在 HStack 里靠外层 padding 控制上下边距,让 Capsule 自动跟 sibling 等高,
/// 端帽视觉与卡片 16pt 圆角对上。
struct SeriesGradientBar: View {
    let series: MotorsportSeries
    var width: CGFloat = 5
    var height: CGFloat? = nil

    var body: some View {
        Capsule()
            .fill(series.brandGradient)
            .frame(width: width)
            .frame(maxHeight: height ?? .infinity)
    }
}
