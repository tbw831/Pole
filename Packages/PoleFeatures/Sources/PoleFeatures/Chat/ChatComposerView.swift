import SwiftUI
import PoleDesignSystem
import PoleDomain
import PoleSpeechKit

// MARK: - 底部输入区(文本框 + 麦克风 + 字数提示 + 听写状态条)
//
// 由 ChatView 顶层 VStack 挂在 chatList / starterView 下面。把视觉细节(权限提示条、
// listening 状态条、字数计数、Liquid Glass tint)集中到这一个 view,
// ChatView.swift 只剩"top-level 路由"。

public struct ChatComposerView: View {
    /// 直接绑 ChatViewModel,避免再多套一层 closure。
    /// canSend / input / isThinking 都从这里读;send 走 vm.send(),无需 view 传 callback。
    @Bindable var viewModel: ChatViewModel
    /// 跟 ChatView 共享的 SpeechService 单例(view 持有 @State,通过参数下传)。
    let speech: SpeechService
    /// 触发触觉反馈 + 同 view 间状态:发送按钮点击计数器(view 持有 @State,改了就震)。
    @Binding var sendCounter: Int

    public var body: some View {
        // canSend 已上提到 vm.canSend,view 不再自己 trim 字符串。
        let canSend = viewModel.canSend
        let charCount = viewModel.input.count
        let charLimit = 500

        VStack(spacing: DS.Spacing.xs) {
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
                    get: { viewModel.input },
                    set: { viewModel.input = $0 }
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
                    Task { await viewModel.send() }
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
                .disabled(viewModel.isThinking)
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

public struct PressableButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(DS.Motion.press, value: configuration.isPressed)
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
