import SwiftUI

@MainActor
@Observable
final class FESessionResultsViewModel {
    enum State {
        case idle
        case loading
        case loaded(rows: [FESessionResult])
        case failed(message: String)
    }

    let ref: FESessionRef
    private(set) var state: State = .idle

    init(ref: FESessionRef) { self.ref = ref }

    func loadIfNeeded() async {
        guard case .idle = state else { return }
        state = .loading
        do {
            let rows = try await FormulaEClient.shared.fetchSessionResults(
                raceId: ref.round.id,
                sessionId: ref.session.id
            )
            state = .loaded(rows: rows)
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }
}

struct FESessionResultsView: View {
    @State private var viewModel: FESessionResultsViewModel

    init(ref: FESessionRef) {
        _viewModel = State(initialValue: FESessionResultsViewModel(ref: ref))
    }

    var body: some View {
        content
            .navigationTitle(viewModel.ref.session.localizedDisplayName)
            .navigationBarTitleDisplayMode(.inline)
            .tint(MotorsportSeries.fe.brandColor)
            .task { await viewModel.loadIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView(L10n.t(zh: "加载结果…", en: "Loading results…"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let rows):
            if rows.isEmpty {
                ContentUnavailableView(L10n.t(zh: "暂无结果", en: "No Results"), systemImage: "list.bullet.rectangle")
            } else {
                List(rows) { row in
                    ResultRow(row: row, isRace: viewModel.ref.session.kind == .race)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color(.systemBackground))
            }
        case .failed(let message):
            ErrorView(message: message) { Task { await viewModel.loadIfNeeded() } }
        }
    }
}

private struct ResultRow: View {
    let row: FESessionResult
    let isRace: Bool

    var body: some View {
        HStack(spacing: 10) {
            positionBadge
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.displayName).font(.subheadline.weight(.medium))
                    if let n = row.driverNumber {
                        Text("#\(n)").font(.caption2.bold()).foregroundStyle(.secondary)
                    }
                    if let tla = row.driverTLA {
                        Text(tla).font(.caption2.bold()).foregroundStyle(.tertiary)
                    }
                }
                Text(row.displayTeamName)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(timingText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(timingColor)
                if isRace, row.points > 0 {
                    Text("+\(Int(row.points)) \(L10n.t(zh: "分", en: "pts"))")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                if !row.statusFlags.isEmpty {
                    Text(row.statusFlags)
                        .font(.caption2.bold())
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var positionBadge: some View {
        Group {
            if let pos = row.driverPosition {
                Text("\(pos)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(pos <= 3 ? .primary : .secondary)
            } else {
                Text("—")
                    .font(.headline)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 28, alignment: .center)
    }

    /// 领跑显示总时间;其他车显示 +gap;非完赛显示 status flags。
    private var timingText: String {
        if let delay = row.delayText, delay != "-" { return delay }
        if let t = row.sessionTimeText, !t.isEmpty { return t }
        if let b = row.bestTimeText, !b.isEmpty { return b }
        return "—"
    }

    private var timingColor: Color {
        if row.dnf || row.dnq || row.dns || row.dsq || row.exc { return .orange }
        return .primary
    }
}
