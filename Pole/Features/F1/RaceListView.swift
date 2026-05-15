import SwiftUI
import PoleDomain
import PoleDesignSystem

// MARK: - ViewModel

@MainActor
@Observable
final class RaceListViewModel {
    enum State {
        case idle
        case loading
        case loaded(races: [F1Race])
        case failed(message: String)
    }

    private(set) var state: State = .idle

    func load() async {
        state = .loading
        do {
            let races = try await JolpicaClient.shared.fetchSeasonRaces()
            // live 排第一,其余按 weekendStart 升序——保证正在进行的赛事最显眼
            let sorted = races.sorted { a, b in
                let aLive = a.currentStatus == .live
                let bLive = b.currentStatus == .live
                if aLive != bLive { return aLive }
                return a.weekendStart < b.weekendStart
            }
            state = .loaded(races: sorted)
            await NotificationScheduler.shared.reschedule(for: races)
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }
}

// MARK: - View

struct RaceListView: View {
    @State private var viewModel = RaceListViewModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(L10n.t(zh: "F1 赛程", en: "F1 Schedule"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.hidden, for: .navigationBar)
                .task {
                    if case .idle = viewModel.state {
                        await viewModel.load()
                    }
                }
                .refreshable { await viewModel.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView(L10n.t(zh: "加载中…", en: "Loading…"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loaded(let races):
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(races) { race in
                        NavigationLink(value: race) {
                            RaceRow(race: race)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .navigationDestination(for: F1Race.self) { race in
                RaceDetailView(race: race)
            }
            .navigationDestination(for: F1SessionResultsRef.self) { ref in
                F1SessionResultsView(ref: ref)
            }

        case .failed(let message):
            ErrorView(message: message) { Task { await viewModel.load() } }
        }
    }
}

// MARK: - Row

private struct RaceRow: View {
    let race: F1Race

    var body: some View {
        MotorsportCard(series: .f1, isLive: race.currentStatus == .live) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(MotorsportSeries.f1.shortName)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(MotorsportSeries.f1.brandColor)
                    Text("·").foregroundStyle(.tertiary)
                    Text(weekendDateRange)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Text(race.headline)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                Text(race.subheadline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } trailing: {
            StatusBadge(status: race.currentStatus)
        }
    }

    private var weekendDateRange: String {
        let s = race.weekendStart.formatted(.dateTime.month(.abbreviated).day().beijing())
        let e = race.weekendEnd.formatted(.dateTime.month(.abbreviated).day().beijing())
        return "\(s) – \(e)"
    }
}

// MARK: - Preview

#Preview {
    RaceListView()
}
