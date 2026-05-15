import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// iOS 26 on-device Apple Intelligence backend。无网络、无 key,延迟低。
/// 仅在 SystemLanguageModel.availability == .available 时可用。
///
/// 当前为 scaffold:已暴露 `LLMProvider` 协议,主 `LLMClient` 仍走 DeepSeek。
/// 后续在确认 Apple Intelligence 在 agent tool-calling 场景下的行为后,
/// 再做完整 failover 接线。
public actor AppleIntelligenceProvider: LLMProvider {
    public static let shared = AppleIntelligenceProvider()
    private init() {}

    public var isAvailable: Bool {
        get async {
            #if canImport(FoundationModels)
            if #available(iOS 26.0, macOS 15.0, *) {
                switch SystemLanguageModel.default.availability {
                case .available:
                    return true
                default:
                    return false
                }
            }
            #endif
            return false
        }
    }

    public func generateText(systemPrompt: String, userMessage: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 15.0, *) {
            guard case .available = SystemLanguageModel.default.availability else {
                throw FallbackError.notAvailable
            }
            let session = LanguageModelSession(
                model: SystemLanguageModel.default,
                instructions: systemPrompt
            )
            let response = try await session.respond(to: userMessage)
            return response.content
        }
        #endif
        throw FallbackError.notAvailable
    }

    public enum FallbackError: Error, LocalizedError {
        case notAvailable

        public var errorDescription: String? {
            switch self {
            case .notAvailable:
                return "Apple Intelligence (FoundationModels) not available on this device / OS."
            }
        }
    }
}
