import SwiftUI
import PoleDesignSystem

/// 详情页顶部 hero header——大 banner + 底部黑色渐变 + 玻璃浮层文字。
/// 支持 banner image / SVG image,失败时 fallback 系列彩色渐变作为背景。
struct GlassHeroHeader<TopContent: View>: View {
    let title: String
    let subtitle: String
    let series: MotorsportSeries
    let bannerURL: URL?
    let svgURL: URL?
    let badge: EventStatus?
    var enableSpeedLines: Bool
    @ViewBuilder let topAccessory: () -> TopContent

    @State private var appeared = false

    init(
        title: String,
        subtitle: String,
        series: MotorsportSeries,
        bannerURL: URL? = nil,
        svgURL: URL? = nil,
        badge: EventStatus? = nil,
        enableSpeedLines: Bool = false,
        @ViewBuilder topAccessory: @escaping () -> TopContent = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.series = series
        self.bannerURL = bannerURL
        self.svgURL = svgURL
        self.badge = badge
        self.enableSpeedLines = enableSpeedLines
        self.topAccessory = topAccessory
    }

    var body: some View {
        baseHeroZStack
            .frame(height: 220)
            .scaleEffect(appeared ? 1.0 : 0.96)
            .opacity(appeared ? 1.0 : 0.0)
            .onAppear {
                withAnimation(DS.Motion.raceEntry) { appeared = true }
            }
    }

    @ViewBuilder
    private var baseHeroZStack: some View {
        ZStack(alignment: .bottomLeading) {
            backgroundLayer
                .frame(height: 217)
                .clipped()

            // 底部黑色渐变,文字保证可读
            LinearGradient(
                colors: [.black.opacity(0.0), .black.opacity(0.75)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 130)
            .frame(maxWidth: .infinity, alignment: .bottom)
            .allowsHitTesting(false)

            // 顶部右侧 status badge
            if let badge = badge {
                VStack {
                    HStack {
                        Spacer()
                        StatusBadge(status: badge)
                    }
                    Spacer()
                }
                .padding(12)
            }

            // 底部信息
            VStack(alignment: .leading, spacing: 6) {
                topAccessory()
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        if let svgURL = svgURL {
            ZStack {
                series.brandGradient
                    .opacity(0.3)
                // SVG 上移一点 — 220 高 banner 底部 130 是黑色渐变文字区,
                // 不上移赛道下半会被遮住。
                SVGImageView(url: svgURL)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 60)   // 给底部文字区让位
            }
        } else if let url = bannerURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .empty:
                    series.brandGradient
                        .overlay(ProgressView().tint(.white))
                case .failure:
                    series.brandGradient
                @unknown default:
                    series.brandGradient
                }
            }
        } else {
            series.brandGradient
        }
    }
}

extension GlassHeroHeader where TopContent == EmptyView {
    init(
        title: String,
        subtitle: String,
        series: MotorsportSeries,
        bannerURL: URL? = nil,
        svgURL: URL? = nil,
        badge: EventStatus? = nil,
        enableSpeedLines: Bool = false
    ) {
        self.init(
            title: title, subtitle: subtitle, series: series,
            bannerURL: bannerURL, svgURL: svgURL, badge: badge,
            enableSpeedLines: enableSpeedLines,
            topAccessory: { EmptyView() }
        )
    }
}
