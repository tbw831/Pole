import SwiftUI
import Combine   // Timer.publish(...).autoconnect() — SwiftUI 不再自动 re-export Combine
import PoleDesignSystem
import PoleDomain

// MARK: - 工具组卡片(运行进度 + 失败重试)
//
// 业界最佳实践对照(Claude / ChatGPT / Cursor / Perplexity):
// 1. 每个 tool 专属 SF Symbol,不再用通用 wrench
// 2. 完成后小字"0.8s"耗时显示
// 3. running 行 shimmer 光带扫过 + 呼吸圆点
// 4. failed step 内联"重试"按钮
// 5. running 时动态进度文案("查找 F1 西班牙站..."),done 时切回 preview
// 6. Staggered 入场:多步同时出现按 index 错开 80ms 渐入
// 7. running 时 header 右上"停止"按钮 + 总用时秒数
// 8. 触觉反馈在 ChatViewModel.handleEvent 触发(开始 soft / 完成 light / 失败 warning)

public struct ToolGroupView: View {
    let steps: [ChatView.RenderItem.ToolStep]
    /// 是否流式中 — 自动展开看进度。
    let autoExpand: Bool
    /// 用户点 header "停止" — running 时才传(传 nil 不显示按钮)。
    let onCancel: (() -> Void)?
    /// 用户点 failed step "重试" — 传 stepId(传 nil 不显示按钮)。
    let onRetry: ((UUID) -> Void)?

    @State private var isExpanded: Bool = false
    /// 跟踪 view 出现以来经过的 wall-clock 时间,driving header 的"运行总秒数"显示。
    /// running 状态下每秒 tick 一次,non-running 时不订阅 timer。
    @State private var nowTick: Date = .now

    /// running 期 timer — 每秒 emit 一次,driving 计时显示。
    private let runningTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    public var body: some View {
        let expanded = isExpanded || autoExpand
        let hasRunning = steps.contains(where: { $0.status == .running })

        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            // 摘要头
            Button {
                withAnimation(DS.Motion.layout) { isExpanded.toggle() }
            } label: {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: headerIcon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DS.Palette.primary)
                        .frame(width: 14, alignment: .center)
                    Text(summaryText)
                        .font(DS.Font.toolLabel)
                        .foregroundStyle(.primary)
                    // running 时显示总用时秒数,豆包/Cursor 同款
                    if hasRunning {
                        Text(String(format: "%.0fs", elapsedSeconds))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: DS.Spacing.sm)
                    headerStatus
                    // 取消按钮 — 仅 running 时显示
                    if hasRunning, let onCancel {
                        Button {
                            onCancel()
                        } label: {
                            Image(systemName: "stop.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.red.opacity(0.85))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.t(zh: "停止", en: "Stop"))
                    }
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .animation(DS.Motion.layout, value: expanded)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(autoExpand)   // 流式期间不让用户折叠,看进度

            // 展开内容
            if expanded {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { idx, step in
                        toolStepRow(step, index: idx)
                            // Staggered 入场 — 每步比上一步晚 80ms 出现
                            .transition(.asymmetric(
                                insertion: .opacity
                                    .combined(with: .move(edge: .top))
                                    .animation(.easeOut(duration: 0.25).delay(Double(idx) * 0.08)),
                                removal: .opacity.animation(.easeIn(duration: 0.15))
                            ))
                    }
                }
                .padding(.top, DS.Spacing.xxs)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm + 2)
        .dsToolCard()
        .padding(.horizontal, DS.Spacing.lg)
        // running 期订阅 timer 让 elapsedSeconds reactive 重算;non-running 不订阅省电。
        .onReceive(runningTimer) { now in
            if hasRunning { nowTick = now }
        }
    }

    // MARK: - Header

    /// "工具调用 · 3 步" / 单步时显示步骤的 humanLabel
    private var summaryText: String {
        if steps.count == 1, let only = steps.first {
            return ToolMetadata.humanLabel(for: only.name)
        }
        let running = steps.contains(where: { $0.status == .running })
        if running {
            // 多步运行时显示"步骤 N/M"
            let doneCount = steps.filter { $0.status != .running }.count
            return L10n.t(
                zh: "工具调用 · \(doneCount + 1)/\(steps.count) 步",
                en: "Tools · step \(doneCount + 1)/\(steps.count)"
            )
        }
        return L10n.t(zh: "工具调用 · \(steps.count) 步", en: "Tool calls · \(steps.count) steps")
    }

    /// header 左侧图标 — 单步时用该 tool 的专属图标,多步时用通用 sparkles。
    private var headerIcon: String {
        if steps.count == 1, let only = steps.first {
            return ToolMetadata.iconName(for: only.name)
        }
        return "wand.and.stars"
    }

    /// 第一个 running step 开始到现在的秒数 — 用于 header 计时显示。
    /// 这里看 nowTick 让 SwiftUI 重新计算,timer 每秒触发 nowTick = .now。
    private var elapsedSeconds: TimeInterval {
        guard let first = steps.first(where: { $0.status == .running }) else { return 0 }
        return max(0, nowTick.timeIntervalSince(first.startedAt))
    }

    @ViewBuilder
    private var headerStatus: some View {
        let running = steps.contains(where: { $0.status == .running })
        let failed  = steps.contains(where: { $0.status == .failed })
        if running {
            BreathingDot(color: DS.Palette.primary, size: 9)
        } else if failed {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red).font(.caption)
        } else {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.caption)
        }
    }

    // MARK: - Step row

    @ViewBuilder
    private func toolStepRow(_ step: ChatView.RenderItem.ToolStep, index: Int) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            // 时间线:状态点 + 竖线
            VStack(spacing: 0) {
                statusDot(step.status)
                if index < steps.count - 1 {
                    Rectangle()
                        .fill(DS.Palette.primary.opacity(0.20))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 14)

            // 内容:工具图标 + label + 副文案 + 耗时 + 重试按钮
            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                Image(systemName: ToolMetadata.iconName(for: step.name))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(stepIconColor(step.status))
                    .frame(width: 14, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(ToolMetadata.humanLabel(for: step.name))
                            .font(DS.Font.toolLabel)
                            .foregroundStyle(step.status == .failed ? .secondary : .primary)
                        // done/failed 显示耗时
                        if let dur = step.duration {
                            Text(formatDuration(dur))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    }
                    // 副文案:running 时是 hint,done 时是 preview;两者都没有就不显示
                    if let sub = subText(for: step), !sub.isEmpty {
                        Text(sub)
                            .font(DS.Font.toolPreview)
                            // 三元表达式两边必须同类型 — `.orange` 是 Color,`.tertiary` 是
                            // HierarchicalShapeStyle,Swift 推不出统一类型。用 AnyShapeStyle 包一层。
                            .foregroundStyle(
                                step.status == .failed
                                    ? AnyShapeStyle(Color.orange)
                                    : AnyShapeStyle(HierarchicalShapeStyle.tertiary)
                            )
                            .lineLimit(2)
                            .transition(.opacity)
                    }
                }
                Spacer()
                // failed step 提供重试入口
                if step.status == .failed, let onRetry {
                    Button {
                        onRetry(step.id)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption2.weight(.bold))
                            Text(L10n.t(zh: "重试", en: "Retry"))
                                .font(.caption2.weight(.semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(DS.Palette.primaryFaint, in: Capsule())
                        .foregroundStyle(DS.Palette.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            // running 行加 shimmer — 给"工作中"很强的视觉信号
            .dsShimmer(active: step.status == .running)
        }
        .padding(.vertical, 2)
    }

    /// running 时优先显示 hint 进度文案,其它状态退回 preview。
    private func subText(for step: ChatView.RenderItem.ToolStep) -> String? {
        switch step.status {
        case .running: return step.runningHint ?? step.preview
        case .done, .failed: return step.preview
        }
    }

    /// 1.234s → "1.2s" / 0.234s → "234ms" — 比纯秒数清晰。
    private func formatDuration(_ d: TimeInterval) -> String {
        if d < 1.0 {
            return String(format: "%.0fms", d * 1000)
        }
        return String(format: "%.1fs", d)
    }

    /// step 图标颜色随状态变化 — done = primary 蓝,running = primary 蓝,failed = orange 警示
    private func stepIconColor(_ status: ChatViewModel.Bubble.ToolStatus) -> Color {
        switch status {
        case .running, .done: return DS.Palette.primary
        case .failed:         return .orange
        }
    }

    @ViewBuilder
    private func statusDot(_ status: ChatViewModel.Bubble.ToolStatus) -> some View {
        switch status {
        case .running:
            // 呼吸圆点(replace ProgressView,克制 + 不抢戏)
            BreathingDot(color: DS.Palette.primary, size: 10)
        case .done:
            Circle().fill(.green).frame(width: 8, height: 8)
        case .failed:
            Circle().fill(.red).frame(width: 8, height: 8)
        }
    }
}

// MARK: - Tool 元数据(图标 + 显示名集中)
//
// 单点维护:加新 tool 时只动这一处。
// 默认值用通用 wrench + raw name,保证 LLM 突然用了未注册 tool 也不会渲染异常。

public enum ToolMetadata {
    /// 每个 tool 专属 SF Symbol — 视觉识别度大幅提升
    static func iconName(for toolName: String) -> String {
        switch toolName {
        case "find_round":          return "magnifyingglass"
        case "get_session_results": return "flag.checkered"
        case "get_standings":       return "list.number"
        case "get_driver_history":  return "person.text.rectangle.fill"
        case "add_to_calendar":     return "calendar.badge.plus"
        case "list_followed":       return "bookmark.fill"
        default:                    return "wrench.and.screwdriver"
        }
    }

    /// 用户可读名(L10n) — 跟原来 humanLabel 一致
    static func humanLabel(for toolName: String) -> String {
        switch toolName {
        case "find_round":          return L10n.t(zh: "查找赛事", en: "Find Race")
        case "get_session_results": return L10n.t(zh: "查询比赛结果", en: "Get Results")
        case "get_standings":       return L10n.t(zh: "查询积分榜", en: "Get Standings")
        case "get_driver_history":  return L10n.t(zh: "查询车手生涯", en: "Driver Career")
        case "add_to_calendar":     return L10n.t(zh: "加入日历", en: "Add to Calendar")
        case "list_followed":       return L10n.t(zh: "读取关注列表", en: "List Followed")
        default:                    return toolName
        }
    }
}
