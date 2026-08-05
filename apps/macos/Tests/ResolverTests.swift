import Foundation
import ThoughtMeterKit

private func makeSources() -> [SourceRecord] {
    [
        SourceRecord(id: 1, kind: .app, identifier: "com.microsoft.VSCode",
                     displayName: "Visual Studio Code", isBuiltin: true, isEnabled: true, createdAt: 0),
        SourceRecord(id: 2, kind: .app, identifier: "com.apple.Terminal",
                     displayName: "Terminal", isBuiltin: true, isEnabled: false, createdAt: 0),
        SourceRecord(id: 3, kind: .domain, identifier: "claude.ai",
                     displayName: "Claude (web)", isBuiltin: true, isEnabled: true, createdAt: 0),
        SourceRecord(id: 4, kind: .app, identifier: "com.example.customtool",
                     displayName: "Custom Tool", isBuiltin: false, isEnabled: true, createdAt: 0),
        SourceRecord(id: 5, kind: .app, identifier: "com.google.Chrome",
                     displayName: "Chrome", isBuiltin: false, isEnabled: true, createdAt: 0),
    ]
}

let resolverTests: [TC] = [
    TC("selected app resolves to its source id") { t in
        let resolver = SourceResolver(clock: { 1000 })
        resolver.updateEnabledSources(makeSources())
        t.expectEqual(resolver.resolve(frontmostBundleID: "com.microsoft.VSCode", chromeState: nil), 1)
    },
    TC("unselected and disabled apps resolve to nil") { t in
        let resolver = SourceResolver(clock: { 1000 })
        resolver.updateEnabledSources(makeSources())
        t.expectNil(resolver.resolve(frontmostBundleID: "com.unknown.app", chromeState: nil))
        t.expectNil(resolver.resolve(frontmostBundleID: "com.apple.Terminal", chromeState: nil),
                    "disabled source must not count")
    },
    TC("custom app resolves") { t in
        let resolver = SourceResolver(clock: { 1000 })
        resolver.updateEnabledSources(makeSources())
        t.expectEqual(resolver.resolve(frontmostBundleID: "com.example.customtool", chromeState: nil), 4)
    },
    TC("nil frontmost resolves to nil") { t in
        let resolver = SourceResolver(clock: { 1000 })
        resolver.updateEnabledSources(makeSources())
        t.expectNil(resolver.resolve(frontmostBundleID: nil, chromeState: nil))
    },
    TC("Chrome never counts as a generic app even if configured") { t in
        let resolver = SourceResolver(clock: { 1000 })
        resolver.updateEnabledSources(makeSources()) // includes a rogue Chrome app row (id 5)
        t.expectNil(resolver.resolve(frontmostBundleID: "com.google.Chrome", chromeState: nil),
                    "Chrome without domain state must not count")
    },
    TC("Chrome with fresh tracked domain counts toward the domain source") { t in
        let resolver = SourceResolver(clock: { 1000 })
        resolver.updateEnabledSources(makeSources())
        let state = ChromeDomainState(trackedDomain: "claude.ai", updatedAt: 990)
        t.expectEqual(resolver.resolve(frontmostBundleID: "com.google.Chrome", chromeState: state), 3)
    },
    TC("Chrome with null domain state does not count") { t in
        let resolver = SourceResolver(clock: { 1000 })
        resolver.updateEnabledSources(makeSources())
        let state = ChromeDomainState(trackedDomain: nil, updatedAt: 990)
        t.expectNil(resolver.resolve(frontmostBundleID: "com.google.Chrome", chromeState: state))
    },
    TC("Chrome with stale state does not count (fail closed)") { t in
        let resolver = SourceResolver(clock: { 10_000 })
        resolver.updateEnabledSources(makeSources())
        let state = ChromeDomainState(trackedDomain: "claude.ai", updatedAt: 100)
        t.expectNil(resolver.resolve(frontmostBundleID: "com.google.Chrome", chromeState: state))
    },
    TC("Chrome with domain not in enabled sources does not count") { t in
        let resolver = SourceResolver(clock: { 1000 })
        resolver.updateEnabledSources(makeSources())
        let state = ChromeDomainState(trackedDomain: "chatgpt.com", updatedAt: 990)
        t.expectNil(resolver.resolve(frontmostBundleID: "com.google.Chrome", chromeState: state))
    },
    TC("enabledDomains lists only enabled domain sources") { t in
        let resolver = SourceResolver(clock: { 1000 })
        resolver.updateEnabledSources(makeSources())
        t.expectEqual(resolver.enabledDomains(), ["claude.ai"])
    },
]
