import SwiftUI
import SwiftData
// Timer.publish(...).autoconnect() 来自 Combine — SwiftUI 不再自动 re-export Combine,
// ToolGroupView 用 .onReceive 订阅 timer 计时必须显式 import。
import Combine
import PoleDesignSystem

struct ChatView: View {
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

    var body: some View {
        NavigationStack {
            content
                // 不再叠红色顶部渐变,走系统纯色背景(支持夜间模式自动切深色)
                .background(Color(.systemBackground).ignoresSafeArea())
                .navigationTitle(L10n.t(zh: "小赛", en: "Xiao Sai"))
                .navigationBarTitleDisplayMode(.inline)
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
                inputBar(vm: vm)
            }
        } else {
            ProgressView()
        }
    }

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
            .onReceive(
                vm.isStreaming
                    ? Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()
                    : Timer.publish(every: 3600, on: .main, in: .common).autoconnect()
            ) { _ in
                if vm.isStreaming {
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

    private func inputBar(vm: ChatViewModel) -> some View {
        // canSend 已上提到 vm.canSend,view 不再自己 trim 字符串。
        let canSend = vm.canSend
        let charCount = vm.input.count
        let charLimit = 500

        return VStack(spacing: DS.Spacing.xs) {
            // 语音权限/识别提示条 — 仅有 errorMessage 时显示,3 秒后用户重试或自动消失
            if let msg = speech.errorMessage {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.caption2)
                    Text(msg)
                        .font(.caption2)
                    Spacer()
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text(L10n.t(zh: "去设置", en: "Settings"))
                            .font(.caption2.weight(.semibold))
                    }
                }
                .foregroundStyle(DS.Palette.live)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm)
                .background(DS.Palette.live.opacity(0.10), in: Capsule())
                .padding(.horizontal, DS.Spacing.md)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            // 听写中条 — 显示当前 transcript,提供"取消"
            if speech.isListening {
                listeningStatusBar
            }

            HStack(alignment: .bottom, spacing: DS.Spacing.sm) {
                // 单行胶囊输入框 — 键盘回车触发发送(无独立 send 按钮)
                TextField(L10n.t(zh: "输入问题…", en: "Ask a question…"), text: Binding(
                    get: { vm.input },
                    set: { vm.input = $0 }
                ))
                .textFieldStyle(.plain)
                .font(DS.Font.bubble)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm + 2)
                .background(DS.Palette.inputFill,
                            in: RoundedRectangle(cornerRadius: DS.Radius.pill, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.pill, style: .continuous)
                        .strokeBorder(canSend ? DS.Palette.primary.opacity(0.35) : Color.clear, lineWidth: 0.8)
                )
                .animation(DS.Motion.layout, value: canSend)
                .accessibilityLabel(L10n.t(zh: "问题输入框", en: "Question input"))
                .submitLabel(.send)
                .onSubmit {
                    guard canSend else { return }
                    speech.stop()
                    sendCounter += 1
                    Task { await vm.send() }
                }

                // 麦克风按钮(右侧) — 点击切换 listening
                Button {
                    Task { await speech.toggle() }
                } label: {
                    Image(systemName: speech.isListening ? "waveform" : "mic.fill")
                        .font(.body.weight(.semibold))
                        .imageScale(.medium)
                        .foregroundStyle(speech.isListening ? .white : DS.Palette.primary)
                        .frame(width: 38, height: 38)
                        .background(
                            speech.isListening
                                ? AnyShapeStyle(DS.Palette.aiGradient)
                                : AnyShapeStyle(DS.Palette.primaryFaint),
                            in: Circle()
                        )
                        .symbolEffect(.variableColor.iterative, isActive: speech.isListening)
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(vm.isThinking)
                .animation(DS.Motion.press, value: speech.isListening)
                .accessibilityLabel(speech.isListening
                                    ? L10n.t(zh: "停止语音输入", en: "Stop voice input")
                                    : L10n.t(zh: "语音输入", en: "Voice input"))
            }

            // 字数提示(只在接近上限时显示,豆包式克制)
            if charCount > charLimit - 50 {
                HStack {
                    Spacer()
                    Text("\(charCount)/\(charLimit)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(charCount > charLimit
                                         ? AnyShapeStyle(DS.Palette.live)
                                         : AnyShapeStyle(HierarchicalShapeStyle.tertiary))
                }
                .padding(.horizontal, DS.Spacing.md)
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.top, DS.Spacing.sm)
        .padding(.bottom, DS.Spacing.sm)
        .background(.bar)
        .animation(DS.Motion.layout, value: speech.isListening)
        .animation(DS.Motion.layout, value: speech.errorMessage)
    }

    /// listening 状态条 — 紫渐变背景 + 实时转写预览 + 取消/完成按钮。
    private var listeningStatusBar: some View {
        HStack(spacing: DS.Spacing.sm) {
            // 三圆点波形动画(占位的"听音浪")— 整段被外层 `if speech.isListening` 控制,
            // 非 listening 时整体不渲染,SwiftUI 自然 GC 动画 loop。
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(.white.opacity(0.85))
                        .frame(width: 3, height: CGFloat([10, 16, 10][i]))
                        .animation(
                            .easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.15),
                            value: speech.isListening
                        )
                }
            }
            .frame(width: 24)

            Text(speech.transcript.isEmpty
                 ? L10n.t(zh: "听写中…说一句赛车问题", en: "Listening… ask anything about racing")
                 : speech.transcript)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                speech.stop()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(L10n.t(zh: "取消语音输入", en: "Cancel voice input"))
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        // 老版本用实色 aiGradient + 白文字,违反 Liquid Glass "solid fills break glass character" 规则。
        // iOS 26+ 用 glassEffect(.regular.tint(...)) + 旧机 fallback 仍用 gradient capsule。
        .modifier(ListeningBarSurface())
        .padding(.horizontal, DS.Spacing.md)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

// MARK: - 按下缩放反馈(豆包/元宝按钮通用)

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(DS.Motion.press, value: configuration.isPressed)
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

private struct ToolGroupView: View {
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

    var body: some View {
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

private enum ToolMetadata {
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

// MARK: - Bubble row

private struct BubbleView: View {
    let bubble: ChatViewModel.Bubble
    let isStreaming: Bool
    let onCopy: () -> Void
    let onRegenerate: () -> Void

    @State private var copied = false

    var body: some View {
        switch bubble {
        case .user(_, let text):
            userBubble(text: text)
        case .assistant(_, let text):
            assistantBubble(text: text)
        case .toolStep:
            // Dead branch — ChatView.RenderItem 已经把所有连续 .toolStep 折叠成
            // ToolGroupView 渲染,单条 toolStep 永远不会进 BubbleView。
            // 显式 EmptyView 让以后误用也只是空白而非异常。
            EmptyView()
        }
    }

    // MARK: 用户气泡(右侧,紫渐变,首尾不对称圆角)

    private func userBubble(text: String) -> some View {
        HStack {
            Spacer(minLength: 48)
            Text(text)
                .font(DS.Font.bubble)
                .foregroundStyle(.white)
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.md - 2)
                .background(DS.Palette.aiGradient,
                            in: UnevenRoundedRectangle(
                                cornerRadii: .init(
                                    topLeading: DS.Radius.bubble,
                                    bottomLeading: DS.Radius.bubble,
                                    bottomTrailing: DS.Radius.sm,
                                    topTrailing: DS.Radius.bubble
                                )
                            ))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = text
                    } label: { Label(L10n.t(zh: "复制", en: "Copy"), systemImage: "doc.on.doc") }
                }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: AI 气泡(左侧带头像,白底卡片,可流式光标 + 操作行)

    private func assistantBubble(text: String) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            AIAvatar(size: .small)
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                // 文本气泡 + 流式光标。
                // isStreaming 时 AssistantMarkdownText 走纯 Text 快路径,
                // 避免每个 chunk 都做 AttributedString markdown parse(主线程帧预算大头)。
                VStack(alignment: .leading, spacing: 0) {
                    AssistantMarkdownText(text: text, isStreaming: isStreaming)
                    if isStreaming {
                        HStack(spacing: 0) {
                            StreamingCursor()
                        }
                    }
                }
                .font(DS.Font.bubble)
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.md - 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipShape(UnevenRoundedRectangle(
                    cornerRadii: .init(
                        topLeading: DS.Radius.sm,
                        bottomLeading: DS.Radius.bubble,
                        bottomTrailing: DS.Radius.bubble,
                        topTrailing: DS.Radius.bubble
                    )
                ))
                .background(
                    UnevenRoundedRectangle(
                        cornerRadii: .init(
                            topLeading: DS.Radius.sm,
                            bottomLeading: DS.Radius.bubble,
                            bottomTrailing: DS.Radius.bubble,
                            topTrailing: DS.Radius.bubble
                        )
                    )
                    .fill(DS.Palette.aiBubbleFill)
                )
                .overlay(
                    UnevenRoundedRectangle(
                        cornerRadii: .init(
                            topLeading: DS.Radius.sm,
                            bottomLeading: DS.Radius.bubble,
                            bottomTrailing: DS.Radius.bubble,
                            topTrailing: DS.Radius.bubble
                        )
                    )
                    .strokeBorder(DS.Palette.aiBubbleStroke, lineWidth: 0.5)
                )
                .shadow(color: DS.Shadow.bubble.color,
                        radius: DS.Shadow.bubble.radius,
                        x: DS.Shadow.bubble.x, y: DS.Shadow.bubble.y)
                .contextMenu {
                    Button {
                        onCopy()
                        showCopiedToast()
                    } label: { Label(L10n.t(zh: "复制", en: "Copy"), systemImage: "doc.on.doc") }
                    Button {
                        onRegenerate()
                    } label: { Label(L10n.t(zh: "重新生成", en: "Regenerate"), systemImage: "arrow.triangle.2.circlepath") }
                }
            }
            Spacer(minLength: 48)
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    private func actionIcon(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: systemName)
                    .font(.caption2.weight(.semibold))
                Text(label)
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, 4)
            .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func showCopiedToast() {
        copied = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            copied = false
        }
    }

    // 注: 单条 .toolStep 渲染逻辑已删除 — ChatView.RenderItem 把连续 .toolStep
    // 折叠成 ToolGroupView,BubbleView 永远拿不到 .toolStep case。
    // statusIcon / humanLabel 之前的 BubbleView 副本与 ToolGroupView 内的副本一字不差,
    // 单一定义保留在 ToolGroupView 里;humanLabel 后续抽 AgentToolName.swift 再统一。
}

// MARK: - Assistant 文本(轻量 markdown 渲染)

/// 把 LLM 的回答按"空行=段落、单换行=同段落内独立行"切开,每行用 inline markdown 解析。
/// 这样 `**xxx**` 加粗、`*xxx*` 斜体、`` `xxx` `` 代码都生效,不需要完整 markdown parser。
/// 段落间间距大、段落内行间距小,视觉上比一坨 Text 整齐。
///
/// 性能: AttributedString markdown 解析是 ms 级 expensive,流式期间每 chunk 重新 parse
/// 全文会主线程吃帧时间预算。`isStreaming=true` 时走纯 Text 快路径(段落分行不解析 inline
/// markdown),流式结束后再切回完整 parse,视觉上一瞬间补回 **加粗** 等格式。
private struct AssistantMarkdownText: View {
    let text: String
    var isStreaming: Bool = false

    var body: some View {
        if isStreaming {
            streamingFastPath
        } else {
            let blocks = parse(text)
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                ForEach(blocks.indices, id: \.self) { i in
                    blockView(blocks[i])
                }
            }
        }
    }

    /// 流式快路径——按空行切段落,段落内单换行切行,
    /// 用 streamingBoldAttributed 处理 **xxx** 加粗（不做完整 markdown parse 避免每 chunk 卡帧）。
    private var streamingFastPath: some View {
        let paragraphs = text.components(separatedBy: "\n\n")
        return VStack(alignment: .leading, spacing: DS.Spacing.md) {
            ForEach(paragraphs.indices, id: \.self) { pi in
                let lines = paragraphs[pi]
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .map(String.init)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(lines.indices, id: \.self) { li in
                        Text(Self.streamingBoldAttributed(lines[li]))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// 共享 bold 正则,避免每个 chunk 重建。NSRegularExpression 线程安全。
    private static let boldRegex: NSRegularExpression? = try? NSRegularExpression(pattern: #"\*\*(.+?)\*\*"#)

    /// O(n) 正则扫描:`**xxx**` 渲染为加粗,其他 markdown 标记保留字面字符。
    /// 流式期间用,避免每个 chunk 重新跑完整 AttributedString markdown parse 卡帧。
    /// 跨 chunk 半成品 `**xx`(未闭合)：当普通文本，等下一 chunk 闭合 `**` 到达后下次重渲染才加粗。
    private static func streamingBoldAttributed(_ s: String) -> AttributedString {
        var result = AttributedString()
        guard let regex = Self.boldRegex else {
            return AttributedString(s)
        }
        let nsRange = NSRange(s.startIndex..<s.endIndex, in: s)
        let matches = regex.matches(in: s, options: [], range: nsRange)

        var lastEnd = s.startIndex
        for match in matches {
            guard let fullRange = Range(match.range, in: s),
                  let innerRange = Range(match.range(at: 1), in: s) else { continue }
            result += AttributedString(String(s[lastEnd..<fullRange.lowerBound]))
            var bolded = AttributedString(String(s[innerRange]))
            bolded.font = .body.bold()
            result += bolded
            lastEnd = fullRange.upperBound
        }
        result += AttributedString(String(s[lastEnd..<s.endIndex]))
        return result
    }

    /// LLM 回答里可能出现的"块"类型。
    private enum Block: Hashable {
        case paragraph(lines: [AttributedString])
        case codeBlock(language: String?, code: String)
        /// 表格 — `rows[0]` 是 header,后续是数据行。
        case table(rows: [[String]])
    }

    /// 行级扫描:识别 ``` 代码块 / | 表格 / 普通段落,跨段落都用空行分隔。
    private func parse(_ raw: String) -> [Block] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var blocks: [Block] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            // ----- 代码块 -----
            if line.hasPrefix("```") {
                let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                i += 1
                var codeLines: [String] = []
                while i < lines.count, !lines[i].hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                // 跳过闭合 ```
                if i < lines.count, lines[i].hasPrefix("```") { i += 1 }
                blocks.append(.codeBlock(
                    language: lang.isEmpty ? nil : lang,
                    code: codeLines.joined(separator: "\n")
                ))
                continue
            }
            // ----- 段落 / 表格(收集到下一个空行或 ```) -----
            var paraLines: [String] = []
            while i < lines.count,
                  !lines[i].trimmingCharacters(in: .whitespaces).isEmpty,
                  !lines[i].hasPrefix("```") {
                paraLines.append(lines[i])
                i += 1
            }
            if !paraLines.isEmpty {
                blocks.append(makeBlock(from: paraLines))
            }
            // 跳过连续空行
            while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                i += 1
            }
        }
        return blocks
    }

    /// 几行连续文本 → 表格 / 段落。表格判定:连续 ≥2 行都含 `|` 且不全是分隔行。
    private func makeBlock(from paraLines: [String]) -> Block {
        if paraLines.count >= 2, paraLines.allSatisfy({ $0.contains("|") }) {
            let rows = paraLines.compactMap { row -> [String]? in
                let cells = row
                    .split(separator: "|", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                guard !cells.isEmpty else { return nil }
                // 跳过分隔行 |---|---|
                if cells.allSatisfy({ $0.allSatisfy { c in c == "-" || c == ":" || c.isWhitespace } }) {
                    return nil
                }
                return cells
            }
            if rows.count >= 2 {
                return .table(rows: rows)
            }
        }
        let attrs = paraLines.map { line -> AttributedString in
            // 容错:LLM 偶发输出 ** xx **(边界空格)→ 规整成 **xx**
            let cleaned = line
                .replacingOccurrences(of: "** ", with: "**")
                .replacingOccurrences(of: " **", with: "**")
            if let attr = try? AttributedString(
                markdown: cleaned,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            ) { return attr }
            return AttributedString(line)
        }
        return .paragraph(lines: attrs)
    }

    @ViewBuilder
    private func blockView(_ b: Block) -> some View {
        switch b {
        case .paragraph(let lines):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(lines.indices, id: \.self) { i in
                    Text(lines[i])
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .codeBlock(let lang, let code):
            CodeBlockView(language: lang, code: code)
        case .table(let rows):
            TableBlockView(rows: rows)
        }
    }
}

// MARK: - 代码块组件(暗底 monospace + 复制按钮)

private struct CodeBlockView: View {
    let language: String?
    let code: String

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部条:语言 + 复制按钮
            HStack(spacing: DS.Spacing.sm) {
                Text(language?.uppercased() ?? L10n.t(zh: "代码", en: "CODE"))
                    .font(.caption2.weight(.semibold).monospaced())
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    copied = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.2))
                        copied = false
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.caption2.weight(.semibold))
                        Text(copied
                             ? L10n.t(zh: "已复制", en: "Copied")
                             : L10n.t(zh: "复制", en: "Copy"))
                            .font(.caption2)
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, DS.Spacing.sm)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.10), in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .background(Color.black.opacity(0.55))

            // 代码区(横滚防长行)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.md)
                    .frame(minWidth: 0, alignment: .leading)
            }
            .background(Color.black.opacity(0.78))
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }
}

// MARK: - 表格降级组件
//
// 窄屏 iPhone 上 markdown 表格 (`| col | col |`) 渲染成多列必然错乱。
// 降级策略:每数据行渲染成一张"卡片",卡片内每个 cell 一行 "header → value",
// 横滚也不需要,直接顺序读完。

private struct TableBlockView: View {
    /// rows[0] 是 header,后续是数据行。
    let rows: [[String]]

    var body: some View {
        let header = rows.first ?? []
        let dataRows = rows.dropFirst()

        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            ForEach(Array(dataRows.enumerated()), id: \.offset) { _, row in
                tableCard(header: header, row: row)
            }
        }
    }

    private func tableCard(header: [String], row: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(0..<row.count, id: \.self) { i in
                HStack(alignment: .top, spacing: DS.Spacing.sm) {
                    Text(i < header.count ? header[i] : "")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 60, alignment: .leading)
                    Text(row[i])
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Palette.primaryFaint, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(DS.Palette.primary.opacity(0.20), lineWidth: 0.5)
        )
    }
}

/// listening status bar 容器材质 — iOS 26+ Liquid Glass tint,旧机 aiGradient fallback。
private struct ListeningBarSurface: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.tint(DS.Palette.primary.opacity(0.35)), in: Capsule())
        } else {
            content
                .background(DS.Palette.aiGradient, in: Capsule())
        }
    }
}

