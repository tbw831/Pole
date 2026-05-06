import SwiftUI

/// 简版车手 profile — 只接 (name + series),无 standing 对象。
/// 关注页点 MotoGP / FE 车手时跳这里(关注表只持久化 id+name,没 standing snapshot)。
/// 不显示赛季 stats(没数据来源),只显示标题 + Wikipedia/LLM 简介。
struct SimpleDriverProfileView: View {
    let name: String
    let series: MotorsportSeries

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(MotorsportNames.driverFullName(rawFullName: name, series: series))
                        .font(.title2.weight(.semibold))
                    Text(series.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            WikipediaSummarySection(queryTitle: name, series: series)
        }
        .dsDetailList()
        .navigationTitle(MotorsportNames.driverFullName(rawFullName: name, series: series))
        .navigationBarTitleDisplayMode(.inline)
        .tint(series.brandColor)
    }
}

/// FollowFeedView 用的轻量 route — name + series,跳进 SimpleDriverProfileView。
struct SimpleDriverRoute: Hashable {
    let name: String
    let seriesRaw: String

    var series: MotorsportSeries? {
        MotorsportSeries(rawValue: seriesRaw)
    }
}
