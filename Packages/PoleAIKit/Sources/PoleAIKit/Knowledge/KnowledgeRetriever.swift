import Foundation
import SwiftData
import NaturalLanguage
import PoleDomain

/// 知识库 cosine 相似度检索 — 给 RetrieveKnowledgeTool / 任何想做语义搜索的地方用。
///
/// **为什么客户端全量 cosine 而不用索引**:
/// - 500 chunk × 512 维 cosine 计算 ~5ms,token 网络往返 200ms+,全量算瓶颈不在这
/// - SwiftData @Query 没有内置向量索引,要自己写 ANN(HNSW/IVF)成本高
/// - 等到 chunk 上万再考虑 sqlite-vec 等扩展
///
/// **filter 策略**:
/// - 传 series 过滤的话,优先返该 series + 跨系列(seriesRaw=nil) chunk
/// - 不传 series 全库召回(用户问"赛车策略一般是什么样的"等通用问题)
@MainActor
public struct KnowledgeRetriever {
    let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// 一次检索结果 — 给 LLM 看的内容 + 元数据。
    public struct Hit: Sendable {
        public let chunkId: UUID
        public let text: String
        public let source: String
        public let series: String?
        public let topic: String?
        public let score: Float   // cosine similarity, [-1, 1] 实际通常 [0, 1]
    }

    /// 异步搜 top-K — 先 embed query,再 fetch + cosine + sort + take K。
    /// `series` 不传 = 全库;传则限定该 series + 跨系列(seriesRaw=nil)。
    /// `language` 决定 query embedding 模型;通常自动跟用户当前 L10n 走。
    public func search(
        query: String,
        topK: Int = 5,
        series: String? = nil,
        language: NLLanguage = .simplifiedChinese
    ) async -> [Hit] {
        // 1. embed query
        let queryVec: [Float]
        do {
            queryVec = try await EmbeddingService.shared.embed(query, language: language)
        } catch {
            return []
        }

        // 2. fetch — series filter 在 SwiftData 层做,减少内存压力
        let chunks: [KnowledgeChunk]
        if let series = series {
            let descriptor = FetchDescriptor<KnowledgeChunk>(
                predicate: #Predicate { $0.seriesRaw == series || $0.seriesRaw == nil }
            )
            chunks = (try? context.fetch(descriptor)) ?? []
        } else {
            chunks = (try? context.fetch(FetchDescriptor<KnowledgeChunk>())) ?? []
        }
        guard !chunks.isEmpty else { return [] }

        // 3. cosine 全量算 + 排序
        let scored: [(KnowledgeChunk, Float)] = chunks.compactMap { c in
            let v = c.vector
            guard v.count == queryVec.count else { return nil }
            let s = Self.cosine(queryVec, v)
            return (c, s)
        }
        let sorted = scored.sorted { $0.1 > $1.1 }
        return sorted.prefix(topK).map { (chunk, score) in
            Hit(
                chunkId: chunk.id,
                text: chunk.text,
                source: chunk.source,
                series: chunk.seriesRaw,
                topic: chunk.topic,
                score: score
            )
        }
    }

    // MARK: - Cosine 内部

    /// 标准 cosine similarity = a·b / (||a|| · ||b||)。
    /// nonisolated 让它可以在 actor / Task 里直接调用,无需 hop 到 MainActor。
    public nonisolated static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = (normA.squareRoot()) * (normB.squareRoot())
        return denom > 0 ? dot / denom : 0
    }
}
