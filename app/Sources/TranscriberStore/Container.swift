import Foundation
import SwiftData

public enum StoreContainer {

    /// The app's store, on disk in Application Support.
    ///
    /// An explicit URL rather than the default location: the default is derived
    /// from the bundle identifier, and a SwiftPM executable run outside a
    /// bundle has none -- which fails at launch rather than at build time.
    public static func make(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(TranscriberSchema.models)
        let configuration = inMemory
            ? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            : ModelConfiguration(schema: schema, url: Paths.storeURL)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Used by tests and previews. Never touches the user's data.
    public static func ephemeral() throws -> ModelContainer {
        try make(inMemory: true)
    }
}
