import Foundation
import SwiftData

/// 显式 schema 版本声明。后续破坏性 schema 改动通过 SchemaMigrationPlan 显式声明。
/// 当前 8 个 @Model 全在 PoleDomain。
public enum SchemaV1: VersionedSchema {
    public static var versionIdentifier = Schema.Version(1, 0, 0)
    public static var models: [any PersistentModel.Type] {
        [
            FollowedItem.self,
            AddedCalendarEvent.self,
            ChatSession.self,
            ChatMessage.self,
            DailyTrivia.self,
            RaceRecap.self,
            CircuitHighlight.self,
            KnowledgeChunk.self,
        ]
    }
}

/// SwiftData migration plan。本 PR 阶段只有 V1,无 migration stage。
/// 后续破坏性改动(加 / 改 / 删 @Model)走 `.lightweight(...)` 或 `.custom(...)` stage。
public enum PoleMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }
    public static var stages: [MigrationStage] = []
}
