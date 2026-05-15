import Foundation

/// 通用 ViewModel 加载状态。配合 `LoadingViewModel` protocol 给 17 个 VM 复用。
public enum LoadingState<Value: Sendable>: Sendable {
    case idle
    case loading
    case loaded(Value)
    case failed(String)
}

/// 提供统一 `load()` 实现的 ViewModel protocol。
/// 子类实现 `loadValue()` 即可,error 处理与 cancellation 自动统一。
///
/// 用法:
/// ```swift
/// @MainActor @Observable
/// final class MyViewModel: LoadingViewModel {
///     var state: LoadingState<MyData> = .idle
///     func loadValue() async throws -> MyData {
///         try await api.fetch()
///     }
/// }
/// ```
@MainActor
public protocol LoadingViewModel: AnyObject {
    associatedtype Value: Sendable
    var state: LoadingState<Value> { get set }
    func loadValue() async throws -> Value
}

public extension LoadingViewModel {
    /// 标准加载流程:loading → loadValue() → loaded(...) | failed(message)
    /// `CancellationError` 不切到 failed,保持原态(.task cancel 时不应清空已加载内容)。
    func load() async {
        state = .loading
        do {
            let value = try await loadValue()
            state = .loaded(value)
        } catch is CancellationError {
            // 不切到 failed
        } catch {
            let poleError = PoleError.from(error)
            state = .failed(poleError.errorDescription ?? "Unknown error")
        }
    }
}
