import Foundation
import Testing
@testable import RefsCore

@Suite struct TagTests {
    @Test func taglessLibrariesAndLegacySidecarsLoadWithoutMigrationWrites() throws {
        let store = makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: store.root) }
        #expect(try store.readTags().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.root.path))

        try store.ensureExists()
        let sidecar = store.root.appendingPathComponent("legacy.json")
        let json = Data("""
        {"id":"legacy","createdAt":"2026-10-10T00:00:00Z","imageFile":"legacy.png","pixelWidth":1,"pixelHeight":1,"app":{"name":"Test"},"description":"Original note"}
        """.utf8)
        try json.write(to: sidecar)
        try #require(ImageCoding.pngData(from: solidImage(width: 1, height: 1)))
            .write(to: store.root.appendingPathComponent("legacy.png"))

        let reference = try #require(store.readAll().first)
        #expect(reference.id == "legacy" && reference.tagIDs.isEmpty && reference.revision == 1)
        #expect(try store.readTags().isEmpty)
        #expect(try Data(contentsOf: sidecar) == json)
        #expect(!FileManager.default.fileExists(atPath: store.root.appendingPathComponent("tags.json").path))
    }

    @Test func catalogRoundTripsAndDefaultsUseThePaletteBeforeRepeating() throws {
        let store = makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let expectedColors: [TagColor] = [.red, .orange, .yellow, .green, .mint, .teal,
                                         .blue, .indigo, .purple, .pink, .brown, .gray]
        #expect(TagColor.allCases == expectedColors)

        var tags: [LibraryTag] = []
        for index in expectedColors.indices {
            tags.append(try store.createTag(name: "  Collection \(index) \n"))
        }
        #expect(tags.map(\.color) == expectedColors)
        #expect(tags.map(\.name) == expectedColors.indices.map { "Collection \($0)" })
        #expect(tags.allSatisfy { $0.revision == 1 && !$0.id.isEmpty })
        #expect(Set(tags.map(\.id)).count == tags.count)
        let repeated = try store.createTag(name: "Another collection")
        #expect(repeated.color == .red)
        let explicit = try store.createTag(name: "Chosen color", color: .purple)
        #expect(explicit.color == .purple)

        let reopened = LibraryStore(root: store.root)
        let loaded = try reopened.readTags()
        #expect(Set(loaded.map(\.id)) == Set((tags + [repeated, explicit]).map(\.id)))
        for tag in tags + [repeated, explicit] {
            let saved = try #require(loaded.first { $0.id == tag.id })
            #expect(saved.name == tag.name && saved.color == tag.color && saved.revision == tag.revision)
        }
        #expect(FileManager.default.fileExists(atPath: store.root.appendingPathComponent("tags.json").path))
        #expect(try store.readAll(includeTrashed: true).isEmpty)
    }

    @Test func namesAreTrimmedUniqueAndNonempty() throws {
        let store = makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let tag = try store.createTag(name: "  Checkout  ", color: .blue)
        #expect(tag.name == "Checkout")
        do {
            _ = try store.createTag(name: "\ncheckout\t", color: .red)
            Issue.record("A duplicate tag name was accepted")
        } catch LibraryError.duplicateTagName(let name) {
            #expect(name.lowercased() == "checkout")
        }
        #expect(throws: (any Error).self) { try store.createTag(name: " \n\t ") }
        let other = try store.createTag(name: "Tables")
        #expect(throws: (any Error).self) { try store.updateTag(id: other.id, name: "CHECKOUT") }
        #expect(throws: (any Error).self) { try store.updateTag(id: other.id, name: "\n ") }
        #expect(try store.readTags().count == 2)
        let unchanged = try #require(store.readTags().first { $0.id == other.id })
        #expect(unchanged.name == "Tables" && unchanged.revision == other.revision)
        #expect(TagColor(rawValue: "ultraviolet") == nil)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(TagColor.self, from: Data("\"ultraviolet\"".utf8))
        }
    }

    @Test func renamingAndRecoloringKeepTheIDAndLeaveReferenceSidecarsUntouched() throws {
        let store = makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let tag = try store.createTag(name: "Checkout", color: .blue)
        let reference = try addTagFixture(to: store)
        let tagged = try store.setTags(id: reference.id, tagIDs: [tag.id], adding: true)
        let sidecar = store.root.appendingPathComponent("\(reference.id).json")
        let before = try Data(contentsOf: sidecar)

        let renamed = try store.updateTag(id: tag.id, name: "  Purchase flow\n", expectedRevision: 1)
        #expect(renamed.id == tag.id && renamed.name == "Purchase flow" && renamed.color == .blue)
        #expect(renamed.revision == 2)
        let recolored = try store.updateTag(id: tag.id, color: .pink, expectedRevision: 2)
        #expect(recolored.id == tag.id && recolored.name == "Purchase flow" && recolored.color == .pink)
        #expect(recolored.revision == 3)
        #expect(try Data(contentsOf: sidecar) == before)
        #expect(try store.readReference(id: reference.id) == tagged)

        let noChange = try store.updateTag(id: tag.id, name: "Purchase flow", color: .pink, expectedRevision: 3)
        #expect(noChange.revision == 3)
        #expect(try store.updateTag(id: tag.id, expectedRevision: 3).revision == 3)
    }

    @Test func staleTagEditsAndDeletionDoNotClobberTheCatalogOrReferences() throws {
        let store = makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let tag = try store.createTag(name: "Checkout", color: .blue)
        let reference = try addTagFixture(to: store)
        let tagged = try store.setTags(id: reference.id, tagIDs: [tag.id], adding: true)
        let current = try store.updateTag(id: tag.id, name: "Purchase flow", expectedRevision: 1)
        do {
            _ = try store.updateTag(id: tag.id, color: .red, expectedRevision: 1)
            Issue.record("A stale tag update succeeded")
        } catch LibraryError.tagConflict(let conflict) {
            #expect(conflict.id == current.id && conflict.revision == 2 && conflict.name == "Purchase flow")
        }
        do {
            _ = try store.deleteTag(id: tag.id, expectedRevision: 1)
            Issue.record("A stale tag deletion succeeded")
        } catch LibraryError.tagConflict(let conflict) {
            #expect(conflict.id == current.id && conflict.revision == 2)
        }
        #expect(try store.readReference(id: reference.id) == tagged)
        let saved = try #require(store.readTags().first)
        #expect(saved.name == current.name && saved.color == current.color && saved.revision == current.revision)
    }

    @Test func addingAndRemovingTagsIsIdempotentAndRejectsUnknownIDsBeforeWriting() throws {
        let store = makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let first = try store.createTag(name: "Checkout")
        let second = try store.createTag(name: "Typography")
        let reference = try addTagFixture(to: store)
        let tagged = try store.setTags(id: reference.id, tagIDs: [first.id, first.id], adding: true, expectedRevision: 1)
        #expect(tagged.tagIDs == [first.id] && tagged.revision == 2)
        #expect(try store.setTags(id: reference.id, tagIDs: [first.id], adding: true) == tagged)
        let both = try store.setTags(id: reference.id, tagIDs: [second.id], adding: true)
        #expect(Set(both.tagIDs) == Set([first.id, second.id]) && both.revision == 3)
        do {
            _ = try store.setTags(id: reference.id, tagIDs: [first.id, "unknown-tag"], adding: false)
            Issue.record("An unknown tag was accepted")
        } catch LibraryError.unknownTag(let id) { #expect(id == "unknown-tag") }
        #expect(try store.readReference(id: reference.id) == both)
        let removed = try store.setTags(id: reference.id, tagIDs: [first.id], adding: false)
        #expect(removed.tagIDs == [second.id] && removed.revision == 4)
        #expect(try store.setTags(id: reference.id, tagIDs: [first.id], adding: false) == removed)
        #expect(try store.setTags(id: reference.id, tagIDs: [], adding: true) == removed)

        let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf:
            store.root.appendingPathComponent("\(reference.id).json"))) as? [String: Any])
        #expect(json["tagIDs"] as? [String] == [second.id])
    }

    @Test func tagEditsShareReferenceRevisionChecksWithMetadataAndWholeRecordWrites() throws {
        let store = makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let tag = try store.createTag(name: "Checkout")
        let reference = try addTagFixture(to: store)
        let edited = try store.patch(id: reference.id, patch: ReferencePatch(note: "Fresh note"), expectedRevision: 1)
        do {
            _ = try store.setTags(id: reference.id, tagIDs: [tag.id], adding: true, expectedRevision: 1)
            Issue.record("A stale reference tag edit succeeded")
        } catch LibraryError.conflict(let current) { #expect(current == edited) }
        let tagged = try store.setTags(id: reference.id, tagIDs: [tag.id], adding: true, expectedRevision: 2)
        #expect(tagged.note == "Fresh note" && tagged.revision == 3)
        var stale = edited
        stale.note = "Stale note"
        do {
            try store.update(stale)
            Issue.record("A stale whole-record write succeeded")
        } catch LibraryError.conflict(let current) { #expect(current == tagged) }
        #expect(try store.readReference(id: reference.id) == tagged)

        var invalid = tagged
        invalid.tagIDs = ["unknown-tag"]
        do {
            try store.update(invalid)
            Issue.record("A whole-record write accepted an unknown tag")
        } catch LibraryError.unknownTag(let id) { #expect(id == "unknown-tag") }
        #expect(try store.readReference(id: reference.id) == tagged)
    }

    @Test func trashKeepsTagsAndDeletionCleansActiveTrashedAndMissingMediaSidecars() throws {
        let store = makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let deleted = try store.createTag(name: "Checkout")
        let retained = try store.createTag(name: "Typography")
        let active = try addTagFixture(to: store)
        let trashed = try addTagFixture(to: store)
        let orphan = try addTagFixture(to: store)
        for reference in [active, trashed, orphan] {
            _ = try store.setTags(id: reference.id, tagIDs: [deleted.id, retained.id], adding: true)
        }
        let inTrash = try store.setTrashed(id: trashed.id, trashed: true)
        #expect(Set(inTrash.tagIDs) == Set([deleted.id, retained.id]))
        try FileManager.default.removeItem(at: store.imageURL(for: orphan))
        #expect(try store.readAll(includeTrashed: true).count == 2)
        #expect(try store.tagReferenceCount(id: deleted.id) == 3)
        #expect(try store.tagReferenceCount(id: deleted.id, includeTrashed: false) == 2)

        #expect(try store.deleteTag(id: deleted.id, expectedRevision: 1) == 3)
        #expect(try store.readTags().map(\.id) == [retained.id])
        for reference in [active, trashed, orphan] {
            let cleaned = try store.readReference(id: reference.id)
            #expect(cleaned.tagIDs == [retained.id])
            #expect(cleaned.revision == (reference.id == trashed.id ? 4 : 3))
        }
        let restored = try store.setTrashed(id: trashed.id, trashed: false)
        #expect(restored.tagIDs == [retained.id])
        #expect(FileManager.default.fileExists(atPath: store.imageURL(for: active).path))
        #expect(FileManager.default.fileExists(atPath: store.imageURL(for: trashed).path))
        #expect(!FileManager.default.fileExists(atPath: store.imageURL(for: orphan).path))
    }

    @Test func deletingUnusedOrUnknownTagsHasExplicitResults() throws {
        let store = makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let tag = try store.createTag(name: "Unused")
        #expect(try store.deleteTag(id: tag.id) == 0)
        #expect(try store.readTags().isEmpty)
        do {
            _ = try store.deleteTag(id: tag.id)
            Issue.record("An unknown tag deletion succeeded")
        } catch LibraryError.unknownTag(let id) { #expect(id == tag.id) }
        do {
            _ = try store.updateTag(id: "missing-tag", name: "New name")
            Issue.record("An unknown tag update succeeded")
        } catch LibraryError.unknownTag(let id) { #expect(id == "missing-tag") }
    }

    @Test func queriesFilterByTagIDOrNameAndSearchAcrossTagNamesAndMetadata() throws {
        let store = makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let checkout = try store.createTag(name: "Purchase flow")
        let typography = try store.createTag(name: "Typography")
        let first = try addTagFixture(to: store, note: "Calm spacing")
        let second = try addTagFixture(to: store, note: "Dense table")
        let third = try addTagFixture(to: store, note: "Purchase flow without a tag")
        _ = try store.setTags(id: first.id, tagIDs: [checkout.id, typography.id], adding: true)
        _ = try store.setTags(id: second.id, tagIDs: [typography.id], adding: true)
        let refs = try store.readAll()
        let tags = try store.readTags()
        #expect(ReferenceQuery(tag: checkout.id).apply(to: refs, tags: tags).map(\.id) == [first.id])
        #expect(ReferenceQuery(tag: "  PURCHASE FLOW \n").apply(to: refs, tags: tags).map(\.id) == [first.id])
        #expect(ReferenceQuery(tag: "Purchase").apply(to: refs, tags: tags).isEmpty)
        #expect(ReferenceQuery(tag: "unknown-tag").apply(to: refs, tags: tags).isEmpty)
        #expect(Set(ReferenceQuery(text: "purchase flow").apply(to: refs, tags: tags).map(\.id)) == Set([first.id, third.id]))
        #expect(ReferenceQuery(text: "typography calm", app: "Test", tag: checkout.id).apply(to: refs, tags: tags).map(\.id) == [first.id])
        #expect(ReferenceQuery(text: "dense", tag: checkout.id).apply(to: refs, tags: tags).isEmpty)
        #expect(ReferenceQuery(tag: typography.id, limit: 1).apply(to: refs, tags: tags).count == 1)
    }

    @Test func separateStoresAddTagsConcurrentlyWithoutLosingOtherAssignments() async throws {
        let store = makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let reference = try addTagFixture(to: store)
        var tags: [LibraryTag] = []
        for index in 0..<12 { tags.append(try store.createTag(name: "Collection \(index)")) }
        let ids = tags.map(\.id)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask {
                    let writer = LibraryStore(root: store.root)
                    _ = try writer.setTags(id: reference.id, tagIDs: [id], adding: true)
                }
            }
            try await group.waitForAll()
        }
        let tagged = try store.readReference(id: reference.id)
        #expect(Set(tagged.tagIDs) == Set(ids))
        #expect(tagged.revision == ids.count + 1)
    }

    @Test func separateStoresCreateCatalogEntriesConcurrentlyWithoutLosingTags() async throws {
        let store = makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let names = (0..<12).map { "Collection \($0)" }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for name in names {
                group.addTask {
                    _ = try LibraryStore(root: store.root).createTag(name: name)
                }
            }
            try await group.waitForAll()
        }
        let saved = try store.readTags()
        #expect(Set(saved.map(\.name)) == Set(names))
        #expect(Set(saved.map(\.id)).count == names.count)
        #expect(Set(saved.map(\.color)).count == TagColor.allCases.count)
    }

    @Test func competingTagCatalogRevisionsHaveOneWinner() async throws {
        let store = makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let tag = try store.createTag(name: "Original")
        let wins = await withTaskGroup(of: Bool.self) { group in
            for index in 0..<12 {
                group.addTask {
                    let writer = LibraryStore(root: store.root)
                    do {
                        _ = try writer.updateTag(id: tag.id, name: "Writer \(index)", expectedRevision: 1)
                        return true
                    } catch { return false }
                }
            }
            var count = 0
            for await succeeded in group where succeeded { count += 1 }
            return count
        }
        #expect(wins == 1)
        let current = try #require(store.readTags().first { $0.id == tag.id })
        #expect(current.revision == 2 && current.name.hasPrefix("Writer "))
    }
}

private func addTagFixture(to store: LibraryStore, note: String = "") throws -> Reference {
    try store.add(pngData: #require(ImageCoding.pngData(from: solidImage(width: 4, height: 4))),
        pixelWidth: 4, pixelHeight: 4, app: SourceApp(name: "Test", bundleID: nil),
        windowTitle: nil, web: nil, note: note)
}
