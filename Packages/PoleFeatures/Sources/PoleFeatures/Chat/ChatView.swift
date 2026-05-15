import SwiftUI
import SwiftData
// Timer.publish(...).autoconnect() 来自 Combine — SwiftUI 不再自动 re-export Combine,
// chatList 用 .onReceive 订阅 timer 计时必须显式 import。
import Combine
import PoleDesignSystem
import PoleDomain
import PoleAIKit
import PoleSpeechKit

/// AI 助手主屏 —— 顶层路由 view。
///
/// **拆分后**:此文件只剩"top-level scaffold":
/// - NavigationStack + Toolbar + Sheet
/// - starterView(空会话 → prompt 推荐 + 今日冷知识)
/// - chatList(有消息时 LazyVStack 列表)
/// - inputBar(转发到 `ChatComposerView`)
///
/// 视觉细节分别在:
/// - `ChatBubbleView` — 用户 / AI 气泡 + markdown 解析(代码块 / 表格)
/// - `ChatToolCallView` — 工具调用组卡片 + tool metadata
/// - `ChatComposerView` — 底部输入区 + 语音输入条
///
/// ChatView.RenderItem 仍在这里(被 ViewModel.renderedItems / ChatBubbleView / ChatToolCallView 共享)。
public struct ChatView: View {
    public init() {}
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: ChatViewModel?
    @State private var showHistory = false
    @State private var displayedPrompts: [String] = []
    @State private var isRefreshingPrompts = false
    @State private var promptTapCounter: Int = 0
    @State private var sendCounter: Int = 0
    /// 语音输入服务(单例,跨 view 共享 listening 状态)。
    @State private var speech = SpeechService.shared

    /// Prompt 三组分类(豆包/元宝典型 starter):热门通用 / 本周末赛事 / 跟关注挂钩。
    /// 合并 prompt pool — 把热门 / 本周末 / 关注三池整合成一个列表,starter 抽 5 条显示。
    /// 老版本有 segmented picker 切换三池,产品决策改成单一列表(切换体验复杂)。
    /// 关注的 prompt 优先放前面(用户最关心),其次热门,再次本周末。重复的去重。
    private var mergedPromptPool: [String] {
        let hot = L10n.effective == .en ? Self.poolHotEN : Self.poolHotZH
        let weekend = L10n.effective == .en ? Self.poolWeekendEN : Self.poolWeekendZH
        let followed = followedPrompts()
        let merged = followed + hot + weekend
        var seen = Set<String>()
        return merged.filter { seen.insert($0).inserted }
    }

    /// 基于关注列表生成 prompt;无关注时返空数组(不再硬塞"先去关注"引导文案)。
    /// Prompt 用"故事性 / 悬念"措辞,直接点关注对象的当下处境,引诱用户点击。
    /// 带 series 前缀(F1/MotoGP/WSBK/FE),让 LLM 一眼知道在问哪个系列,不用反复 disambiguate。
    /// 中文不在前缀和正文之间加空格(中英文混排习惯,跟 pool 里的 prompts 保持一致)。
    private func followedPrompts() -> [String] {
        let items = FollowStore(context: modelContext).all().prefix(3)
        return items.flatMap { item -> [String] in
            let name = item.localizedDisplayName
            let prefix = Self.seriesPrefix(seriesRaw: item.seriesRaw)
            if L10n.effective == .en {
                if item.kindRaw == "athlete" {
                    return ["\(prefix): \(name) — title hopes?"]
                } else {
                    return ["\(prefix): What's up at \(name)?"]
                }
            } else {
                if item.kindRaw == "athlete" {
                    return ["\(prefix)\(name)还有戏吗?"]
                } else {
                    return ["\(prefix)\(name)最近怎样?"]
                }
            }
        }
    }

    /// 系列 raw → 显示前缀("f1" → "F1","wssp" → "WSBK" 等)。
    /// 跟 MotorsportSeries.shortName 保持一致(WSSP class 但显示 WSBK 品牌名),
    /// fallback 到原始 raw 大写。
    private static func seriesPrefix(seriesRaw: String) -> String {
        switch seriesRaw.lowercased() {
        case "f1":     return "F1"
        case "motogp": return "MotoGP"
        case "wssp":   return "WSBK"   // 显示用品牌名 WSBK,LLM 系统 prompt 已知 WSBK = wssp class
        case "fe":     return "FE"
        default:       return seriesRaw.uppercased()
        }
    }

    /// 系列前缀检测顺序 — 长 prefix 先匹配避免歧义(FE 不会跟 F1 撞,但保险起见 longest first)。
    /// 用于 refreshPromptsLocal 抽样时按系列分类。
    private static let seriesPrefixes = ["MotoGP", "WSBK", "F1", "FE"]

    /// 给 prompt 找它属于的系列(F1/MotoGP/WSBK/FE),没有前缀返 nil(跨系列 prompt)。
    /// 中英文都用 hasPrefix 匹配 — 中文是 "F1维斯塔潘",英文是 "F1: Can ..." 两者都能命中。
    private static func seriesFor(_ prompt: String) -> String? {
        seriesPrefixes.first(where: { prompt.hasPrefix($0) })
    }

    // 中文 / 英文 各两组(热门 / 本周末)
    // Prompt 设计原则:**短、punchy、有亮点、有针对性**。
    // - 每条 ≤ 12 个汉字 / 28 个英文字符,避免 chip 截断
    // - 重故事性 / 悬念 / 反差,而不是平铺直叙的"XX 积分榜"
    // - 让用户产生好奇 → 点击,而不是把它当查询入口
    //
    // **系列前缀必填**(F1 / MotoGP / WSBK / FE):用户报告"sug 都没说是什么比赛",
    // LLM 要靠用户问题猜 series 容易错。带前缀后 LLM 直接知道调哪个系列的工具,
    // 减少消歧成本 + 让推荐看上去更专业。少数跨系列问题(如"本周末值得看哪场")才不带前缀。
    //
    // **中文不加空格**(F1+中文紧贴):中英混排时这样视觉更紧凑,空格反而别扭。
    // 英文保留 ": "(F1: ...)冒号 + 空格,符合英文排版。

    private static let poolHotZH: [String] = [
        "F1维斯塔潘还能卫冕吗?",
        "F1梅奔今年怎么了?",
        "F1法拉利这周能赢吗?",
        "F1诺里斯今年悬吗?",
        "F1安东内利是天才吗?",
        "F1威廉姆斯为啥这么慢?",
        "F1雨战谁最强?",
        "F1积分差能逆转吗?",
        "MotoGP谁追得上马奎斯?",
        "MotoGP巴尼亚亚还稳吗?",
        "WSBK谁是这赛季王者?",
        "FE本季冠军会是谁?",
        "本赛季最戏剧性的一幕?",   // 跨系列 OK
        "今年最大冷门是哪场?"      // 跨系列 OK
    ]

    private static let poolHotEN: [String] = [
        "F1: Can Verstappen defend?",
        "F1: What's up with Mercedes?",
        "F1: Will Ferrari win?",
        "F1: Norris title hopes?",
        "F1: Antonelli — prodigy?",
        "F1: Why is Williams so slow?",
        "F1: Best wet-weather driver?",
        "F1: Points gap reversible?",
        "MotoGP: Who chases Marquez?",
        "MotoGP: Bagnaia steady?",
        "WSBK: Who rules this year?",
        "FE: Title pick this season?",
        "Most dramatic moment so far?",
        "Biggest upset this year?"
    ]

    private static let poolWeekendZH: [String] = [
        "F1周末几点正赛?",
        "MotoGP周末几点正赛?",
        "WSBK周末几点正赛?",
        "FE周末几点正赛?",
        "F1这周末会下雨吗?",
        "把F1正赛加到日历",
        "F1周末有几场练习赛?",
        "F1上轮后积分变化?",
        "MotoGP上轮谁是赢家?",
        "F1本周排位赛几点?",
        "F1是冲刺赛周末吗?",
        "F1本赛道难点在哪?",
        "本周末值得看哪场?"   // 跨系列 OK
    ]

    private static let poolWeekendEN: [String] = [
        "F1: Race time Sunday?",
        "MotoGP: Race time Sunday?",
        "WSBK: Race time Sunday?",
        "FE: Race time Sunday?",
        "F1: Wet weekend?",
        "Add F1 race to calendar",
        "F1: How many practices?",
        "F1: Standings shift since last?",
        "MotoGP: Last round winners?",
        "F1: Quali time this week?",
        "F1: Sprint weekend?",
        "F1: Toughest corner?",
        "Top race to watch this weekend?"
    ]

    public var body: some View {
        NavigationStack {
            content
                // 不再叠红色顶部渐变,走系统纯色背景(支持夜间模式自动切深色)
                .background(Color(.systemBackground).ignoresSafeArea())
                .navigationTitle(L10n.t(zh: "小赛", en: "Xiao Sai"))
                #if canImport(UIKit)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showHistory = true } label: {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                        .accessibilityLabel(L10n.t(zh: "对话历史", en: "Chat History"))
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { viewModel?.startNewSession() } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .disabled((viewModel?.bubbles.isEmpty) ?? true)
                        .accessibilityLabel(L10n.t(zh: "新建对话", en: "New Chat"))
                    }
                }
                .sheet(isPresented: $showHistory) {
                    if let vm = viewModel {
                        ChatHistoryView(
                            currentSessionID: vm.currentSessionID,
                            onSelect: { vm.loadSession($0) },
                            onDelete: { vm.deleteSession($0) },
                            onNew: { vm.startNewSession() }
                        )
                    }
                }
                .onAppear {
                    if viewModel == nil {
                        viewModel = ChatViewModel(modelContext: modelContext)
                    }
                    // 每次进入赛车助手 tab 都回 starter(包括首次进入 / 从其它 tab 切回)。
                    // 历史会话仍在 ChatHistoryView 可查;sheet present/dismiss 不触发 onAppear,
                    // 不影响"对话历史里加载某条 session"的体验。
                    speech.stop()
                    viewModel?.startNewSession()
                }
                .onDisappear {
                    // 离开页面时强制停语音,避免后台一直占麦克风
                    speech.stop()
                }
                // 用户从底部 tab 切到 AI 时 — 总是回 starter(放弃当前会话,历史仍在 ChatHistoryView)
                .onReceive(NotificationCenter.default.publisher(for: .resetChatToStarter)) { _ in
                    speech.stop()
                    viewModel?.startNewSession()
                }
                // 语音转写实时回填到输入框 — listening 中每个 partial 都会触发
                .onChange(of: speech.transcript) { _, newValue in
                    guard speech.isListening, let vm = viewModel else { return }
                    vm.input = newValue
                }
                // AI 思考完成时震一下,LLM 异步返回不需要用户盯着屏幕
                .sensoryFeedback(.impact(weight: .light), trigger: viewModel?.bubbles.count ?? 0)
                // 语音 listening 起停时震一下
                .sensoryFeedback(.impact(weight: .medium), trigger: speech.isListening)
                // 用户点 prompt chip / followUp 建议:轻微 selection,反馈"我的选择被识别"
                .sensoryFeedback(.selection, trigger: promptTapCounter)
                // 用户点 send 按钮:success,确认"消息已送出"
                .sensoryFeedback(.success, trigger: sendCounter)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let vm = viewModel {
            VStack(spacing: 0) {
                if vm.bubbles.isEmpty {
                    starterView(vm: vm)
                } else {
                    chatList(vm: vm)
                }
                ChatComposerView(
                    viewModel: vm,
                    speech: speech,
                    sendCounter: $sendCounter
                )
            }
        } else {
            ProgressView()
        }
    }

    // MARK: - Starter(空会话视图)

    private func starterView(vm: ChatViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {

                // ---------- 今日冷知识 ----------
                TriviaCard(modelContext: modelContext)
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.lg)

                // ---------- 猜你想问 标题(顶部,无换一换按钮) ----------
                Text(L10n.t(zh: "猜你想问", en: "Suggested"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, DS.Spacing.lg)

                // ---------- Prompt 上下排列(最多 5 条,每条一行,宽度自适应内容,左对齐) ----------
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    ForEach(displayedPrompts.prefix(5), id: \.self) { p in
                        Button {
                            promptTapCounter += 1
                            vm.usePrompt(p)
                            Task { await vm.send() }
                        } label: {
                            Text(p)
                                .font(.footnote)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .padding(.horizontal, DS.Spacing.md)
                                .padding(.vertical, 7)
                                .background(
                                    Color(.secondarySystemBackground),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(PressableButtonStyle())
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)

                // ---------- 换一换按钮(放所有 prompts 下面,左对齐) ----------
                HStack {
                    Button {
                        Task { await refreshPromptsAI() }
                    } label: {
                        HStack(spacing: 4) {
                            if isRefreshingPrompts {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.caption.weight(.semibold))
                            }
                            Text(L10n.t(zh: "换一换", en: "Shuffle"))
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .disabled(isRefreshingPrompts)
                    .accessibilityLabel(L10n.t(zh: "换一组提问", en: "Shuffle prompts"))
                    Spacer()
                }
                .padding(.horizontal, DS.Spacing.lg)

                Spacer(minLength: DS.Spacing.xl)
            }
            .padding(.vertical, DS.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            // 首屏立即用本地 pool 抽 5 条,不等 AI(0 延迟)
            if displayedPrompts.isEmpty { refreshPromptsLocal() }
        }
    }

    /// 本地 shuffle —— 从合并 pool 抽 5 条,即时返回,首屏用。
    /// **抽样策略**:用户要求每个系列(F1/MotoGP/WSBK/FE)至少出现 1 条 sug,
    /// 之前纯 random 抽 5 条几乎全是 F1(pool 里 F1 prompt 占 ~70%),小众系列被埋。
    /// 策略:先给每个系列保留 1 个名额(4 条),剩 1 条 + 不够时填补从 pool 余下随机抽。
    /// 最后 shuffle 打乱顺序避免 F1 永远第一位。
    private func refreshPromptsLocal() {
        let pool = mergedPromptPool
        let exclude = Set(displayedPrompts)
        var picked: [String] = []
        var seen = Set<String>()

        // 1. 每个系列先保证 1 条(F1 / MotoGP / WSBK / FE)
        for series in Self.seriesPrefixes {
            let candidates = pool.filter { p in
                !seen.contains(p) && !exclude.contains(p) && Self.seriesFor(p) == series
            }
            if let pick = candidates.randomElement() {
                picked.append(pick)
                seen.insert(pick)
            }
        }

        // 2. 剩下名额从 pool 余下(任意系列 + 跨系列 + followed)随机填
        let remaining = pool.filter { !seen.contains($0) && !exclude.contains($0) }.shuffled()
        for p in remaining where picked.count < 5 {
            picked.append(p)
            seen.insert(p)
        }

        // 3. 还不够 5 条? 放宽 exclude 限制(允许重新出现近期已显示的),保证总有 5 条
        if picked.count < 5 {
            let backup = pool.filter { !seen.contains($0) }.shuffled()
            for p in backup where picked.count < 5 {
                picked.append(p)
                seen.insert(p)
            }
        }

        // 4. 打乱顺序(否则 F1 永远显示在第一位)
        displayedPrompts = picked.shuffled()
    }

    /// AI 生成 —— 点"换一换"才走;失败则回退到本地 shuffle 不打断体验。
    @MainActor
    private func refreshPromptsAI() async {
        isRefreshingPrompts = true
        let followedNames = FollowStore(context: modelContext).all().map { $0.localizedDisplayName }
        let exclude = displayedPrompts
        let result = (try? await LLMClient.shared.suggestStarterPrompts(
            followedNames: followedNames,
            exclude: exclude
        )) ?? []
        isRefreshingPrompts = false

        if result.count >= 5 {
            withAnimation(.easeInOut(duration: 0.25)) {
                displayedPrompts = Array(result.prefix(5))
            }
        } else {
            // AI 失败/解析失败:退化为本地 shuffle,用户至少看到新的一组
            withAnimation(.easeInOut(duration: 0.25)) {
                refreshPromptsLocal()
            }
        }
    }

    // MARK: - 对话列表(有消息时)

    private func chatList(vm: ChatViewModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.Spacing.md) {
                    let items = vm.renderedItems
                    ForEach(items) { item in
                        renderItem(item, vm: vm)
                            .id(item.id)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)),
                                removal: .opacity
                            ))
                    }
                    // 流式中的 assistant bubble — 不在 vm.bubbles 里(避免每个 chunk 全 list diff),
                    // 单独渲染。流式结束 ViewModel 才把 streamingText 合并进 bubbles。
                    if !vm.streamingText.isEmpty, let sid = vm.streamingId {
                        BubbleView(
                            bubble: .assistant(id: sid, text: vm.streamingText),
                            isStreaming: true,
                            onCopy: {},
                            onRegenerate: {}
                        )
                        .id("__streaming")
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    if !vm.isThinking, !vm.followUps.isEmpty {
                        followUpChips(vm: vm)
                            .id("followUps")
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.vertical, DS.Spacing.md)
                // 不给 bubbles.count 加 .animation() — flushStreamingToBubbles 用
                // Transaction(disablesAnimations: true) 禁动画,如果这里还挂 .animation()
                // SwiftUI 会无视 transaction 导致 flush 时也播 spring,跟 scrollTo 叠加 jitter。
            }
            .onChange(of: vm.bubbles.count) { _, _ in
                if let last = vm.bubbles.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            // 流式期间用节拍器驱动连续滚动(每 150ms 一跳)。
            // 替代原来的 onChange(of: Bool) 只触发一次 — 那个方案文字在长但列表没跟上。
            // .task(id: isStreaming) 自然在 streaming 翻 false 时取消;空闲时零唤醒。
            .task(id: vm.isStreaming) {
                guard vm.isStreaming else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled else { return }
                    proxy.scrollTo("__streaming", anchor: .bottom)
                }
            }
            .onChange(of: vm.followUps) { _, new in
                if !new.isEmpty {
                    withAnimation(DS.Motion.layout) {
                        proxy.scrollTo("followUps", anchor: .bottom)
                    }
                }
            }
        }
    }

    /// 追问建议 chips —— 竖排,每条一行,点击立即发送。无标题(头部图标已删)。
    private func followUpChips(vm: ChatViewModel) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            ForEach(vm.followUps, id: \.self) { sug in
                Button {
                    promptTapCounter += 1
                    vm.usePrompt(sug)
                    Task { await vm.send() }
                } label: {
                    Text(sug)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, DS.Spacing.sm)
                        .background(DS.Palette.primaryFaint, in: Capsule())
                        .overlay(
                            Capsule().strokeBorder(DS.Palette.primary.opacity(0.4), lineWidth: 0.8)
                        )
                        .foregroundStyle(DS.Palette.primary)
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
        .padding(.horizontal, DS.Spacing.lg + DS.Avatar.size + DS.Spacing.sm)
    }
}

// MARK: - 渲染单元(把连续 toolStep 折叠成一组,豆包/元宝式 "工具调用 N 步")

extension ChatView {
    /// chatList 渲染单元 — 比 ViewModel.Bubble 多一层"工具组"折叠。
    enum RenderItem: Identifiable, Equatable {
        case message(ChatViewModel.Bubble)
        case toolGroup(id: UUID, steps: [ToolStep])

        struct ToolStep: Identifiable, Equatable {
            let id: UUID
            let name: String
            let status: ChatViewModel.Bubble.ToolStatus
            let preview: String?
            let runningHint: String?
            let startedAt: Date
            let finishedAt: Date?

            /// 显示用耗时(秒) — done/failed 才有,running 时返 nil。
            /// 用法:`step.duration.map { String(format: "%.1fs", $0) }`
            var duration: TimeInterval? {
                guard let e = finishedAt else { return nil }
                return max(0, e.timeIntervalSince(startedAt))
            }
        }

        var id: UUID {
            switch self {
            case .message(let b):       return b.id
            case .toolGroup(let id, _): return id
            }
        }
    }

    @ViewBuilder
    func renderItem(_ item: RenderItem, vm: ChatViewModel) -> some View {
        switch item {
        case .message(let bubble):
            let bubbles = vm.bubbles
            let isLastBubble = bubbles.last?.id == bubble.id
            // 只有当 bubble 的 id 等于 vm.streamingId 时才显示光标。
            // 修复:用 vm.isThinking 算会有一帧 race —— flushStreamingToBubbles 把 bubble
            // append 进 bubbles 后,isThinking 设 false 之前,SwiftUI 看到 isLastBubble 是
            // 这条新 bubble + isThinking 仍 true → 误判为 streaming → cursor 残留闪烁。
            // 改用 streamingId 后 flush 时已 nil → 新 bubble.id != streamingId → 立即停光标。
            let isStreaming: Bool = {
                guard isLastBubble else { return false }
                if case .assistant(let id, _) = bubble {
                    return id == vm.streamingId
                }
                return false
            }()
            BubbleView(
                bubble: bubble,
                isStreaming: isStreaming,
                onCopy: { vm.copy(bubbleId: bubble.id) },
                onRegenerate: { Task { await vm.regenerate(bubbleId: bubble.id) } }
            )
        case .toolGroup(_, let steps):
            // 显示规则:
            // - running 中 → 完整 group 展示进度(shimmer / 计时 / 取消)
            // - 任一 failed → 保留显示,提供重试入口(否则用户没办法恢复)
            // - 全 done → 隐藏(保持对话流干净 — 这是原始用户诉求)
            // 用 transition 切换避免 if 切换时"上下窜动"突变。
            let hasRunning = steps.contains(where: { $0.status == .running })
            let hasFailed = steps.contains(where: { $0.status == .failed })
            if hasRunning || hasFailed {
                ToolGroupView(
                    steps: steps,
                    autoExpand: hasRunning,
                    onCancel: hasRunning ? { vm.stop() } : nil,
                    onRetry: hasFailed ? { stepId in
                        Task { await vm.retryToolStep(bubbleId: stepId) }
                    } : nil
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top))
                        .animation(.easeOut(duration: 0.25)),
                    removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
                        .animation(.easeIn(duration: 0.30))
                ))
            }
        }
    }
}
