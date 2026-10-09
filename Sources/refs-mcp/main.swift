import Foundation
import RefsCore
import RefsMCP

// stdio transport: one JSON-RPC message per line on stdin, one response per line on stdout.
// Nothing else may be written to stdout; diagnostics go to stderr.

let library = LibraryLocation.resolve()
let server = MCPServer(store: LibraryStore(root: library))
FileHandle.standardError.write(Data("refs-mcp: serving \(library.path)\n".utf8))

while let line = readLine(strippingNewline: true) {
    guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
    if let response = server.handle(Data(line.utf8)) {
        FileHandle.standardOutput.write(response)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
