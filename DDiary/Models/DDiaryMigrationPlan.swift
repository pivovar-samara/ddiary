import SwiftData

// CloudKit private databases only support lightweight (additive) migrations.
// Never use .custom stages that rename/delete columns or change types.
enum DDiaryMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [DDiarySchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
