//
//  LocalizationCatalogTests.swift
//  DDiaryTests
//

import Foundation
import XCTest
@testable import DDiary

/// Checks the localizations that actually shipped into the app bundle.
///
/// These tests read the compiled `.lproj/Localizable.strings`, which is the only view of the
/// localizations available at runtime: unit tests execute on a simulator, and on Xcode Cloud the
/// checkout is already gone by then, so nothing here can consult `L10n.swift` or the catalog
/// source.
///
/// What that covers: a language that shipped without an `.lproj` at all, and one that shipped
/// half-filled — a key English carries that another language is missing or left blank, wherever it
/// was lost between the catalog and the bundle.
///
/// What it cannot cover, and worth knowing about: a key `L10n.tr(_:_:)` asks for that was never
/// added to `Localizable.xcstrings`. Such a key leaves no trace in the bundle — there is nothing to
/// find — and `tr(key, default)` quietly returns its English default, so it renders in English
/// everywhere and looks exactly like a working string. Catching that means comparing `L10n.swift`
/// against the catalog, which needs the sources, so it belongs to whatever reads the checkout
/// rather than to a test. Three such keys were found by hand while writing these tests.
final class LocalizationCatalogTests: XCTestCase {

    /// Localizations the app ships. A new language must be added here and filled in everywhere,
    /// so half-landing one fails instead of silently falling back to English.
    private static let expectedLanguages: Set<String> = [
        "ar", "de", "en", "es", "fr", "it", "ja", "ko",
        "nl", "pl", "pt-BR", "ru", "sv", "tr", "uk", "zh-Hans",
    ]

    // MARK: - Tests

    func test_appBundle_shipsEveryExpectedLanguage() throws {
        let shipped = Set(Bundle.main.localizations).intersection(Self.expectedLanguages)
        let absent = Self.expectedLanguages.subtracting(shipped).sorted()

        XCTAssertTrue(
            absent.isEmpty,
            """
            The built app has no .lproj for \(absent.joined(separator: ", ")). Every string in \
            those languages falls back to English at runtime.
            """
        )
    }

    func test_everyShippedLanguage_translatesEveryEnglishKey() throws {
        let english = try strings(for: "en")
        XCTAssertFalse(english.isEmpty, "en.lproj/Localizable.strings compiled to nothing")

        var problems: [String] = []
        for language in Self.expectedLanguages.subtracting(["en"]).sorted() {
            let translated = try strings(for: language)

            let missing = Set(english.keys).subtracting(translated.keys).sorted()
            if !missing.isEmpty {
                problems.append("\(language): missing \(missing.count) key(s) — \(missing.prefix(5).joined(separator: ", "))")
            }
            let blank = translated
                .filter { english[$0.key] != nil && $0.value.trimmingCharacters(in: .whitespaces).isEmpty }
                .keys.sorted()
            if !blank.isEmpty {
                problems.append("\(language): empty value for \(blank.joined(separator: ", "))")
            }
        }

        XCTAssertTrue(
            problems.isEmpty,
            "Languages that shipped incomplete:\n" + problems.joined(separator: "\n")
        )
    }

    /// The English side of the catalog omits entries whose value equals the key — Xcode drops
    /// identity strings in the development language — so every key English does carry is one a
    /// translator was meant to see.
    func test_englishKeys_areRealKeysRatherThanPlaceholders() throws {
        let english = try strings(for: "en")

        let unresolved = english.filter { $0.value == $0.key }.keys.sorted()
        XCTAssertTrue(
            unresolved.isEmpty,
            """
            \(unresolved.count) English entry/entries are just their own key, which is what a \
            string looks like when its translation was never filled in:
            \(unresolved.joined(separator: "\n"))
            """
        )
    }

    // MARK: - Reading the built bundle

    /// The compiled `Localizable.strings` for one language, as it shipped inside the app.
    private func strings(for language: String) throws -> [String: String] {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: language),
            "No Localizable.strings for \(language) in the built app bundle"
        )
        let plist = try PropertyListSerialization.propertyList(
            from: try Data(contentsOf: url), format: nil
        )
        return try XCTUnwrap(plist as? [String: String], "\(language) strings file is not a string dictionary")
    }
}
