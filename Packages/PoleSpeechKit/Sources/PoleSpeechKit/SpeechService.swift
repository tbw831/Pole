import Foundation
import PoleDomain

#if os(iOS)
import Speech
import AVFoundation

/// 语音输入服务 — Speech framework + AVAudioEngine 封装。
///
/// 设计:
/// - `@MainActor @Observable` 单例:Listening 状态 / 实时 transcript / 错误提示由 ChatView 直接观察
/// - 点击切换模式(豆包同款):再次点 mic 停止;停止后 transcript 留在输入框,用户可编辑后发
/// - 中英语种跟随 `L10n.effective`,初次启用和切语言时重建 recognizer
/// - 权限分两层:麦克风 (AVAudioApplication) + 语音识别 (SFSpeechRecognizer);任一失败给中文友好提示
/// - **不上传音频**:SFSpeechRecognitionRequest.requiresOnDeviceRecognition = true(若设备支持),
///   保证用户隐私(说明文案也是这么说的)
@MainActor
@Observable
public final class SpeechService {

    public static let shared = SpeechService()

    // MARK: 公开状态(给 UI 观察)

    /// 当前是否在听写。
    public private(set) var isListening: Bool = false

    /// 实时转写结果(partial + final),UI 拿来填到输入框。
    public private(set) var transcript: String = ""

    /// 错误 / 状态提示文案(权限拒绝、识别失败等);nil 表示一切正常。
    public private(set) var errorMessage: String?

    // MARK: 内部状态

    private let audioEngine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    /// 当 transcript 切语种时,记录当前 locale 避免每次都重建 recognizer。
    private var currentLocaleId: String?

    private init() {}

    // MARK: - 公开 API

    /// 切换 listening 状态:开始 / 停止。
    public func toggle() async {
        if isListening {
            stop()
        } else {
            await start()
        }
    }

    /// 强制停止(切换 tab / 退出 view 时调)。
    public func stop() {
        guard isListening else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        deactivateAudioSession()
        isListening = false
    }

    /// 清空状态(用户发出后或新会话时调)。
    public func reset() {
        stop()
        transcript = ""
        errorMessage = nil
    }

    // MARK: - 核心:开始 listening

    private func start() async {
        errorMessage = nil
        transcript = ""

        // 1. 权限链:麦克风 → 语音识别
        guard await ensureMicrophonePermission() else {
            errorMessage = L10n.t(zh: "请到系统设置开启麦克风权限",
                                   en: "Enable microphone access in Settings")
            return
        }
        guard await ensureSpeechAuthorization() else {
            errorMessage = L10n.t(zh: "请到系统设置开启语音识别权限",
                                   en: "Enable speech recognition in Settings")
            return
        }

        // 2. 准备 recognizer(按 L10n 切 locale)
        let preferredId = L10n.effective == .en ? "en-US" : "zh-CN"
        if recognizer == nil || currentLocaleId != preferredId {
            recognizer = SFSpeechRecognizer(locale: Locale(identifier: preferredId))
            currentLocaleId = preferredId
        }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = L10n.t(zh: "语音识别暂不可用,稍后再试",
                                   en: "Speech recognition unavailable, try later")
            return
        }

        // 3. 配置 audio session(.record + .duckOthers 避免和音乐打架)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = L10n.t(zh: "音频会话配置失败:\(error.localizedDescription)",
                                   en: "Audio session failed: \(error.localizedDescription)")
            return
        }

        // 4. 建 recognition request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // 设备支持时优先用本地识别,不上传音频(隐私 + 离线可用)
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request

        // 5. 安装 audio tap
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        // 6. 启动 audio engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            errorMessage = L10n.t(zh: "麦克风启动失败:\(error.localizedDescription)",
                                   en: "Microphone failed: \(error.localizedDescription)")
            cleanupAfterFailure()
            return
        }

        // 7. 启动 recognition task(回调在 main actor 上)
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.stop()
                    }
                }
                if let error {
                    let nsErr = error as NSError
                    // 用户主动 cancel 不算错误(domain=kAFAssistantErrorDomain code=216/203 等是常见取消)
                    if !self.isCancellationError(nsErr) {
                        self.errorMessage = L10n.t(
                            zh: "识别失败:\(error.localizedDescription)",
                            en: "Recognition failed: \(error.localizedDescription)"
                        )
                    }
                    self.stop()
                }
            }
        }

        isListening = true
    }

    private func cleanupAfterFailure() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        deactivateAudioSession()
        isListening = false
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func isCancellationError(_ err: NSError) -> Bool {
        // SFSpeechRecognizer 取消时常见错误码,不当成"识别失败"提示用户
        if err.domain == "kAFAssistantErrorDomain" {
            return [203, 209, 216, 1101, 1700].contains(err.code)
        }
        return err.domain == NSCocoaErrorDomain && err.code == NSUserCancelledError
    }

    // MARK: - 权限

    private func ensureMicrophonePermission() async -> Bool {
        let status = AVAudioApplication.shared.recordPermission
        switch status {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await AVAudioApplication.requestRecordPermission()
        @unknown default:
            return false
        }
    }

    private func ensureSpeechAuthorization() async -> Bool {
        let status = SFSpeechRecognizer.authorizationStatus()
        switch status {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                SFSpeechRecognizer.requestAuthorization { newStatus in
                    cont.resume(returning: newStatus == .authorized)
                }
            }
        @unknown default:
            return false
        }
    }
}

#endif
