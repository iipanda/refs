import Testing
@testable import RefsCore

@Suite struct SelectionTests {
    let order = ["a", "b", "c", "d", "e"]

    @Test func plainClickSelectsOneAndClickingItAgainClears() {
        var selection = Selection()
        selection.click("b", modifier: .none, order: order)
        #expect(selection.ids == ["b"])
        #expect(selection.single == "b")

        selection.click("d", modifier: .none, order: order)
        #expect(selection.ids == ["d"])

        selection.click("d", modifier: .none, order: order)
        #expect(selection.isEmpty)
        #expect(selection.anchor == nil)
    }

    @Test func plainClickOnAMemberOfAMultiSelectionNarrowsToIt() {
        var selection = Selection()
        selection.selectAll(order)
        selection.click("c", modifier: .none, order: order)
        #expect(selection.ids == ["c"])
    }

    @Test func commandClickToggles() {
        var selection = Selection()
        selection.click("a", modifier: .none, order: order)
        selection.click("c", modifier: .toggle, order: order)
        selection.click("e", modifier: .toggle, order: order)
        #expect(selection.ids == ["a", "c", "e"])
        #expect(selection.single == nil)

        selection.click("c", modifier: .toggle, order: order)
        #expect(selection.ids == ["a", "e"])
    }

    @Test func shiftClickSelectsRangeFromAnchorInEitherDirection() {
        var selection = Selection()
        selection.click("b", modifier: .none, order: order)
        selection.click("d", modifier: .extend, order: order)
        #expect(selection.ids == ["b", "c", "d"])

        // The anchor stays put, so a second shift-click re-ranges from it.
        selection.click("a", modifier: .extend, order: order)
        #expect(selection.ids == ["a", "b"])
        #expect(selection.ordered(by: order) == ["a", "b"])
    }

    @Test func shiftClickWithoutAnAnchorSelectsJustThatItem() {
        var selection = Selection()
        selection.click("c", modifier: .extend, order: order)
        #expect(selection.ids == ["c"])
        selection.click("e", modifier: .extend, order: order)
        #expect(selection.ids == ["c", "d", "e"])
    }

    @Test func setReplacesSelectionAndAnchorsAtFirstInOrder() {
        var selection = Selection()
        selection.click("a", modifier: .none, order: order)
        selection.set(["d", "b"], order: order)
        #expect(selection.ids == ["b", "d"])
        #expect(selection.anchor == "b")
        selection.click("c", modifier: .extend, order: order)
        #expect(selection.ids == ["b", "c"])

        selection.set([], order: order)
        #expect(selection.isEmpty && selection.anchor == nil)
    }

    @Test func retainDropsHiddenItemsAndStaleAnchor() {
        var selection = Selection()
        selection.click("b", modifier: .none, order: order)
        selection.click("d", modifier: .toggle, order: order)
        selection.retain(["a", "b", "c"])
        #expect(selection.ids == ["b"])
        #expect(selection.anchor == nil)
    }
}
