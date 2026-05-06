import WidgetKit
import SwiftUI
import ActivityKit

/// Widget extension 内简化版本地化。主 app 的 `L10n.t(zh:en:)` 在 Pole target,
/// 让其双勾给 widget 也行,但 SETUP 复杂;widget 这一处用法少,直接 file-private 实现更轻。
fileprivate func widgetL10n(zh: String, en: String) -> String {
    Locale.current.language.languageCode?.identifier == "zh" ? zh : en
}

/// 赛事 Live Activity widget — 同时渲染锁屏卡片 + iPhone 14 Pro+ 灵动岛三种形态。
struct RaceLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RaceLiveActivityAttributes.self) { context in
            // -------------- 锁屏 / 通知中心(全屏卡片) ---------------
            LockScreenView(
                attributes: context.attributes,
                state: context.state
            )
            // 按当前赛事 series 动态品牌 tint(F1 红 / MotoGP 橙 / WSSP 绿 / FE 青)。
            // 老版本残留紫色 #7C4DFF 是历史 ai-purple,Pole 已统一 F1 红为主品牌。
            .activityBackgroundTint(seriesColor(context.attributes.seriesRaw).opacity(0.15))
            .activitySystemActionForegroundColor(Color.primary)

        } dynamicIsland: { context in
            // -------------- 灵动岛 ---------------
            DynamicIsland {
                // ---- expanded(长按展开) ----
                DynamicIslandExpandedRegion(.leading) {
                    LeadingExpanded(state: context.state, attributes: context.attributes)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TrailingExpanded(state: context.state, attributes: context.attributes)
                }
                DynamicIslandExpandedRegion(.center) {
                    CenterExpanded(state: context.state, attributes: context.attributes)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    BottomExpanded(state: context.state, attributes: context.attributes)
                }
            } compactLeading: {
                // ---- compact 左侧(常驻态) ----
                Image(systemName: seriesIcon(context.attributes.seriesRaw))
                    .foregroundStyle(seriesColor(context.attributes.seriesRaw))
            } compactTrailing: {
                // ---- compact 右侧 ----
                CompactTrailingView(state: context.state, attributes: context.attributes)
            } minimal: {
                // ---- minimal(被其他 activity 挤到圆点态) ----
                Image(systemName: seriesIcon(context.attributes.seriesRaw))
                    .foregroundStyle(seriesColor(context.attributes.seriesRaw))
            }
            // 灵动岛点击范围 deep-link 走 widgetURL
            .widgetURL(URL(string: "pole://race/\(context.attributes.raceId)"))
            .keylineTint(seriesColor(context.attributes.seriesRaw))
        }
    }
}

// MARK: - 锁屏视图

private struct LockScreenView: View {
    let attributes: RaceLiveActivityAttributes
    let state: RaceLiveActivityAttributes.ContentState

    /// VoiceOver:整张锁屏卡合成一句,不再逐个 Text 朗读 6+ 次。
    private var a11yLabel: String {
        let phase: String
        switch state.phase {
        case .beforeWeekend:    phase = widgetL10n(zh: "未开始", en: "Not started")
        case .inSession:        phase = state.currentSessionLabel ?? widgetL10n(zh: "进行中", en: "In progress")
        case .betweenSessions:  phase = widgetL10n(zh: "间歇", en: "Between sessions")
        case .finished:         phase = widgetL10n(zh: "已结束", en: "Finished")
        }
        return "\(attributes.raceTitle), \(attributes.raceSubtitle), \(phase)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: seriesIcon(attributes.seriesRaw))
                    .foregroundStyle(seriesColor(attributes.seriesRaw))
                    .font(.headline)
                Text(attributes.raceTitle)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                phaseBadge
            }
            Text(attributes.raceSubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            // 进度条 — 用赛事整周末时间窗推算
            if let s = state.currentSessionStart, let e = state.currentSessionEnd {
                ProgressView(timerInterval: s...e, countsDown: false)
                    .tint(seriesColor(attributes.seriesRaw))
                    .progressViewStyle(.linear)
            }

            // top 3
            if !state.lastSessionTop3.isEmpty {
                HStack(spacing: 6) {
                    Text(state.lastSessionLabel ?? widgetL10n(zh: "上一 session", en: "Last session"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(state.lastSessionTop3.prefix(3).joined(separator: " · "))
                        .font(.caption2)
                        .lineLimit(1)
                }
            }
        }
        .padding(12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11yLabel)
    }

    @ViewBuilder
    private var phaseBadge: some View {
        let label: String = {
            switch state.phase {
            case .beforeWeekend:    return widgetL10n(zh: "未开始", en: "Not started")
            case .inSession:        return state.currentSessionLabel ?? widgetL10n(zh: "进行中", en: "In progress")
            case .betweenSessions:  return widgetL10n(zh: "间歇", en: "Between sessions")
            case .finished:         return widgetL10n(zh: "已结束", en: "Finished")
            }
        }()
        let color: Color = {
            switch state.phase {
            case .inSession: return .red
            case .beforeWeekend: return .blue
            case .betweenSessions: return .orange
            case .finished: return .gray
            }
        }()
        Text(label)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.20), in: Capsule())
            .foregroundStyle(color)
    }
}

// MARK: - Dynamic Island expanded 区域

private struct LeadingExpanded: View {
    let state: RaceLiveActivityAttributes.ContentState
    let attributes: RaceLiveActivityAttributes
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: seriesIcon(attributes.seriesRaw))
                .foregroundStyle(seriesColor(attributes.seriesRaw))
                .font(.title3)
            Text(attributes.raceTitle)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
    }
}

private struct TrailingExpanded: View {
    let state: RaceLiveActivityAttributes.ContentState
    let attributes: RaceLiveActivityAttributes
    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(state.currentSessionLabel ?? "—")
                .font(.caption2.weight(.bold))
                .foregroundStyle(seriesColor(attributes.seriesRaw))
            if let s = state.currentSessionStart, let e = state.currentSessionEnd {
                Text(timerInterval: s...e, countsDown: false)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CenterExpanded: View {
    let state: RaceLiveActivityAttributes.ContentState
    let attributes: RaceLiveActivityAttributes
    var body: some View {
        if let s = state.currentSessionStart, let e = state.currentSessionEnd {
            ProgressView(timerInterval: s...e, countsDown: false)
                .tint(seriesColor(attributes.seriesRaw))
                .progressViewStyle(.linear)
                .padding(.horizontal, 8)
        }
    }
}

private struct BottomExpanded: View {
    let state: RaceLiveActivityAttributes.ContentState
    let attributes: RaceLiveActivityAttributes
    var body: some View {
        HStack(spacing: 8) {
            if !state.lastSessionTop3.isEmpty {
                Text(state.lastSessionTop3.prefix(3).joined(separator: " · "))
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            } else {
                Text(attributes.raceSubtitle)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            // 灵动岛上的"停止"按钮 — Button(intent:) iOS 17+
            Button(intent: StopLiveActivityIntent()) {
                Image(systemName: "stop.circle")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - compact trailing(常驻态右侧)

private struct CompactTrailingView: View {
    let state: RaceLiveActivityAttributes.ContentState
    let attributes: RaceLiveActivityAttributes
    var body: some View {
        if let s = state.currentSessionStart, let e = state.currentSessionEnd {
            // 当前 session 倒计时
            Text(timerInterval: s...e, countsDown: state.phase == .beforeWeekend)
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(seriesColor(attributes.seriesRaw))
        } else {
            Text(state.currentSessionLabel ?? "—")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(seriesColor(attributes.seriesRaw))
        }
    }
}

// MARK: - 共享 helper(seriesRaw → 颜色 / icon)

private func seriesColor(_ raw: String) -> Color {
    switch raw {
    case "f1":     return Color(red: 0.882, green: 0.024, blue: 0.000)
    case "motogp": return Color(red: 1.000, green: 0.420, blue: 0.000)
    case "wssp":   return Color(red: 0.000, green: 0.624, blue: 0.302)
    case "fe":     return Color(red: 0.000, green: 0.784, blue: 0.769)
    default:       return .accentColor
    }
}

private func seriesIcon(_ raw: String) -> String {
    "flag.checkered"   // 全系列共用,简洁
}
