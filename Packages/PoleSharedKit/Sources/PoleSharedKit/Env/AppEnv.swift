import SwiftUI

/// 全局应用环境对象 — 通过 `@Environment(AppEnv.self)` 注入到所有 SwiftUI View。
///
/// 本 PR 只暴露 `router`。后续 PR 增量加 `appearance` / `follow` / `motorsport` /
/// `llm` / `knowledge` / 其他全局服务。
@MainActor
@Observable
public final class AppEnv {
    public let router: AppRouter

    public init(router: AppRouter) {
        self.router = router
    }

    /// 标准 bootstrap 入口,主 app `@main` 调用一次。
    public static func bootstrap() -> AppEnv {
        AppEnv(router: AppRouter())
    }
}
