import SwiftUI
import UniformTypeIdentifiers

/// A JSON file for `fileExporter`: keystores and backups.
nonisolated struct JSONFile: FileDocument {
    static let readableContentTypes: [UTType] = [.json]

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// What's being exported, and under which name.
struct PendingExport: Identifiable {
    let id = UUID()
    let file: JSONFile
    let filename: String
}

extension URL {
    /// Reads a file picked from Files, which may live outside the sandbox.
    func readSecurityScoped() throws -> Data {
        let accessing = startAccessingSecurityScopedResource()
        defer { if accessing { stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: self)
    }
}
