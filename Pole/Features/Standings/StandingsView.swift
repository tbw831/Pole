import SwiftUI
import PoleDesignSystem
import PoleDomain

// MARK: - 顶层

struct StandingsView: View {
    @State private var series: MotorsportSeries = .f1
    /// 4 个 series ViewModel 上提到父级 — 切 segmented 时 child view 不重 mount,
    /// VM 状态(loaded data / 选中 driver/team tab)保留。每个 series 第一次切到才触发 .task load。
    @State private var f1VM = F1StandingsViewModel()
    @State private var motogpVM = MotoGPStandingsViewModel()
    @State private var wsspVM = WSSPStandingsViewModel()
    @State private var feVM = FEStandingsViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SegmentedPillPicker(selection: $series, items: MotorsportSeries.allCases) { s in
                    Text(s.shortName)
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.sm)

                switch series {
                case .f1:     F1StandingsContent(viewModel: f1VM)
                case .motogp: MotoGPStandingsContent(viewModel: motogpVM)
                case .wssp:   WSSPStandingsContent(viewModel: wsspVM)
                case .fe:     FEStandingsContent(viewModel: feVM)
                }
            }
            .navigationTitle(L10n.t(zh: "积分榜", en: "Standings"))
            .navigationBarTitleDisplayMode(.inline)
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
            .navigationDestination(for: MotoGPRiderStanding.self) { standing in
                MotoGPRiderDetailView(standing: standing)
            }
            .navigationDestination(for: FEDriverStanding.self) { standing in
                FEDriverDetailView(standing: standing)
            }
        }
    }
}

/// 车队/厂商详情 NavigationLink 路由值。
struct TeamNewsRoute: Hashable {
    let teamName: String
    let series: MotorsportSeries
}

/// F1 车手详情(积分趋势图)路由值。
struct F1DriverDetailRoute: Hashable {
    let driverId: String
    let driverName: String
    let season: String
}

/// WSSP 车手详情(积分趋势图)路由值。
struct WSSPRiderDetailRoute: Hashable {
    let riderName: String
}

// MARK: - F1

private enum DriverTeamTab: String, CaseIterable, Identifiable {
    case drivers
    case teams
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .drivers: return L10n.t(zh: "车手", en: "Drivers")
        case .teams:   return L10n.t(zh: "车队", en: "Teams")
        }
    }
}

@MainActor
@Observable
fileprivate final class F1StandingsViewModel {
    enum State {
        case idle
        case loading
        case loaded(drivers: [F1DriverStanding], constructors: [F1ConstructorStanding])
        case failed(message: String)
    }

    private(set) var state: State = .idle

    func load() async {
        state = .loading
        let client = JolpicaClient.shared
        do {
            async let drivers = client.fetchDriverStandings()
            async let constructors = client.fetchConstructorStandings()
            let (d, c) = try await (drivers, constructors)
            state = .loaded(drivers: d, constructors: c)
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }
}

private struct F1StandingsContent: View {
    @Bindable var viewModel: F1StandingsViewModel
    @State private var tab: DriverTeamTab = .drivers

    var body: some View {
        VStack(spacing: 0) {
            SegmentedPillPicker(selection: $tab, items: DriverTeamTab.allCases) { t in
                Text(t.displayName)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.xs)
            .padding(.bottom, DS.Spacing.xs)

            content
        }
        .task {
            if case .idle = viewModel.state { await viewModel.load() }
        }
        .refreshable { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView(L10n.t(zh: "加载中…", en: "Loading…"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let drivers, let constructors):
            switch tab {
            case .drivers:
                cardScroll(items: drivers) { standing in
                    NavigationLink(value: F1DriverDetailRoute(
                        driverId: standing.driver.id,
                        driverName: standing.driver.fullName,
                        season: "current"
                    )) {
                        F1DriverStandingRow(standing: standing).dsListCard()
                            .background(
                                standing.position == 1 ? DS.Palette.racingRedFaint : Color.clear,
                                in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }
            case .teams:
                cardScroll(items: constructors) { standing in
                    NavigationLink(value: TeamNewsRoute(teamName: standing.constructor.name, series: .f1)) {
                        F1ConstructorStandingRow(standing: standing).dsListCard()
                            .background(
                                standing.position == 1 ? DS.Palette.racingRedFaint : Color.clear,
                                in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        case .failed(let message):
            ErrorView(message: message) { Task { await viewModel.load() } }
        }
    }
}

private struct F1DriverStandingRow: View {
    let standing: F1DriverStanding

    var body: some View {
        HStack(spacing: 10) {
            PositionBadge(position: standing.position)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(standing.driver.displayName).font(.subheadline.weight(.medium))
                    if let n = standing.driver.permanentNumber {
                        Text("#\(n)").font(.caption2.bold()).foregroundStyle(.secondary)
                    }
                    if let code = standing.driver.code {
                        Text(code).font(.caption2.bold()).foregroundStyle(.tertiary)
                    }
                }
                Text(constructorChineseName).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            PointsBlock(points: standing.points, wins: standing.wins)
            FollowToggleButton(
                target: .athlete(id: standing.driver.id, sport: .motorsport, series: "f1"),
                displayName: standing.driver.fullName
            )
        }
        // VoiceOver:row 整体一句读完 + 关注按钮单独可点
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t(
            zh: "第 \(standing.position) 位 \(standing.driver.displayName) \(constructorChineseName) \(Int(standing.points)) 分 \(standing.wins) 胜",
            en: "P\(standing.position) \(standing.driver.displayName) \(constructorChineseName) \(Int(standing.points)) pts \(standing.wins) wins"
        ))
    }

    /// F1DriverStanding 只携带 constructorIds: [String](Ergast wire 字段),
    /// 一个 driver 当季最多对应 1 个车队;通过 MotorsportNames.teamName 走中文翻译。
    private var constructorChineseName: String {
        guard let raw = standing.constructorIds.first, !raw.isEmpty else { return "" }
        return MotorsportNames.teamName(raw: raw, series: .f1)
    }
}

private struct F1ConstructorStandingRow: View {
    let standing: F1ConstructorStanding

    var body: some View {
        HStack(spacing: 10) {
            PositionBadge(position: standing.position)
            Text(standing.constructor.displayName).font(.subheadline.weight(.medium))
            Spacer()
            PointsBlock(points: standing.points, wins: standing.wins)
            FollowToggleButton(
                target: .team(id: standing.constructor.id, sport: .motorsport, series: "f1"),
                displayName: standing.constructor.name
            )
        }
    }
}

// MARK: - MotoGP

private enum RiderTeamConsTab: String, CaseIterable, Identifiable {
    case riders
    case teams
    case constructors
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .riders:       return L10n.t(zh: "车手", en: "Riders")
        case .teams:        return L10n.t(zh: "车队", en: "Teams")
        case .constructors: return L10n.t(zh: "厂商", en: "Constructors")
        }
    }
}

@MainActor
@Observable
fileprivate final class MotoGPStandingsViewModel {
    enum State {
        case idle
        case loading
        case loaded(riders: [MotoGPRiderStanding], teams: [MotoGPTeamStanding], constructors: [MotoGPConstructorStanding])
        case failed(message: String)
    }

    private(set) var state: State = .idle

    func load() async {
        state = .loading
        let client = MotoGPClient.shared
        do {
            // riders 是源,team/constructor 是客户端聚合(同一份数据加工)。
            // 但 client 内部各自走独立请求,这里并发拉,简单。
            async let riders = client.fetchRiderStandings()
            async let teams = client.fetchTeamStandings()
            async let cons = client.fetchConstructorStandings()
            let (r, t, c) = try await (riders, teams, cons)
            state = .loaded(riders: r, teams: t, constructors: c)
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }
}

private struct MotoGPStandingsContent: View {
    @Bindable var viewModel: MotoGPStandingsViewModel
    @State private var tab: RiderTeamConsTab = .riders

    var body: some View {
        VStack(spacing: 0) {
            SegmentedPillPicker(selection: $tab, items: RiderTeamConsTab.allCases) { t in
                Text(t.displayName)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.xs)

            content
        }
        .task {
            if case .idle = viewModel.state { await viewModel.load() }
        }
        .refreshable { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView(L10n.t(zh: "加载中…", en: "Loading…")).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let riders, let teams, let constructors):
            switch tab {
            case .riders:
                cardScroll(items: riders) { standing in
                    NavigationLink(value: standing) {
                        MotoGPRiderRow(standing: standing).dsListCard()
                            .background(
                                standing.position == 1 ? DS.Palette.racingRedFaint : Color.clear,
                                in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }
            case .teams:
                cardScroll(items: teams) { standing in
                    NavigationLink(value: TeamNewsRoute(teamName: standing.team.name, series: .motogp)) {
                        MotoGPTeamRow(standing: standing).dsListCard()
                            .background(
                                standing.position == 1 ? DS.Palette.racingRedFaint : Color.clear,
                                in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }
            case .constructors:
                cardScroll(items: constructors) { standing in
                    NavigationLink(value: TeamNewsRoute(teamName: standing.constructor.name, series: .motogp)) {
                        MotoGPConstructorRow(standing: standing).dsListCard()
                            .background(
                                standing.position == 1 ? DS.Palette.racingRedFaint : Color.clear,
                                in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        case .failed(let message):
            ErrorView(message: message) { Task { await viewModel.load() } }
        }
    }
}

private struct MotoGPRiderRow: View {
    let standing: MotoGPRiderStanding

    var body: some View {
        HStack(spacing: 10) {
            PositionBadge(position: standing.position)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(standing.rider.displayName).font(.subheadline.weight(.medium))
                    if let n = standing.rider.number {
                        Text("#\(n)").font(.caption2.bold()).foregroundStyle(.secondary)
                    }
                }
                Text("\(standing.team.displayName) · \(standing.constructor.displayName)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            PointsBlock(points: standing.points, wins: standing.raceWins)
            FollowToggleButton(
                target: .athlete(id: standing.rider.id, sport: .motorsport, series: "motogp"),
                displayName: standing.rider.fullName
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t(
            zh: "第 \(standing.position) 位 \(standing.rider.displayName) \(standing.team.displayName) \(Int(standing.points)) 分 \(standing.raceWins) 胜",
            en: "P\(standing.position) \(standing.rider.displayName) \(standing.team.displayName) \(Int(standing.points)) pts \(standing.raceWins) wins"
        ))
    }
}

private struct MotoGPTeamRow: View {
    let standing: MotoGPTeamStanding

    var body: some View {
        HStack(spacing: 10) {
            PositionBadge(position: standing.position)
            VStack(alignment: .leading, spacing: 2) {
                Text(standing.team.displayName).font(.subheadline.weight(.medium))
                Text(standing.riderNames.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            PointsBlock(points: standing.points, wins: nil)
            FollowToggleButton(
                target: .team(id: standing.team.id, sport: .motorsport, series: "motogp"),
                displayName: standing.team.name
            )
        }
    }
}

private struct MotoGPConstructorRow: View {
    let standing: MotoGPConstructorStanding

    var body: some View {
        HStack(spacing: 10) {
            PositionBadge(position: standing.position)
            Text(standing.constructor.displayName).font(.subheadline.weight(.medium))
            Spacer()
            PointsBlock(points: standing.points, wins: nil)
            FollowToggleButton(
                target: .team(id: standing.constructor.id, sport: .motorsport, series: "motogp-constructor"),
                displayName: standing.constructor.name
            )
        }
    }
}

// MARK: - WSSP

private enum WSSPTab: String, CaseIterable, Identifiable {
    case riders
    case builders
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .riders:   return L10n.t(zh: "车手", en: "Riders")
        case .builders: return L10n.t(zh: "厂商", en: "Manufacturers")
        }
    }
}

@MainActor
@Observable
fileprivate final class WSSPStandingsViewModel {
    enum State {
        case idle
        case loading
        case loaded(riders: [WSSPRiderStanding], builders: [WSSPBuilderStanding])
        case failed(message: String)
    }

    private(set) var state: State = .idle

    func load() async {
        state = .loading
        let client = WSBKClient.shared
        do {
            // standings 是 throwing,wins 是 non-throwing(内部 swallow 错误)——分开 await
            async let riders = client.fetchSSPRiderStandings()
            async let builders = client.fetchSSPBuilderStandings()
            async let winsMap = client.fetchSSPRiderWins()
            let r = try await riders
            let b = try await builders
            let w = await winsMap
            // wins map key 是大写姓("MASIA" / "BULEGA"),standings name 是 fullname
            // ("JAUME MASIA"),匹配用 last word 大写
            let merged = r.map { row -> WSSPRiderStanding in
                let lastWord = row.rider.fullName.split(separator: " ").last.map { String($0).uppercased() } ?? ""
                return WSSPRiderStanding(
                    position: row.position,
                    points: row.points,
                    wins: w[lastWord] ?? 0,
                    rider: row.rider
                )
            }
            state = .loaded(riders: merged, builders: b)
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }
}

private struct WSSPStandingsContent: View {
    @Bindable var viewModel: WSSPStandingsViewModel
    @State private var tab: WSSPTab = .riders

    var body: some View {
        VStack(spacing: 0) {
            SegmentedPillPicker(selection: $tab, items: WSSPTab.allCases) { t in
                Text(t.displayName)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.xs)

            content
        }
        .task {
            if case .idle = viewModel.state { await viewModel.load() }
        }
        .refreshable { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView(L10n.t(zh: "加载中…", en: "Loading…")).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let riders, let builders):
            switch tab {
            case .riders:
                cardScroll(items: riders) { standing in
                    NavigationLink(value: WSSPRiderDetailRoute(riderName: standing.rider.fullName)) {
                        WSSPRiderRow(standing: standing).dsListCard()
                            .background(
                                standing.position == 1 ? DS.Palette.racingRedFaint : Color.clear,
                                in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }
            case .builders:
                cardScroll(items: builders) { standing in
                    NavigationLink(value: TeamNewsRoute(teamName: standing.builder.name, series: .wssp)) {
                        WSSPBuilderRow(standing: standing).dsListCard()
                            .background(
                                standing.position == 1 ? DS.Palette.racingRedFaint : Color.clear,
                                in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        case .failed(let message):
            ErrorView(message: message) { Task { await viewModel.load() } }
        }
    }
}

private struct WSSPRiderRow: View {
    let standing: WSSPRiderStanding

    var body: some View {
        HStack(spacing: 10) {
            PositionBadge(position: standing.position)
            HStack(spacing: 6) {
                Text(standing.rider.displayName).font(.subheadline.weight(.medium))
            }
            Spacer()
            PointsBlock(points: standing.points, wins: standing.wins)
            FollowToggleButton(
                target: .athlete(id: standing.rider.id, sport: .motorsport, series: "wssp"),
                displayName: standing.rider.fullName
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t(
            zh: "第 \(standing.position) 位 \(standing.rider.displayName) \(Int(standing.points)) 分 \(standing.wins) 胜",
            en: "P\(standing.position) \(standing.rider.displayName) \(Int(standing.points)) pts \(standing.wins) wins"
        ))
    }
}

private struct WSSPBuilderRow: View {
    let standing: WSSPBuilderStanding

    var body: some View {
        HStack(spacing: 10) {
            PositionBadge(position: standing.position)
            HStack(spacing: 6) {
                Text(standing.builder.displayName).font(.subheadline.weight(.medium))
            }
            Spacer()
            PointsBlock(points: standing.points, wins: nil)
            FollowToggleButton(
                target: .team(id: standing.builder.id, sport: .motorsport, series: "wssp-builder"),
                displayName: standing.builder.name
            )
        }
    }
}

// MARK: - Formula E

private enum FETab: String, CaseIterable, Identifiable {
    case drivers
    case teams
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .drivers: return L10n.t(zh: "车手", en: "Drivers")
        case .teams:   return L10n.t(zh: "车队", en: "Teams")
        }
    }
}

@MainActor
@Observable
fileprivate final class FEStandingsViewModel {
    enum State {
        case idle
        case loading
        case loaded(drivers: [FEDriverStanding], teams: [FEConstructorStanding])
        case failed(message: String)
    }
    private(set) var state: State = .idle

    func load() async {
        state = .loading
        do {
            async let drivers = FormulaEClient.shared.fetchDriverStandings()
            async let teams = FormulaEClient.shared.fetchConstructorStandings()
            let (d, t) = try await (drivers, teams)
            state = .loaded(drivers: d, teams: t)
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }
}

private struct FEStandingsContent: View {
    @Bindable var viewModel: FEStandingsViewModel
    @State private var tab: FETab = .drivers

    var body: some View {
        VStack(spacing: 0) {
            SegmentedPillPicker(selection: $tab, items: FETab.allCases) { t in
                Text(t.displayName)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.xs)

            content
        }
        .tint(MotorsportSeries.fe.brandColor)
        .task {
            if case .idle = viewModel.state { await viewModel.load() }
        }
        .refreshable { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView(L10n.t(zh: "加载中…", en: "Loading…")).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let drivers, let teams):
            switch tab {
            case .drivers:
                cardScroll(items: drivers) { standing in
                    NavigationLink(value: standing) {
                        FEDriverRow(standing: standing).dsListCard()
                            .background(
                                standing.position == 1 ? DS.Palette.racingRedFaint : Color.clear,
                                in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }
            case .teams:
                cardScroll(items: teams) { standing in
                    NavigationLink(value: TeamNewsRoute(teamName: standing.team.name, series: .fe)) {
                        FETeamRow(standing: standing).dsListCard()
                            .background(
                                standing.position == 1 ? DS.Palette.racingRedFaint : Color.clear,
                                in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        case .failed(let message):
            ErrorView(message: message) { Task { await viewModel.load() } }
        }
    }
}

private struct FEDriverRow: View {
    let standing: FEDriverStanding

    var body: some View {
        HStack(spacing: 10) {
            PositionBadge(position: standing.position)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(standing.driver.displayName).font(.subheadline.weight(.medium))
                    if let tla = standing.driver.tla {
                        Text(tla).font(.caption2.bold()).foregroundStyle(.secondary)
                    }
                }
                Text(MotorsportNames.teamName(raw: standing.teamName, series: .fe))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            PointsBlock(points: standing.points, wins: nil)
            FollowToggleButton(
                target: .athlete(id: standing.driver.id, sport: .motorsport, series: "fe"),
                displayName: standing.driver.fullName
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t(
            zh: "第 \(standing.position) 位 \(standing.driver.displayName) \(MotorsportNames.teamName(raw: standing.teamName, series: .fe)) \(Int(standing.points)) 分",
            en: "P\(standing.position) \(standing.driver.displayName) \(MotorsportNames.teamName(raw: standing.teamName, series: .fe)) \(Int(standing.points)) pts"
        ))
    }
}

private struct FETeamRow: View {
    let standing: FEConstructorStanding

    var body: some View {
        HStack(spacing: 10) {
            PositionBadge(position: standing.position)
            Text(standing.team.displayName).font(.subheadline.weight(.medium))
            Spacer()
            PointsBlock(points: standing.points, wins: nil)
        }
    }
}

// MARK: - Shared subviews

private struct PositionBadge: View {
    let position: Int
    var body: some View {
        Text("P\(position)")
            .font(DS.Font.numberMid.weight(.heavy))
            .foregroundStyle(position == 1 ? DS.Palette.racingRed : (position <= 3 ? .primary : .secondary))
            .frame(width: 38, alignment: .leading)
    }
}

private struct PointsBlock: View {
    let points: Double
    let wins: Int?

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("\(points, format: .number)")
                .font(DS.Font.numberMid)
                .monospacedDigit()
            Text(L10n.t(zh: "分", en: "pts"))
                .font(DS.Font.toolLabel)
                .foregroundStyle(.secondary)
            if let w = wins, w > 0 {
                Text("\(w) \(L10n.t(zh: "胜", en: "wins"))").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        // 固定 trailing 宽度,避免"150 分"比"89 分"宽 / 含"X 胜"行高不一致
        // 导致积分榜各 row 右侧 follow 按钮位置参差
        .frame(minWidth: 70, alignment: .trailing)
    }
}

// MARK: - 共享 helper

/// 把一个 List 替换成 ScrollView+LazyVStack 卡片流(豆包/元宝积分榜典型布局)。
@ViewBuilder
fileprivate func cardScroll<Item: Identifiable, Content: View>(
    items: [Item],
    @ViewBuilder content: @escaping (Item) -> Content
) -> some View {
    ScrollView {
        LazyVStack(spacing: DS.Spacing.sm) {
            ForEach(items) { item in
                content(item)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        .animation(DS.Motion.bubbleEntry, value: items.count)
    }
}

