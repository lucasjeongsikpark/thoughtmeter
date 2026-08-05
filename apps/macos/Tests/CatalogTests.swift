import Foundation
import ThoughtMeterKit

/// Sanity checks on the shipped recognized catalog — a wrong entry here
/// fails safe at runtime (never detected), but should still fail loudly
/// in tests.
let catalogTests: [TC] = [
    TC("recognized domains are already normalized") { t in
        for (_, domain) in RecognizedCatalog.domains {
            t.expectEqual(DomainNormalizer.normalize(domain), domain,
                          "catalog domain '\(domain)' must normalize to itself")
        }
    },
    TC("recognized domains are unique") { t in
        let domains = RecognizedCatalog.domains.map { $0.domain }
        t.expectEqual(Set(domains).count, domains.count)
    },
    TC("recognized app bundle IDs are unique, non-empty, and not browsers") { t in
        let ids = RecognizedCatalog.apps.map { $0.bundleID }
        t.expectEqual(Set(ids).count, ids.count)
        for app in RecognizedCatalog.apps {
            t.expect(!app.bundleID.isEmpty && app.bundleID.contains("."),
                     "'\(app.displayName)' has an implausible bundle ID")
            t.expect(!RecognizedCatalog.isChrome(bundleID: app.bundleID),
                     "Chrome must never be a recognized app source")
            t.expect(!app.displayName.isEmpty)
        }
    },
    TC("display names are unique") { t in
        let names = RecognizedCatalog.apps.map { $0.displayName }
        t.expectEqual(Set(names).count, names.count)
    },
    TC("domain companion map points at recognized entries") { t in
        let domains = Set(RecognizedCatalog.domains.map { $0.domain })
        let appIDs = Set(RecognizedCatalog.apps.map { $0.bundleID })
        for (domain, bundleID) in RecognizedCatalog.domainCompanionApps {
            t.expect(domains.contains(domain), "companion key '\(domain)' is not a recognized domain")
            t.expect(appIDs.contains(bundleID), "companion value '\(bundleID)' is not a recognized app")
        }
    },
]
