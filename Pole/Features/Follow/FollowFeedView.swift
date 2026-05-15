import SwiftUI
import SwiftData
import UIKit   // UIPasteboard for context menu "copy name"
import PoleDesignSystem
import PoleDomain

struct FollowFeedView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FollowedItem.addedAt, order: .reverse) private var items: [FollowedItem]

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(L10n.t(zh: "关注", en: "Follow"))
                // 关注 row 点击 → 跟积分榜一致的 detail 路由
                .navigationDestination(for: TeamNewsRoute.self) { route in
                    TeamDetailView(teamName: route.teamName, series: route.series)
                }
                .navigationDestination(for: F1DriverDetailRoute.self) { route in
                    F1DriverDetailView(
                        driverId: route.driverId,
                        driverName: route.driverName,
                        season: route.season
                    )
                }
                .navigationDestination(for: WSSPRiderDetailRoute.self) { route in
                    WSSPRiderDetailView(riderName: route.riderName)
                }
                .navigationDestination(for: SimpleDriverRoute.self) { route in
                    if let s = route.series {
                        SimpleDriverProfileView(name: route.name, series: s)
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if items.isEmpty {
            VStack(spacing: DS.Spacing.lg) {
                StartLightGrid(mode: .idle, size: 14)
                Text(L10n.t(zh: "尚未关注任何车手 / 车队", en: "No followed athletes or teams"))
                    .font(DS.Font.heroSubtitle)
                    .foregroundStyle(.secondary)
                Button(L10n.t(zh: "去赛车 tab 发现", en: "Discover in Race tab")) {
                    NotificationCenter.default.post(name: .navigateToMotorsportTab, object: nil)
                }
                .buttonStyle(.dsRacingButton)
            }
            .frame(maxWidth: .infinity, minHeight: 200)
            .padding()
            .background(CheckerStripe(.fill, opacity: 0.04))
        } else {
            ScrollView {
                LazyVStack(spacing: DS.Spacing.sm) {
                    ForEach(grouped, id: \.0) { series, rows in
                        // Section header
                        HStack {
                            Text(seriesLabel(series).uppercased())
                                .font(DS.Font.toolLabel)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.top, DS.Spacing.sm)

                        ForEach(rows) { item in
                            FollowedRowLink(item: item)
                        }
                    }
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm)
            }
        }
    }

    /// 按 series 分组,组内按 addedAt 倒序(已经由 @Query 排好,只需保持稳定)。
    private var grouped: [(String, [FollowedItem])] {
        let buckets = Dictionary(grouping: items, by: \.seriesRaw)
        return buckets
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
    }

    private func seriesLabel(_ raw: String) -> String {
        MotorsportSeries(rawValue: raw)?.displayName ?? raw.uppercased()
    }
}

// MARK: - Row Link Wrapper(根据 series 派发到对应 detail 路由)

private struct FollowedRowLink: View {
    let item: FollowedItem
    @Environment(\.modelContext) private var context

    var body: some View {
        // 按 (kind, series) 派发跟积分榜一致的 route 类型
        Group {
            switch (item.kindRaw, item.seriesRaw) {
            case ("athlete", "f1"):
                NavigationLink(value: F1DriverDetailRoute(
                    driverId: item.refId,
                    driverName: item.displayName,
                    season: "current"
                )) { FollowedRow(item: item) }
                .buttonStyle(.plain)

            case ("athlete", "wssp"):
                NavigationLink(value: WSSPRiderDetailRoute(riderName: item.displayName)) {
                    FollowedRow(item: item)
                }
                .buttonStyle(.plain)

            case ("athlete", "motogp"), ("athlete", "fe"):
                NavigationLink(value: SimpleDriverRoute(
                    name: item.displayName, seriesRaw: item.seriesRaw
                )) { FollowedRow(item: item) }
                .buttonStyle(.plain)

            case ("team", _), ("league", _):
                if let s = MotorsportSeries(rawValue: item.seriesRaw) {
                    NavigationLink(value: TeamNewsRoute(teamName: item.displayName, series: s)) {
                        FollowedRow(item: item)
                    }
                    .buttonStyle(.plain)
                } else {
                    FollowedRow(item: item)
                }

            default:
                FollowedRow(item: item)
            }
        }
        // 长按弹快捷菜单 — 取消关注 / 复制名字。比 swipe-to-delete 更显眼。
        .contextMenu {
            Button(role: .destructive) {
                context.delete(item)
                try? context.save()
                WidgetSnapshotBuilder.refresh(force: true)
            } label: {
                Label(L10n.t(zh: "取消关注", en: "Unfollow"), systemImage: "star.slash")
            }

            Button {
                UIPasteboard.general.string = item.displayName
            } label: {
                Label(L10n.t(zh: "复制名字", en: "Copy Name"), systemImage: "doc.on.doc")
            }
        }
    }
}

// MARK: - Row

private struct FollowedRow: View {
    let item: FollowedItem

    private var seriesAccent: Color? {
        MotorsportSeries(rawValue: item.seriesRaw)?.brandColor
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: kindIcon)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(localizedName)
                    .font(.subheadline.weight(.medium))
                Text(kindLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(item.addedAt, format: .dateTime.month().day().beijing())
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .dsListCard(seriesAccent: seriesAccent)
    }

    /// item.displayName 持久化的是关注当时的 raw 名(英文 fullName / 厂商原名),
    /// 显示时按当前语言 + 系列再走 mapping —— 让"切语言关注列表跟着变"。
    private var localizedName: String {
        guard let series = MotorsportSeries(rawValue: item.seriesRaw) else { return item.displayName }
        switch item.kindRaw {
        case "athlete":
            return MotorsportNames.driverShortName(rawFullName: item.displayName, series: series)
        case "team", "league":
            return MotorsportNames.teamName(raw: item.displayName, series: series)
        default:
            return item.displayName
        }
    }

    private var kindIcon: String {
        switch item.kindRaw {
        case "athlete": return "person.fill"
        case "team":    return "person.3.fill"
        case "league":  return "trophy.fill"
        default:        return "questionmark"
        }
    }

    private var kindLabel: String {
        switch item.kindRaw {
        case "athlete": return L10n.t(zh: "车手", en: "Athlete")
        case "team":    return L10n.t(zh: "车队", en: "Team")
        case "league":  return L10n.t(zh: "联赛", en: "League")
        default:        return item.kindRaw
        }
    }
}
