import Foundation
import ThoughtMeterKit

let domainTests: [TC] = [
    TC("normalizes simple hostnames") { t in
        t.expectEqual(DomainNormalizer.normalize("claude.ai"), "claude.ai")
        t.expectEqual(DomainNormalizer.normalize("ChatGPT.com"), "chatgpt.com")
        t.expectEqual(DomainNormalizer.normalize("  claude.ai  "), "claude.ai")
    },
    TC("strips www prefix") { t in
        t.expectEqual(DomainNormalizer.normalize("www.example.com"), "example.com")
        t.expectEqual(DomainNormalizer.normalize("WWW.Example.COM"), "example.com")
    },
    TC("accepts full URLs as user input, reduces to hostname") { t in
        t.expectEqual(DomainNormalizer.normalize("https://claude.ai/chat/abc?q=1#x"), "claude.ai")
        t.expectEqual(DomainNormalizer.normalize("http://www.chatgpt.com/"), "chatgpt.com")
        t.expectEqual(DomainNormalizer.normalize("https://claude.ai:443/chat"), "claude.ai")
    },
    TC("URL embedded in a path/query is not mistaken for the scheme") { t in
        t.expectEqual(DomainNormalizer.normalize("example.com/login?next=https://evil.com"), "example.com")
        t.expectEqual(DomainNormalizer.normalize("example.com?u=https://x.test"), "example.com")
    },
    TC("rejects invalid hostnames") { t in
        t.expectNil(DomainNormalizer.normalize(""))
        t.expectNil(DomainNormalizer.normalize("   "))
        t.expectNil(DomainNormalizer.normalize("localhost"), "single label rejected")
        t.expectNil(DomainNormalizer.normalize("has space.com"))
        t.expectNil(DomainNormalizer.normalize("user@evil.com"))
        t.expectNil(DomainNormalizer.normalize("bad..com"))
        t.expectNil(DomainNormalizer.normalize("-bad.com"))
        t.expectNil(DomainNormalizer.normalize("bad-.com"))
        t.expectNil(DomainNormalizer.normalize("claude.ai:notaport"))
        t.expectNil(DomainNormalizer.normalize(String(repeating: "a", count: 300) + ".com"))
    },
    TC("trailing dot removed") { t in
        t.expectEqual(DomainNormalizer.normalize("claude.ai."), "claude.ai")
    },
    TC("exact domain matches") { t in
        t.expect(DomainNormalizer.matches(host: "claude.ai", selectedDomain: "claude.ai"))
    },
    TC("subdomain matches, lookalike does not") { t in
        t.expect(DomainNormalizer.matches(host: "chat.claude.ai", selectedDomain: "claude.ai"))
        t.expect(!DomainNormalizer.matches(host: "notclaude.ai", selectedDomain: "claude.ai"),
                 "suffix without dot boundary must not match")
        t.expect(!DomainNormalizer.matches(host: "claude.ai.evil.com", selectedDomain: "claude.ai"),
                 "selected domain embedded mid-hostname must not match")
    },
    TC("canonical selected domain: longest match wins") { t in
        let selected = ["claude.ai", "chat.claude.ai"]
        t.expectEqual(DomainNormalizer.canonicalSelectedDomain(forHost: "chat.claude.ai", in: selected), "chat.claude.ai")
        t.expectEqual(DomainNormalizer.canonicalSelectedDomain(forHost: "claude.ai", in: selected), "claude.ai")
        t.expectNil(DomainNormalizer.canonicalSelectedDomain(forHost: "example.com", in: selected))
    },
]

let extensionIDTests: [TC] = [
    TC("accepts real extension IDs (32 letters a–p)") { t in
        t.expect(ChromeExtensionID.isPlausible("omhnbpfiapchifodmobgeglhgpgolmhn"), "the store ID is valid")
        t.expect(ChromeExtensionID.isPlausible(String(repeating: "a", count: 32)))
        t.expect(ChromeExtensionID.isPlausible(String(repeating: "p", count: 32)))
    },
    TC("rejects wrong lengths") { t in
        t.expect(!ChromeExtensionID.isPlausible(""))
        t.expect(!ChromeExtensionID.isPlausible(String(repeating: "a", count: 31)))
        t.expect(!ChromeExtensionID.isPlausible(String(repeating: "a", count: 33)))
    },
    TC("rejects characters outside a–p") { t in
        t.expect(!ChromeExtensionID.isPlausible(String(repeating: "q", count: 32)), "q is past the alphabet")
        t.expect(!ChromeExtensionID.isPlausible(String(repeating: "A", count: 32)), "uppercase rejected")
        t.expect(!ChromeExtensionID.isPlausible(String(repeating: "1", count: 32)), "digits rejected")
        t.expect(!ChromeExtensionID.isPlausible("abcdefgh ijklmnopabcdefghijklmno"), "embedded space rejected (32 chars)")
        t.expect(!ChromeExtensionID.isPlausible("chrome-extension://omhnbpfiapchif"), "pasted URL fragment rejected")
    },
]

let chromeStateTests: [TC] = [
    TC("fresh state within window") { t in
        let state = ChromeDomainState(trackedDomain: "claude.ai", updatedAt: 1_000_000)
        t.expect(state.isFresh(now: 1_000_000))
        t.expect(state.isFresh(now: 1_000_000 + 179))
    },
    TC("stale state rejected") { t in
        let state = ChromeDomainState(trackedDomain: "claude.ai", updatedAt: 1_000_000)
        t.expect(!state.isFresh(now: 1_000_000 + 181), "older than window")
    },
    TC("far-future state rejected") { t in
        let state = ChromeDomainState(trackedDomain: "claude.ai", updatedAt: 1_000_000 + 3600)
        t.expect(!state.isFresh(now: 1_000_000), "clock-skewed future state")
    },
]
