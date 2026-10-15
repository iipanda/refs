import CoreGraphics
import Foundation
import RefsCore
import Testing
@testable import Refs

@Suite struct LibraryTagsTests {
    @Test @MainActor func watcherRefreshesTagsAndMembershipFromAnotherWriter() async throws {
        let store = temporaryTagLibrary()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let ref = try addTagFixture(to: store)
        let model = LibraryModel(root: store.root)
        let writer = LibraryStore(root: store.root)

        let tag = try writer.createTag(name: "Navigation", color: .blue)
        try await eventually { model.tags == [tag] }
        _ = try writer.setTags(id: ref.id, tagIDs: [tag.id], adding: true)
        try await eventually { model.reference(id: ref.id)?.tagIDs == [tag.id] }
        #expect(model.tagReferenceCount(tag) == 1)

        let renamed = try writer.updateTag(id: tag.id, name: "Menus", color: .mint, expectedRevision: tag.revision)
        try await eventually { model.tags == [renamed] }
        let refreshed = try #require(model.reference(id: ref.id))
        #expect(model.tags(for: refreshed) == [renamed])

        _ = try writer.setTrashed(id: ref.id, trashed: true)
        try await eventually { model.trashRefs.count == 1 && model.refs.isEmpty }
        #expect(model.tagReferenceCount(renamed) == 0)
        #expect(model.tagReferenceCount(renamed, includeTrashed: true) == 1)
        #expect(model.trashRefs.first?.tagIDs == [tag.id])

        #expect(try writer.deleteTag(id: tag.id, expectedRevision: renamed.revision) == 1)
        try await eventually { model.tags.isEmpty && model.trashRefs.first?.tagIDs.isEmpty == true }
    }

    @Test @MainActor func bulkTaggingReportsStaleItemsAndKeepsSuccessfulEdits() throws {
        let store = temporaryTagLibrary()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let first = try addTagFixture(to: store)
        let second = try addTagFixture(to: store)
        let tag = try store.createTag(name: "Layout")
        let model = LibraryModel(root: store.root)
        let external = try LibraryStore(root: store.root).patch(
            id: first.id, patch: ReferencePatch(note: "Changed elsewhere"), expectedRevision: first.revision)

        model.setTag(tag, on: [first, second], adding: true)

        #expect(try store.readReference(id: first.id) == external)
        #expect(try store.readReference(id: second.id).tagIDs == [tag.id])
        #expect(try store.readReference(id: second.id).revision == second.revision + 1)
        #expect(model.libraryError?.contains(first.id) == true)
        #expect(model.refs.first(where: { $0.id == second.id })?.tagIDs == [tag.id])
    }

    @Test @MainActor func savePanelTagsApplyAndSkipTagsDeletedWhileTheDraftWasOpen() throws {
        let store = temporaryTagLibrary()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let kept = try store.createTag(name: "Layout")
        let removed = try store.createTag(name: "Motion")
        let model = LibraryModel(root: store.root)
        let draft = SaveDraft(capture: try tagCapture())
        draft.tagIDs = [kept.id, removed.id]
        _ = try store.deleteTag(id: removed.id, expectedRevision: removed.revision)
        model.reload()

        let saved = try model.add(draft)

        #expect(saved.tagIDs == [kept.id])
        #expect(try store.readReference(id: saved.id).tagIDs == [kept.id])
        #expect(model.refs.first?.id == saved.id && model.refs.first?.tagIDs == [kept.id])
    }

    @Test func tagCoverageDistinguishesAllSomeAndNone() throws {
        let tag = LibraryTag(id: "t", name: "Calm", color: .mint)
        func ref(_ tagged: Bool) -> Reference {
            Reference(id: UUID().uuidString, createdAt: Date(), imageFile: "x.png", pixelWidth: 1, pixelHeight: 1,
                      app: SourceApp(name: "A", bundleID: nil), tagIDs: tagged ? ["t"] : [])
        }
        #expect(TagCoverage(tag, in: [ref(true), ref(true)]) == .all)
        #expect(TagCoverage(tag, in: [ref(true), ref(false), ref(true)]) == .some(2))
        #expect(TagCoverage(tag, in: [ref(false)]) == .none)
    }

    @Test @MainActor func changingLibraryRootReplacesTheTagCatalog() throws {
        let first = temporaryTagLibrary()
        let second = temporaryTagLibrary()
        defer {
            try? FileManager.default.removeItem(at: first.root)
            try? FileManager.default.removeItem(at: second.root)
        }
        let tag = try first.createTag(name: "Only in the first library")
        let model = LibraryModel(root: first.root)
        #expect(model.tags == [tag])
        model.changeRoot(second.root)
        #expect(model.tags.isEmpty)
        #expect(model.refs.isEmpty && model.trashRefs.isEmpty)
    }
}

private func temporaryTagLibrary() -> LibraryStore {
    LibraryStore(root: FileManager.default.temporaryDirectory
        .appendingPathComponent("refs-app-tags-\(UUID().uuidString)", isDirectory: true))
}

private func addTagFixture(to store: LibraryStore) throws -> Reference {
    let context = try #require(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let image = try #require(context.makeImage())
    let png = try #require(ImageCoding.pngData(from: image))
    return try store.add(pngData: png, pixelWidth: 2, pixelHeight: 2,
        app: SourceApp(name: "Tag fixture", bundleID: nil), windowTitle: nil, web: nil, note: "")
}

private func tagCapture() throws -> CaptureResult {
    let context = try #require(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    return CaptureResult(image: try #require(context.makeImage()), scale: 1,
                         app: SourceApp(name: "Tag fixture", bundleID: nil), windowTitle: nil, web: nil,
                         frame: .zero, sourceWindow: nil, sourceWindowIsFrontmostOfApp: false)
}

@MainActor private func eventually(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(3)
    while !condition(), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(condition(), "The Library model did not refresh after an external write")
}
