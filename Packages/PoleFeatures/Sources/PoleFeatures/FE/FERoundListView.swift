import SwiftUI
import PoleDomain
import PoleDesignSystem
import PoleMotorsportKit
import PoleUI

@MainActor
@Observable
public final class FERoundListViewModel {
    enum State {
        case idle
        case loading
        case loaded(routes: [FERoute])
        case failed(message: String)
    }

    private(set) var state: State = .idle

    func load() async {
        state = .loading
        do {
            let rounds = try await FormulaEClient.shared.fetchSeasonRounds()
            let routes = Self.groupByWeekend(rounds)
            state = .loaded(routes: routes)
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }

    /// 按赛道把连续的同赛道 round 合并为 FEWeekend（双回合）。
    private static func groupByWeekend(_ rounds: [FERound]) -> [FERoute] {
        var routes: [FERoute] = []
        var buffer: [FERound] = []
        for round in rounds {
            if let last = buffer.last, last.circuit.name != round.circuit.name {
                routes.append(buffer.count > 1 ? .weekend(FEWeekend(rounds: buffer)) : .single(buffer[0]))
                buffer = []
            }
            buffer.append(round)
        }
        if let last = buffer.last {
            routes.append(buffer.count > 1 ? .weekend(FEWeekend(rounds: buffer)) : .single(last))
        }
        return routes
    }
}

/// FE 赛历列表 —— 双回合赛事合并为一张卡片，点进去可切换。
public struct FERoundListView: View {
    @State private var viewModel = FERoundListViewModel()

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle(L10n.t(zh: "Formula E 赛程", en: "Formula E Schedule"))
                #if canImport(UIKit)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar(.hidden, for: .navigationBar)
                .tint(MotorsportSeries.fe.brandColor)
                .navigationDestination(for: FERoute.self) { FERoundDetailView(route: $0) }
                .navigationDestination(for: FESessionRef.self) { FESessionResultsView(ref: $0) }
                .task {
                    if case .idle = viewModel.state { await viewModel.load() }
                }
                .refreshable { await viewModel.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView(L10n.t(zh: "加载中…", en: "Loading…")).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let routes):
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(routes) { route in
                        NavigationLink(value: route) {
                            switch route {
                            case .single(let round):
                                singleCard(round)
                            case .weekend(let weekend):
                                weekendCard(weekend)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        case .failed(let message):
            ErrorView(message: message) { Task { await viewModel.load() } }
        }
    }

    private func singleCard(_ round: FERound) -> some View {
        MotorsportCard(series: .fe, isLive: round.currentStatus == .live) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("FE")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(MotorsportSeries.fe.brandColor)
                    Text("·").foregroundStyle(.tertiary)
                    Text(round.raceDate, format: .dateTime.month(.abbreviated).day().beijing())
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Text(round.headline)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                Text(round.subheadline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } trailing: {
            StatusBadge(status: round.currentStatus)
        }
    }

    private func weekendCard(_ weekend: FEWeekend) -> some View {
        let isLive = weekend.rounds.contains { $0.currentStatus == .live }
        let representative = weekend.rounds.first!
        return MotorsportCard(series: .fe, isLive: isLive) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("FE")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(MotorsportSeries.fe.brandColor)
                    Text("·").foregroundStyle(.tertiary)
                    Text(weekend.dateRangeText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text("2R")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(MotorsportSeries.fe.brandColor)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(MotorsportSeries.fe.brandColor.opacity(0.12), in: .capsule)
                }
                Text(weekend.headline)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                Text(weekend.subheadline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } trailing: {
            StatusBadge(status: representative.currentStatus)
        }
    }
}
