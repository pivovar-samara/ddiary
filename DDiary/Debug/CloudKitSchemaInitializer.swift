//
//  CloudKitSchemaInitializer.swift
//  DDiary
//

#if DEBUG
import CoreData
import Foundation
import OSLog
import SwiftData

/// Pushes every record type and field of the SwiftData model into the CloudKit **Development**
/// schema, so it can then be deployed to Production from CloudKit Console.
///
/// Development only creates a field when a record carrying a non-nil value for it is saved, so
/// optional fields that are always `nil` locally (e.g. `googleLastError`) never show up on their
/// own. `initializeCloudKitSchema()` uploads fully populated sample records and deletes them.
///
/// Opt-in with the `-initCloudKitSchema` launch argument on a Debug build signed into iCloud.
/// It uses a throwaway store file, so the user's local data is never touched.
enum CloudKitSchemaInitializer {
    static let launchArgument = "-initCloudKitSchema"

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DDiary",
        category: "CloudKitSchemaInitializer"
    )

    static func runIfRequested(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        containerIdentifier: String
    ) {
        guard arguments.contains(launchArgument) else { return }

        let storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CloudKitSchemaInit-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storeDirectory) }

        do {
            try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
            try autoreleasepool {
                guard let model = NSManagedObjectModel.makeManagedObjectModel(for: DDiarySchemaV1.models) else {
                    logger.error("Could not build an NSManagedObjectModel from DDiarySchemaV1")
                    return
                }
                let description = NSPersistentStoreDescription(
                    url: storeDirectory.appendingPathComponent("SchemaInit.store")
                )
                description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                    containerIdentifier: containerIdentifier
                )
                description.shouldAddStoreAsynchronously = false

                let container = NSPersistentCloudKitContainer(name: "SchemaInit", managedObjectModel: model)
                container.persistentStoreDescriptions = [description]

                var loadError: Error?
                container.loadPersistentStores { _, error in loadError = error }
                if let loadError { throw loadError }

                try container.initializeCloudKitSchema(options: [])

                for store in container.persistentStoreCoordinator.persistentStores {
                    try container.persistentStoreCoordinator.remove(store)
                }
            }
            logger.notice("CloudKit Development schema initialized for \(containerIdentifier, privacy: .public)")
        } catch {
            logger.error("CloudKit schema initialization failed. error=\(String(describing: error), privacy: .public)")
        }
    }
}
#endif
