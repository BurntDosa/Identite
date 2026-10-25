import SwiftData

public enum IDStore {
    public static let schema = Schema([Person.self, IDRecord.self])

    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        // Keep backups and iOS's Until First Unlock protection: CloudKit must reopen the store while locked.
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: inMemory ? .none : .automatic
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
