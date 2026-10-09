# Spike 03: MCP server for the screenshot library

## Recommendation

- **Transport: stdio helper binary** bundled in the app (`Refs.app/Contents/MacOS/refs-mcp`). It reads the library from disk directly. It works when the menu-bar app is not running, needs no port, no auth, and no DNS-rebinding defenses. The MCP spec says clients SHOULD support stdio whenever possible. Do not run Streamable HTTP in v1.
- **Swift SDK:** use the official `modelcontextprotocol/swift-sdk` (`import MCP`, `StdioTransport`). It is pre-1.0 (0.x minor bumps may break), so pin the exact version.
- **Storage:** a folder of PNG files plus one JSON sidecar per screenshot, with the app as the only writer. Writes go to a temp file and are renamed into place, so the helper never reads a half-written file. Search is an in-memory scan over sidecars, which is fine for hundreds to low thousands of items. Move to SQLite (FTS5) only when the scan is measurably slow. SQLite with WAL across two processes is workable but adds locking and `SQLITE_BUSY` concerns that v1 does not need.
- **Images:** return an MCP `image` content block for `get_reference(include_image: true)`, downscaled to about 1024 px on the long edge and JPEG/PNG-compressed. `list_references` returns text only. Also expose the file path in the metadata so an agent can open the full-resolution file.
- **Tools (v1):** `list_references`, `get_reference`, `list_sources`. Details in section 5.

Items marked UNVERIFIED were not confirmed in the sources listed at the bottom.

---

## 1. Official Swift SDK

| Item | Finding | Status |
|---|---|---|
| Repo | `github.com/modelcontextprotocol/swift-sdk`, described in its README as the "Official Swift SDK" for MCP | Verified (README) |
| Latest version | The README install snippet shows `from: "0.11.0"`. The page does not label it as the latest release. The releases page was not readable through the fetch tool. | UNVERIFIED: check GitHub Releases before pinning |
| Maturity | Changelog: "For pre-1.0 releases, minor version increments (0.X.0) may contain breaking changes." | Verified |
| Spec version | README: "implements both client and server components according to the 2025-11-25 (latest) version of the MCP specification." | Verified |
| Server-side stdio | `StdioTransport()` with `server.start(transport:)` | Verified (README) |
| Server-side Streamable HTTP | `StatelessHTTPServerTransport` (no sessions, no SSE streaming) and `StatefulHTTPServerTransport` (sessions and SSE). Also a client `HTTPClientTransport`. | Verified (README). Not tested. |
| Platforms | Swift 6.0+ / Xcode 16+. macOS 13.0+, iOS 16+, and others. | Verified (README) |
| Resources | Server registers list, read, and subscribe handlers. | Verified (README) |
| Image content | Client side has an `.image(data, mimeType, metadata)` case. The README's server examples return only text. Server-side image return is not shown. | Image return on server: UNVERIFIED (should be the same `Tool.Content` enum, but compile and check) |
| Other forks | `DePasqualeOrg/swift-mcp` claims full 2025-11-25 support and is at 1.0.3 (March 2026). Not evaluated. | Third-party, unverified |

Spec background: the MCP spec's current transports are stdio and Streamable HTTP. Clients SHOULD support stdio whenever possible. Streamable HTTP replaces the older HTTP+SSE transport.

## 2. Transport choice

### Option A: stdio helper binary (recommended)

- The client launches `refs-mcp` as a subprocess. It speaks JSON-RPC over stdin/stdout. The spec forbids anything else on stdout, so all logs go to stderr.
- The helper reads the library folder directly. The app does not need to be running.
- No open port, no token, no Origin validation. The spec's DNS-rebinding and localhost-binding requirements apply only to HTTP.
- Each client launches its own process. The helper is stateless between calls. Read-only access means no write contention.
- Downside: the helper path is baked into client configs. If the app moves, the paths change. Use `/Applications/Refs.app/...` and document the reconfiguration step. Also, if the app is ever sandboxed for the Mac App Store, the helper must be sandboxed too and share an App Group container. This is not an issue for a direct-distributed v1.

### Option B: running app serves Streamable HTTP on localhost

- Works only while the app runs. A menu-bar app is usually running, but not guaranteed.
- Needs: bind to 127.0.0.1 only, validate `Origin` (MUST, to block DNS rebinding), and some auth (SHOULD). A random token in the client config is the simplest, which means storing a secret in each client's config file.
- Concurrency is easier (the app owns the data), but the app must answer MCP requests on the main actor or a background queue safely.
- Each client must be pointed at `http://127.0.0.1:<port>/mcp`. Port conflicts and app restarts change the endpoint unless it is fixed.
- Clients handle HTTP servers well (Claude Code `--transport http`, Codex `url`, Cursor `url`). Claude Desktop's local config expects stdio commands. Remote/custom connectors go through a different UI. (Not verified for this spike; see the Claude Desktop note below.)

### Verdict

Option A is simpler and more robust for v1. Option B is worth revisiting only if you later want live updates pushed to agents or a single process that owns writes.

### Client configuration (stdio)

Absolute path to the binary is required in all clients. Replace `/Applications/Refs.app` with the real install path.

**Claude Code** (syntax verified from the Claude Code MCP docs):
```bash
claude mcp add --transport stdio --scope user refs -- /Applications/Refs.app/Contents/MacOS/refs-mcp
```
User scope writes to `~/.claude.json`. Project scope writes `.mcp.json`.

**Codex CLI** (`~/.codex/config.toml`, format verified from the Codex MCP docs):
```toml
[mcp_servers.refs]
command = "/Applications/Refs.app/Contents/MacOS/refs-mcp"
args = []
```

**Cursor** (`~/.cursor/mcp.json` or `.cursor/mcp.json`, verified from Cursor docs summary):
```json
{
  "mcpServers": {
    "refs": {
      "type": "stdio",
      "command": "/Applications/Refs.app/Contents/MacOS/refs-mcp",
      "args": []
    }
  }
}
```

**Claude Desktop** (`~/Library/Application Support/Claude/claude_desktop_config.json`, verified from the MCP local-server guide):
```json
{
  "mcpServers": {
    "refs": {
      "command": "/Applications/Refs.app/Contents/MacOS/refs-mcp",
      "args": []
    }
  }
}
```
Restart Claude Desktop fully after editing. Logs are in `~/Library/Logs/Claude/mcp*.log`.

## 3. Returning images

- **Image content block:** MCP tool results may include `{"type":"image","data":"<base64>","mimeType":"image/png"}`. Verified (spec, tools page).
- **Claude Code behavior (verified, Claude Code MCP docs):**
  - The inline copy the model sees may be scaled down or compressed to fit model image limits.
  - Claude Code saves the original bytes to `~/.claude/projects/.../tool-results/` and gives the path. This requires Claude Code v2.1.283 or later.
  - Image results are still subject to `MAX_MCP_OUTPUT_TOKENS` (default 25,000 tokens; warning at 10,000). The docs say the file-save fallback applies only when a result has no image content.
  - Warning: the docs' image section was only partly readable. Exact token cost per image and the resize target were not stated.
- **Codex CLI:** the Codex MCP docs page did not mention image handling in tool results. UNVERIFIED whether Codex renders image blocks, and at what size.
- **Cursor and Claude Desktop:** not checked.
- **Downscale decision:** yes. Resize to about 1024 px on the long edge and JPEG or PNG-compress. Reason: full retina screenshots (2880 px wide or larger) waste context and may be rejected or compressed by clients. The exact token budget is UNVERIFIED; measure with one real Claude Code session before fixing the number.
- **Alternatives:**
  - Return a text path. Works everywhere, and agents with file access can open it. Cheap in tokens, but depends on the agent having filesystem permission.
  - MCP resource (`resource_link` with `file://` URI). The spec allows tools to return `resource_link`. Claude Code's `@server:protocol://` mentions and resource tools are documented. Use it as a complement to the path.
- **Recommended shape:** `list_references` returns text only (id, title, description, source, URL, timestamp, `image_path`, pixel size). `get_reference(include_image: true)` returns text metadata plus one downscaled image block. Default `include_image` to false.

## 4. Storage

| Option | Pros | Cons |
|---|---|---|
| Folder: PNG + JSON sidecar per item, plus optional `index.json` | No schema migrations. Atomic per-file writes (temp + rename). Helper reads files directly. Easy to inspect and back up. | Search is a scan. Concurrent writes to index need care (only app writes). |
| Single SQLite file (GRDB, FTS5) | Real full-text search and ranking. Transactions. | Cross-process access needs WAL. Per GRDB's own sharing guide, multi-process access is "difficult" and SQLITE_BUSY and file-locking issues are common. GRDB observation does not see writes from other processes. SPM setup for custom SQLite builds is not supported (FTS5 is normally available in system SQLite). |

Verified (GRDB sharing guide mirror and SQLite WAL docs): WAL allows concurrent readers and one writer. All processes must be on the same host. Every opening process needs write access to the `-shm` file.

Recommendation for v1: folder plus sidecars. Each item:
```json
{
  "id": "01J...",
  "createdAt": "2026-10-09T10:12:00Z",
  "sourceApp": "Safari",
  "sourceBundleId": "com.apple.Safari",
  "url": "https://example.com/pricing",
  "pageTitle": "Pricing",
  "description": "Pricing table with three tiers, highlighted middle card",
  "image": "01J....png",
  "pixelWidth": 2880,
  "pixelHeight": 1800
}
```
Search: lowercase substring/token match over description, pageTitle, sourceApp, url. Rank by simple score (description hit > title > url). Add FTS5 later if needed. Write the sidecar and PNG before the index, and skip sidecars that fail to parse.

## 5. Proposed v1 tool list

All tools return `isError: true` with an actionable message on bad input (spec pattern).

```jsonc
// list_references
{
  "name": "list_references",
  "description": "List saved UI screenshot references. Filter by source app, site domain, or free-text query over description, page title, and URL. Returns text only; call get_reference to see the image.",
  "inputSchema": {
    "type": "object",
    "additionalProperties": false,
    "properties": {
      "app": { "type": "string", "description": "Source app name or bundle id, case-insensitive" },
      "site": { "type": "string", "description": "Domain, e.g. example.com (matches subdomains)" },
      "query": { "type": "string", "description": "Free-text search over description, page title, URL" },
      "limit": { "type": "integer", "minimum": 1, "maximum": 100, "default": 20 }
    }
  }
}

// get_reference
{
  "name": "get_reference",
  "description": "Get one reference by id: metadata, and optionally its screenshot (downscaled image plus the full-resolution file path).",
  "inputSchema": {
    "type": "object",
    "additionalProperties": false,
    "required": ["id"],
    "properties": {
      "id": { "type": "string" },
      "include_image": { "type": "boolean", "default": false }
    }
  }
}

// list_sources
{
  "name": "list_sources",
  "description": "List source apps and sites that have references, with counts. Use to discover valid app/site filters.",
  "inputSchema": { "type": "object", "additionalProperties": false, "properties": {} }
}
```

Notes:
- Tool names fit the spec guidance (letters, digits, underscore).
- Claude Code truncates tool descriptions at 2,048 characters and defers MCP tools behind tool search by default. Keep descriptions short and put the key phrase first. Verified (Claude Code docs).
- Deferred for later: `search_by_image`, `add_reference` (writes from agents), resources listing.

## 6. Minimal server sketch

Shape only, based on the README's API names. NOT compiled. Check the exact `Tool`/`Content` signatures against the pinned SDK version.

```swift
// Package.swift: .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.11.0")
// executableTarget "refs-mcp" depends on product "MCP"; copy into Refs.app/Contents/MacOS/
import MCP
import Foundation

let libraryDir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["REFS_LIBRARY"]
    ?? NSHomeDirectory() + "/Library/Application Support/Refs")

let store = ReferenceStore(directory: libraryDir)   // reads *.json sidecars, read-only

let server = Server(
    name: "refs",
    version: "1.0.0",
    capabilities: .init(tools: .init(listChanged: false))
)

await server.withMethodHandler(ListTools.self) { _ in
    .init(tools: [listReferencesTool, getReferenceTool, listSourcesTool])
}

await server.withMethodHandler(CallTool.self) { params in
    switch params.name {
    case "list_references":
        let args = try ListArgs(params.arguments)                 // decode + validate
        let hits = store.search(app: args.app, site: args.site, query: args.query, limit: args.limit ?? 20)
        return .init(content: [.text(hits.summaryText)], isError: false)

    case "get_reference":
        let args = try GetArgs(params.arguments)
        guard let ref = store.load(id: args.id) else {
            return .init(content: [.text("No reference with id \(args.id). Use list_references.")], isError: true)
        }
        var content: [Tool.Content] = [.text(ref.metadataJSON)]
        if args.includeImage == true {
            let jpeg = try ImageDownscaler.jpeg(at: ref.imageURL, maxEdge: 1024)  // UNVERIFIED helper
            content.append(.image(data: jpeg.base64EncodedString(), mimeType: "image/jpeg", metadata: nil))
        }
        return .init(content: content, isError: false)

    default:
        return .init(content: [.text("Unknown tool \(params.name)")], isError: true)
    }
}

// stdout is the protocol channel: log only to stderr.
let transport = StdioTransport()
try await server.start(transport: transport)
await server.waitUntilCompleted()   // UNVERIFIED method name
```

Notes for the sketch: `ReferenceStore`, `ImageDownscaler`, and the arg types are app code you write. The `waitUntilCompleted` call and the `.image(data:mimeType:metadata:)` case are UNVERIFIED against the pinned SDK. Confirm with a build before relying on them.

## 7. Open items and risks

- Pin the Swift SDK version after checking GitHub Releases. Pre-1.0 means breaking changes are possible.
- Measure image token cost and the resize target in one real Claude Code session.
- Confirm Codex renders image blocks from MCP results. Not in the docs checked.
- Confirm Claude Desktop accepts a bundled-binary stdio command in the same way (docs show `npx`-style examples, path commands are standard but not separately verified).
- The helper must find the library the same way the app does. Use one shared path constant (e.g., `~/Library/Application Support/Refs`), or an env var set in each client config.
- Privacy: screenshots may contain sensitive content. Any agent with this MCP sees everything in the library. Document this and consider a per-item "exclude from agents" flag.
- Not compiled or run in this spike. All code is a sketch.

## Sources

- MCP Transports (stdio, Streamable HTTP, Origin/DNS rebinding rules): https://modelcontextprotocol.io/specification/2025-11-25/basic/transports
- MCP Tools (tool result content types, image block, isError, inputSchema): https://modelcontextprotocol.io/specification/2025-11-25/server/tools
- Connect to local MCP servers (Claude Desktop config path and format): https://modelcontextprotocol.io/docs/develop/connect-local-servers
- Official Swift SDK README: https://github.com/modelcontextprotocol/swift-sdk
- Swift SDK search results (third-party mirrors, version numbers inconsistent): https://swiftpackageregistry.com/modelcontextprotocol/swift-sdk
- Alternative Swift MCP fork (not evaluated): https://swiftpackageregistry.com/DePasqualeOrg/swift-mcp
- Claude Code MCP docs (`claude mcp add`, scopes, `.mcp.json`, output limits, image handling, tool search): https://code.claude.com/docs/en/mcp
- Codex CLI MCP docs (config.toml fields, redirected from developers.openai.com): https://learn.chatgpt.com/docs/extend/mcp?surface=cli
- Cursor MCP docs (mcp.json fields): https://cursor.com/docs/mcp
- GRDB full-text search and sharing guide (mirror, not official site): https://www.mintlify.com/groue/GRDB.swift/advanced/full-text-search and https://mintlify.com/groue/GRDB.swift/guides/sharing-a-database
- SQLite WAL documentation (mirror): https://docs.w3cub.com/sqlite/wal.html
