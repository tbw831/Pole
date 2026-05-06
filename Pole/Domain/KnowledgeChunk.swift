import Foundation
import SwiftData

/// RAG 知识库的一条 chunk。
///
/// 存储:启动时由 `KnowledgeImporter` 把 `Resources/Knowledge/*.md` 切 chunk + embed 入库。
/// 检索:`KnowledgeRetriever` 用 cosine similarity 在 client 端排 top-K(无需向量数据库,
/// 500-5000 chunk 全量算 cosine ~5-30ms,远低于网络往返,iPhone 14 Pro 实测够用)。
///
/// 跟 ChatMessage 等 @Model 一起注册进 PoleApp.sharedModelContainer 的 Schema。
@Model
final class KnowledgeChunk {
    @Attribute(.unique) var id: UUID
    var text: String              // chunk 原文(给 LLM 看的内容)
    var source: String            // "F1/rules.md#drs"-类似面包屑,显示给用户/调试用
    var seriesRaw: String?        // "f1"/"motogp"/"wsbk"/"fe"/nil(跨系列通用)
    var topic: String?            // "rules"/"circuit"/"history"/"strategy" 用于 filter 不同主题
    /// 向量(Float32 序列化)— Apple NLContextualEmbedding 维度通常 512;
    /// 用 Float 而非 Double 节省 50% 存储,cosine 精度足够。
    /// 500 chunk × 512 维 × 4 bytes = 1MB,完全可接受。
    var vectorData: Data
    var createdAt: Date

    init(
        id: UUID = UUID(),
        text: String,
        source: String,
        seriesRaw: String? = nil,
        topic: String? = nil,
        vectorData: Data,
        createdAt: Date = .now
    ) {
        self.id = id
        self.text = text
        self.source = source
        self.seriesRaw = seriesRaw
        self.topic = topic
        self.vectorData = vectorData
        self.createdAt = createdAt
    }

    /// 反序列化 vectorData → [Float]。每次读会 alloc 新 array,fetch 后建议
    /// 在 retriever 内一次性转换避免反复 unsafeBytes。
    var vector: [Float] {
        vectorData.withUnsafeBytes { buf -> [Float] in
            let count = buf.count / MemoryLayout<Float>.size
            let floatBuf = buf.bindMemory(to: Float.self)
            return Array(floatBuf.prefix(count))
        }
    }

    /// 序列化 [Float] → Data — Importer 写入时用。
    static func encodeVector(_ v: [Float]) -> Data {
        v.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
