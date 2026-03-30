import SwiftData

enum DDiarySchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [BPMeasurement.self, GlucoseMeasurement.self, UserSettings.self, GoogleIntegration.self]
    }
}
