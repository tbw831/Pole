import SwiftUI
import PoleDomain

/// detail header 用的天气小卡片——内嵌 task 自己拉,失败 / 远期赛事(>3 天)隐藏。
struct WeatherCard: View {
    let location: String
    let targetDate: Date

    @State private var snapshot: WeatherSnapshot?
    @State private var loaded = false

    var body: some View {
        Group {
            if let s = snapshot {
                HStack(spacing: 8) {
                    Image(systemName: s.sfSymbol)
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .frame(width: 28, alignment: .center)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(s.maxTempC)° / \(s.minTempC)°")
                            .font(.subheadline.monospacedDigit())
                        Text(s.description)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(s.date, format: .dateTime.month(.abbreviated).day().beijing())
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            } else if !loaded {
                HStack {
                    ProgressView()
                    Text(L10n.t(zh: "天气加载中…", en: "Loading weather…")).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                EmptyView()   // 加载失败 / 远期 → 不占位
            }
        }
        // task id 用 location + 按天 truncate(86400 秒/天)避免 Date 纳秒级微变导致重发请求,
        // 同一 round 反复进入不应该每次都打 wttr.in。
        .task(id: "\(location)-\(Int(targetDate.timeIntervalSince1970 / 86400))") {
            // 远于 3 天的 round 不拉(wttr.in 只给 3 天预报)
            let interval = targetDate.timeIntervalSinceNow
            guard interval > -86400, interval < 3 * 86400 else {
                loaded = true
                return
            }
            snapshot = (try? await WttrClient.shared.fetchForecast(
                location: location,
                targetDate: targetDate
            ))
            loaded = true
        }
    }
}
