import Foundation

// ThoughtMeter test runner. See TestHarness.swift for why this exists
// instead of XCTest. Run via `make test` or `swift run thoughtmeter-tests`.

let exitCode = runSuites([
    ("KeystrokeCounter", keystrokeCounterTests),
    ("InputTracker", inputTrackerTests),
    ("DomainNormalizer", domainTests),
    ("ChromeExtensionID", extensionIDTests),
    ("RecognizedCatalog", catalogTests),
    ("ChromeDomainState", chromeStateTests),
    ("SourceResolver", resolverTests),
    ("SQLiteStore", storeTests),
    ("AggregationFlusher", flusherTests),
    ("NativeMessageFraming", framingTests),
    ("HostLogic", hostLogicTests),
    ("AtomicFile", atomicFileTests),
    ("ChromeStateReader", chromeReaderTests),
    ("AppSettings", settingsTests),
    ("CountFormatter", formatterTests),
    ("LocalDate", localDateTests),
])

exit(exitCode)
