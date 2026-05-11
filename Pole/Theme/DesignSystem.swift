import SwiftUI

// MARK: - Design System
//
// 集中所有视觉 token —— 颜色 / 间距 / 圆角 / 字号 / 动效曲线。
// 改造一处颜色或间距规则,只需改这一份;Chat 模块和后续全 app 一致性改动都依赖它。
//
// 命名灵感参考豆包 / 元宝 / 微信对话流的"AI 助手"语汇。
// 凡是出现"BrandPalette.xxx"的位置以后逐步迁移到这里;新代码直接用 DS。

public enum DS {

    // MARK: 间距 (4 倍数刻度,iOS HIG 友好)

    public enum Spacing {
        public static let xxs: CGFloat = 2
        public static let xs:  CGFloat = 4
        public static let sm:  CGFloat = 8
        public static let md:  CGFloat = 12
        public static let lg:  CGFloat = 16
        public static let xl:  CGFloat = 20
        public static let xxl: CGFloat = 28
        public static let xxxl: CGFloat = 40
    }

    // MARK: 圆角

    public enum Radius {
        public static let sm: CGFloat = 4     // 旧 8
        public static let md: CGFloat = 8     // 旧 12
        public static let lg: CGFloat = 12    // 旧 16
        public static let xl: CGFloat = 16    // 旧 20
        public static let xxl: CGFloat = 20   // 旧 24
        public static let bubble: CGFloat = 14  // 旧 20
        public static let pill: CGFloat = 18    // 旧 22
    }

    // MARK: 颜色

    public enum Palette {
        // ===== Racing 红系: 双模通用 =====
        public static let racingRed     = Color(red: 0.882, green: 0.024, blue: 0)
        public static let racingRedSoft = Color(red: 1.000, green: 0.122, blue: 0.102)
        public static let racingRedDeep = Color(red: 0.612, green: 0.020, blue: 0)
        public static let racingRedFaint = racingRed.opacity(0.10)

        public static let racingGradient = LinearGradient(
            colors: [racingRedDeep, racingRed, racingRedSoft],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )

        public static let racingGradientStrong = LinearGradient(
            colors: [racingRedDeep, racingRed],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )

        // ===== 向后兼容 alias(让 14 处 .primary 引用直接编译通过)=====
        public static let primary      = racingRed
        public static let primarySoft  = racingRedSoft
        public static let primaryDeep  = racingRedDeep
        public static let primaryFaint = racingRedFaint
        public static let aiGradient   = racingGradient
        public static let aiGradientStrong = racingGradientStrong

        // ===== Tarmac 中性: UIColor dynamic 双模 =====
        public static let tarmacBg = Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.055, green: 0.055, blue: 0.063, alpha: 1)
                : UIColor.systemBackground
        })

        public static let tarmacFill = Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.094, green: 0.094, blue: 0.106, alpha: 1)
                : UIColor.secondarySystemBackground
        })

        public static let tarmacCard = Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.137, green: 0.137, blue: 0.153, alpha: 1)
                : UIColor.tertiarySystemBackground
        })

        public static let tarmacHairline = Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.180, green: 0.180, blue: 0.200, alpha: 1)
                : UIColor.separator
        })

        public static let decorOnSurface = Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.08)
                : UIColor.black.withAlphaComponent(0.06)
        })

        // ===== 状態色(Dark 下加饱和)=====
        public static let live      = Color(red: 1.000, green: 0.176, blue: 0.176)
        public static let upcoming  = Color(red: 0.302, green: 0.659, blue: 1.000)
        public static let finished  = Color(.systemGray)
        public static let postponed = Color.orange

        // ===== AI 消息气泡(双模 dynamic)=====
        public static var aiBubbleFill: Color { tarmacCard }
        public static var aiBubbleStroke: Color { tarmacHairline }
        public static var toolCardFill: Color { tarmacCard }
        public static var inputFill: Color { tarmacFill }
    }

    // MARK: 字号

    public enum Font {
        /// 消息正文 — `.subheadline`(15pt),比 `.callout` 小一档但仍可读;
        /// 老版本 `.callout` 在 chat 流里偏大,排版显拥挤。
        public static let bubble = SwiftUI.Font.system(.footnote)
        public static let bubbleBold = SwiftUI.Font.system(.footnote, weight: .semibold)
        /// AI 消息时间戳
        public static let timestamp = SwiftUI.Font.caption2
        /// 工具步骤标签
        public static let toolLabel = SwiftUI.Font.caption.weight(.semibold)
        public static let toolPreview = SwiftUI.Font.caption2
        /// Greeting 大标题 — 用 `.title3` 让"早上好"等问候不抢戏
        public static let heroTitle = SwiftUI.Font.system(.title3, design: .rounded, weight: .bold)
        public static let heroSubtitle = SwiftUI.Font.footnote
    }

    // MARK: 阴影

    public enum Shadow {
        public static let bubble = ShadowStyle(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        public static let card   = ShadowStyle(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
        public static let aiHero = ShadowStyle(color: Palette.primary.opacity(0.35), radius: 20, x: 0, y: 6)

        public struct ShadowStyle: Sendable {
            public let color: Color
            public let radius: CGFloat
            public let x: CGFloat
            public let y: CGFloat
        }
    }

    // MARK: 动效曲线

    public enum Motion {
        /// 入场:略 bounce 的 spring,豆包消息出现感
        public static let bubbleEntry: Animation = .spring(response: 0.35, dampingFraction: 0.78)
        /// UI 切换:平顺 ease
        public static let layout: Animation = .easeOut(duration: 0.2)
        /// 按下反馈:快速 spring
        public static let press: Animation = .spring(response: 0.18, dampingFraction: 0.7)
        /// 流式光标闪烁
        public static let cursorBlink: Animation = .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
    }

    // MARK: AI 头像 - sparkles 紫渐变球(豆包/元宝同款"主角"识别符)

    public enum Avatar {
        public static let size: CGFloat = 32
        public static let sizeLarge: CGFloat = 96
    }
}

// MARK: - 便捷 modifier

public extension View {
    /// AI 消息卡片 — iOS 26 Liquid Glass 自带 specular + 自适应对比;旧 SDK 兜底浅底卡片。
    @ViewBuilder
    func dsAIBubble() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: DS.Radius.bubble, style: .continuous)
            )
        } else {
            self
                .background(DS.Palette.aiBubbleFill,
                            in: RoundedRectangle(cornerRadius: DS.Radius.bubble, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.bubble, style: .continuous)
                        .strokeBorder(DS.Palette.aiBubbleStroke, lineWidth: 0.5)
                )
                .shadow(color: DS.Shadow.bubble.color,
                        radius: DS.Shadow.bubble.radius,
                        x: DS.Shadow.bubble.x, y: DS.Shadow.bubble.y)
        }
    }

    /// 通用胶囊容器 — segmented picker / refresh chip / timeline section header 等用,
    /// iOS 26+ Liquid Glass,旧机 ultraThinMaterial fallback。
    /// 老代码各处直接 `.background(.ultraThinMaterial, in: Capsule())` 不带 26+ gate,
    /// 在 iOS 26 上与同屏 glassEffect 共存导致 glass-on-material 视觉错乱。
    @ViewBuilder
    func dsGlassPill() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: Capsule())
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
        }
    }

    /// 工具步骤卡片 — Liquid Glass 一行替代 material + stroke 双层装饰。
    @ViewBuilder
    func dsToolCard() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            )
        } else {
            self
                .background(.ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        }
    }

    /// hero element 红色发光阴影(发送按钮等)。Liquid Glass 时代视觉已弱化,
    /// 仅作 fallback 兜底,iOS 26 上可省略调用——直接 .glassEffect + .tint 更合规。
    func dsAIGlow() -> some View {
        self.shadow(color: DS.Shadow.aiHero.color,
                    radius: DS.Shadow.aiHero.radius,
                    x: DS.Shadow.aiHero.x, y: DS.Shadow.aiHero.y)
    }

    /// Detail 页统一 list 风格(豆包/元宝典型):insetGrouped + 隐藏 row 分隔线 + 透明背景。
    /// 4 个 RoundDetail/DriverDetail 都加这个 modifier。
    func dsDetailList() -> some View {
        self
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemBackground))
            .listSectionSpacing(DS.Spacing.md)
    }

    /// 通用 list row 卡片包装(积分榜行 / 详情 section item / 关注 row 用)。
    /// 单卡片 padding 14×12,圆角 16,secondarySystemBackground 底,极淡描边 + 微阴影。
    func dsListCard() -> some View {
        self
            .padding(.horizontal, DS.Spacing.lg - 2)
            .padding(.vertical, DS.Spacing.md)
            .background(
                Color(uiColor: .secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
    }
}

// MARK: - 通用胶囊 segmented picker(豆包/元宝同款)
//
// 系统 .pickerStyle(.segmented) 太朴素;胶囊式更贴 AI 助手风格。
// 用法:`SegmentedPillPicker(selection: $tab, items: T.allCases) { Text($0.displayName) }`

public struct SegmentedPillPicker<T: Hashable, Label: View>: View {
    @Binding var selection: T
    let items: [T]
    let label: (T) -> Label

    public init(selection: Binding<T>, items: [T], @ViewBuilder label: @escaping (T) -> Label) {
        self._selection = selection
        self.items = items
        self.label = label
    }

    public var body: some View {
        HStack(spacing: DS.Spacing.xxs) {
            ForEach(items, id: \.self) { item in
                let selected = (item == selection)
                Button {
                    selection = item
                } label: {
                    label(item)
                        .font(.caption.weight(selected ? .semibold : .medium))
                        .foregroundStyle(selected ? Color.white : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.sm - 2)
                        .background(
                            selected
                                ? AnyShapeStyle(DS.Palette.aiGradient)
                                : AnyShapeStyle(Color.clear),
                            in: Capsule()
                        )
                        .animation(DS.Motion.layout, value: selected)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DS.Spacing.xxs)
        .dsGlassPill()
    }
}

// MARK: - AI 头像组件(可复用)

/// 36 / 96 两档头像 — sparkles 紫渐变圆。
/// AI 头像 — 渐变圆底 + 方向盘图标(赛车语义,跟 tab bar 风格统一)。
public struct AIAvatar: View {
    public enum Size { case small, large }
    let size: Size

    public init(size: Size = .small) { self.size = size }

    public var body: some View {
        let dim: CGFloat = size == .small ? DS.Avatar.size : DS.Avatar.sizeLarge
        let iconSize: CGFloat = size == .small ? 15 : 42
        ZStack {
            Circle()
                .fill(DS.Palette.aiGradient)
            Image(systemName: "steeringwheel")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: dim, height: dim)
        .shadow(color: DS.Palette.primary.opacity(size == .large ? 0.4 : 0.25),
                radius: size == .large ? 20 : 6, y: size == .large ? 6 : 2)
        .accessibilityHidden(true)
    }
}

// MARK: - 呼吸点(running 状态指示器,替代默认 ProgressView 更克制)
//
// Linear / Anthropic 风格:0.85↔1.0 scale + 0.4↔1.0 opacity 1.2s 循环,
// 表达"在工作但不抢戏"的视觉语言,比 stock UIActivityIndicatorView 安静得多。

public struct BreathingDot: View {
    let color: Color
    let size: CGFloat

    @State private var animating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(color: Color = DS.Palette.primary, size: CGFloat = 10) {
        self.color = color
        self.size = size
    }

    public var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .scaleEffect(reduceMotion ? 1.0 : (animating ? 1.0 : 0.7))
            .opacity(reduceMotion ? 1.0 : (animating ? 1.0 : 0.45))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    animating = true
                }
            }
            .onDisappear {
                withAnimation(.linear(duration: 0)) { animating = false }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Shimmer 光带 (running 行,Claude / Perplexity 同款"工作中"质感)
//
// 在目标 view 上叠加一条 0.0→0.35→0.0 透明度的高斯渐变带从左→右扫过,1.5s 周期。
// 优点:不需要给 view 改实际颜色,只是 overlay,任何 background/material 都能用。
// reduceMotion 下完全禁用动画,只显示一次性的静态 view(无 shimmer)。

private struct ShimmerOverlay: ViewModifier {
    let active: Bool

    @State private var phase: CGFloat = -1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if active && !reduceMotion {
                    GeometryReader { geo in
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: .white.opacity(0.35), location: 0.5),
                                .init(color: .clear, location: 1.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 0.5)
                        .offset(x: phase * geo.size.width * 1.5)
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                    }
                    .mask(content)
                    .onAppear {
                        withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                            phase = 1.0
                        }
                    }
                }
            }
    }
}

public extension View {
    /// shimmer 光带 — `active` true 时启动循环,false / reduceMotion 完全无效。
    /// 用法:`row.dsShimmer(active: step.status == .running)`
    func dsShimmer(active: Bool) -> some View {
        modifier(ShimmerOverlay(active: active))
    }
}

// MARK: - 触觉反馈(iOS UIFeedbackGenerator 封装)
//
// 集中调用避免散落 import UIKit。所有方法都是 fire-and-forget,失败静默。
// 在 Mac Catalyst / accessibility 关闭触觉时,UIFeedbackGenerator 自身静默不报错。

public enum HapticFeedback {
    /// 轻微触感 — 适合工具步骤完成、单个 step done 这种"小成就"
    public static func lightImpact() {
        let g = UIImpactFeedbackGenerator(style: .light)
        g.impactOccurred()
    }

    /// 柔软触感 — 工具开始,比 light 更轻
    public static func softImpact() {
        let g = UIImpactFeedbackGenerator(style: .soft)
        g.impactOccurred()
    }

    /// success — 整轮 agent 完成
    public static func success() {
        let g = UINotificationFeedbackGenerator()
        g.notificationOccurred(.success)
    }

    /// warning — 失败 / 取消
    public static func warning() {
        let g = UINotificationFeedbackGenerator()
        g.notificationOccurred(.warning)
    }
}

// MARK: - 流式光标(豆包打字机感)

public struct StreamingCursor: View {
    @State private var blink = false

    public init() {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
        Text("▍")
            .font(DS.Font.bubble)
            .foregroundStyle(DS.Palette.primary)
            .opacity(reduceMotion ? 1.0 : (blink ? 0.2 : 1.0))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(DS.Motion.cursorBlink) {
                    blink = true
                }
            }
            // 流式结束 / 切走会话 / view dismiss 时停掉 repeatForever — 否则 cursor 在
            // 不可见状态仍占 60Hz 重绘吃电。
            .onDisappear {
                withAnimation(.linear(duration: 0)) { blink = false }
            }
            // 装饰光标:VoiceOver 不需要读 ▍
            .accessibilityHidden(true)
    }
}
