import Foundation

/// Filters references by free text, app and website. All given criteria must match.
public struct ReferenceQuery: Sendable {
    public var text: String?
    /// App name or bundle ID, case-insensitive.
    public var app: String?
    /// Website host such as `stripe.com`; subdomains match too (`dashboard.stripe.com`).
    public var site: String?
    public var limit: Int?

    public init(text: String? = nil, app: String? = nil, site: String? = nil, limit: Int? = nil) {
        self.text = text
        self.app = app
        self.site = site
        self.limit = limit
    }

    public func apply(to refs: [Reference]) -> [Reference] {
        let tokens = (text ?? "")
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        let appNeedle = app?.trimmingCharacters(in: .whitespaces).lowercased()
        let siteNeedle = site.flatMap(WebSource.normalizedHost)

        let matched = refs.filter { ref in
            if let appNeedle, !appNeedle.isEmpty {
                let name = ref.app.name.lowercased()
                let bundle = ref.app.bundleID?.lowercased()
                guard name == appNeedle || bundle == appNeedle || name.contains(appNeedle) else { return false }
            }
            if let siteNeedle {
                guard let host = ref.web?.host,
                      host == siteNeedle || host.hasSuffix("." + siteNeedle)
                else { return false }
            }
            if !tokens.isEmpty {
                let haystack = Self.searchableText(ref)
                guard tokens.allSatisfy(haystack.contains) else { return false }
            }
            return true
        }
        if let limit, limit >= 0 {
            return Array(matched.prefix(limit))
        }
        return matched
    }

    static func searchableText(_ ref: Reference) -> String {
        [ref.note, ref.app.name, ref.app.bundleID, ref.windowTitle, ref.web?.title, ref.web?.url]
            .compactMap { $0 }
            .joined(separator: "\n")
            .lowercased()
    }
}

/// Counts of references per source. Browser captures count under their website, everything else under its app.
public struct SourceSummary: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public var name: String
        public var bundleID: String?
        public var count: Int
    }

    public var apps: [Entry]
    public var sites: [Entry]

    public init(refs: [Reference]) {
        var apps: [String: Entry] = [:]
        var sites: [String: Entry] = [:]
        for ref in refs {
            if let host = ref.web?.host {
                sites[host, default: Entry(name: host, bundleID: nil, count: 0)].count += 1
            } else {
                let key = ref.app.bundleID ?? ref.app.name
                apps[key, default: Entry(name: ref.app.name, bundleID: ref.app.bundleID, count: 0)].count += 1
            }
        }
        let order: (Entry, Entry) -> Bool = { a, b in
            a.count != b.count ? a.count > b.count : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        self.apps = apps.values.sorted(by: order)
        self.sites = sites.values.sorted(by: order)
    }
}
