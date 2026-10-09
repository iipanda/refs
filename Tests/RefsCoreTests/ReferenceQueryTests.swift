import Foundation
import Testing
@testable import RefsCore

private func ref(
    _ id: String, app: String, bundle: String? = nil, url: String? = nil, title: String? = nil, note: String = ""
) -> Reference {
    Reference(
        id: id, createdAt: Date(), imageFile: "\(id).png", pixelWidth: 1, pixelHeight: 1,
        app: SourceApp(name: app, bundleID: bundle),
        windowTitle: title,
        web: url.map { WebSource(url: $0, title: title) },
        note: note
    )
}

private let sample = [
    ref("1", app: "Safari", bundle: "com.apple.Safari", url: "https://stripe.com/payments/checkout",
        title: "Checkout | Stripe", note: "Calm gradient, pinned price summary"),
    ref("2", app: "Google Chrome", bundle: "com.google.Chrome", url: "https://dashboard.stripe.com/test",
        title: "Dashboard", note: "Dense table with muted separators"),
    ref("3", app: "Linear", bundle: "com.linear", title: "Issues", note: "Dense issue list"),
    ref("4", app: "Google Chrome", bundle: "com.google.Chrome", url: "https://vercel.com", note: "Hero restraint"),
]

@Suite struct ReferenceQueryTests {
    @Test func emptyQueryReturnsEverything() {
        #expect(ReferenceQuery().apply(to: sample).count == 4)
    }

    @Test func textMatchesAllTokensAcrossFields() {
        #expect(ReferenceQuery(text: "dense").apply(to: sample).map(\.id) == ["2", "3"])
        #expect(ReferenceQuery(text: "DENSE table").apply(to: sample).map(\.id) == ["2"])
        #expect(ReferenceQuery(text: "checkout").apply(to: sample).map(\.id) == ["1"])
        #expect(ReferenceQuery(text: "linear").apply(to: sample).map(\.id) == ["3"])
    }

    @Test func siteMatchesHostAndSubdomainsInAnyFormat() {
        #expect(ReferenceQuery(site: "stripe.com").apply(to: sample).map(\.id) == ["1", "2"])
        #expect(ReferenceQuery(site: "https://www.stripe.com/pricing").apply(to: sample).map(\.id) == ["1", "2"])
        #expect(ReferenceQuery(site: "dashboard.stripe.com").apply(to: sample).map(\.id) == ["2"])
        #expect(ReferenceQuery(site: "tripe.com").apply(to: sample).isEmpty)
    }

    @Test func appMatchesNameOrBundleID() {
        #expect(ReferenceQuery(app: "linear").apply(to: sample).map(\.id) == ["3"])
        #expect(ReferenceQuery(app: "com.google.chrome").apply(to: sample).map(\.id) == ["2", "4"])
        #expect(ReferenceQuery(app: "chrome").apply(to: sample).map(\.id) == ["2", "4"])
    }

    @Test func criteriaCombineAndLimitApplies() {
        #expect(ReferenceQuery(text: "dense", site: "stripe.com").apply(to: sample).map(\.id) == ["2"])
        #expect(ReferenceQuery(limit: 2).apply(to: sample).map(\.id) == ["1", "2"])
    }

    @Test func sourceSummaryGroupsWebByHostAndNativeByApp() {
        let summary = SourceSummary(refs: sample)
        #expect(summary.sites.map(\.name) == ["dashboard.stripe.com", "stripe.com", "vercel.com"])
        #expect(summary.apps.map(\.name) == ["Linear"])
        #expect(summary.apps[0].count == 1)
    }

    @Test func normalizedHost() {
        #expect(WebSource.normalizedHost("https://WWW.Stripe.com/x?y=1") == "stripe.com")
        #expect(WebSource.normalizedHost("linear.app") == "linear.app")
        #expect(WebSource.normalizedHost("  ") == nil)
    }
}
