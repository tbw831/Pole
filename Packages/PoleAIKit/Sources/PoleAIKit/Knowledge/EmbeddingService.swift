import Foundation
import NaturalLanguage

/// 把文本变成 [Float] 向量的服务,基于 Apple NLContextualEmbedding(iOS 17+)。
///
/// **为什么不用向量数据库**:本 app 知识库 ~300-500 chunk,客户端全量 cosine 5-30ms,
/// 引入 Pinecone/sqlite-vec 等只增加复杂度,完全不值。需要规模化时再切 ANN 索引。
///
/// **为什么用 NLContextualEmbedding**:
/// - 0 包体积(系统自带)
/// - 多语言(中/英都支持,中文质量"够用但不顶尖")
/// - Transformer-based contextual embedding,比老的 NLEmbedding(static word vectors)好得多
///
/// 中文 query 路径用 simplifiedChinese model;英文 query 用 english model。
/// 启动时一次性加载,actor 内部缓存模型 instance(NLContextualEmbedding 重复 load() 浪费)。
public actor EmbeddingService {
    public static let shared = EmbeddingService()

    private var modelZh: NLContextualEmbedding?
    private var modelEn: NLContextualEmbedding?

    public enum EmbeddingError: Error, LocalizedError {
        case modelUnavailable(String)
        case loadFailed(Error)
        case emptyText
        case noTokens

        public var errorDescription: String? {
            switch self {
            case .modelUnavailable(let lang):
                return "NLContextualEmbedding 不支持语言:\(lang)"
            case .loadFailed(let e):
                return "Embedding 模型加载失败:\(e.localizedDescription)"
            case .emptyText:
                return "Embedding 输入为空"
            case .noTokens:
                return "Embedding 没产生任何 token vector"
            }
        }
    }

    /// 给一段文本算 embedding(mean-pool 所有 token 向量到一个 sentence vector)。
    /// `language` 决定走哪个模型;含 emoji / 混用语言时仍按主语言走,效果略降但可接受。
    public func embed(_ text: String, language: NLLanguage = .simplifiedChinese) async throws -> [Float] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EmbeddingError.emptyText }

        let model = try await loadModel(for: language)
        let result: NLContextualEmbeddingResult
        do {
            result = try model.embeddingResult(for: trimmed, language: language)
        } catch {
            throw EmbeddingError.loadFailed(error)
        }

        // mean-pool:对所有 token vector 求平均。
        // NLContextualEmbeddingResult 没有 dimension 属性 — 从第一个 token vector 的 count 推断,
        // 既不用预先知道维度,也不依赖随 SDK 版本变动的 API。
        var sum: [Double] = []
        var count = 0
        result.enumerateTokenVectors(in: trimmed.startIndex..<trimmed.endIndex) { vector, _ in
            if sum.isEmpty {
                sum = Array(repeating: 0, count: vector.count)
            }
            let n = min(vector.count, sum.count)
            for i in 0..<n {
                sum[i] += vector[i]
            }
            count += 1
            return true
        }
        guard count > 0, !sum.isEmpty else { throw EmbeddingError.noTokens }
        return sum.map { Float($0 / Double(count)) }
    }

    // MARK: - 私有模型加载(actor 隔离 + 一次性 load)

    private func loadModel(for language: NLLanguage) async throws -> NLContextualEmbedding {
        // 中文相关都走 zh 模型(简繁同模型),其它走英文模型
        let isChinese = (language == .simplifiedChinese || language == .traditionalChinese)
        if isChinese {
            if let m = modelZh { return m }
            guard let m = NLContextualEmbedding(language: .simplifiedChinese) else {
                throw EmbeddingError.modelUnavailable("zh-Hans")
            }
            do { try m.load() } catch { throw EmbeddingError.loadFailed(error) }
            modelZh = m
            return m
        } else {
            if let m = modelEn { return m }
            guard let m = NLContextualEmbedding(language: .english) else {
                throw EmbeddingError.modelUnavailable("en")
            }
            do { try m.load() } catch { throw EmbeddingError.loadFailed(error) }
            modelEn = m
            return m
        }
    }
}
