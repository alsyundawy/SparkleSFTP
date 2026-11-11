# ADR-006: SparkNotePad Multi-Themes, Runtime JSON i18n, Notepad2 Editor, and Community Update Fallback

## Status

Accepted

## Date

2026-11-11

## Context

Following the MVP release (`v0.2.0`), post-release hardening added four rich macOS desktop capabilities while retaining **macOS 13+ deployment target** and **Swift 6 strict concurrency**:

1. **Multi-Theme Engine (`SparkNotePad` Palettes)**: Need 28 curated light/dark themes with WCAG 2.1 AA contrast validation and user JSON extensibility without adopting macOS 14-only `@Entry` macros.
2. **Maintainable JSON i18n (`Resources/Locales/`)**: Static hardcoded Swift dictionaries hindered translation auditing and community contributions; bundled JSON files also risk `Bundle.module` `fatalError` crashes inside Universal 2 `.app` bundles if `resource_bundle_accessor` points only to build-time paths.
3. **Minimalist Notepad2 Internal File Editor (`Features/Editor/`)**: SwiftUI `TextEditor` lacks deterministic line-number gutters (`NSRulerView`), whitespace symbol drawing (`¶`), horizontal no-wrap toggles, regex range highlighting, and direct caret metrics needed for server config editing.
4. **Auto-Update Community Mode vs Signed Sparkle Feed**: Unsigned/community builds ship with placeholder `SUPublicEDKey`, which previously caused silent `checkForUpdates` no-ops without UI feedback.

## Decision

1. **Theme Architecture (`Packages/DesignSystem`)**: Implement `SparkleThemePalette` + `SparkleThemeCatalog` (`28` palettes across `15` families) + `SparkleThemeStore` custom JSON loader/exporter, exposing active palettes via standard macOS 13-compatible `EnvironmentKey` (`EnvironmentValues.sparklePalette`).
2. **Crash-Safe JSON i18n (`LocalizationCatalog`)**: Ship synchronized `en.json` and `id.json` (`271` keys) with runtime overrides under `Application Support/SparkleSFTP/Locales/`, resolving `SparkleSFTP_SparkleDesignSystem.bundle` from `Bundle.main.resourceURL` inside `.app` bundles before falling back safely to built-in strings instead of invoking `Bundle.module` unconditionally. Cache active `AppStrings` & `SparkleThemePalette` cleanly on `AppState`.
3. **AppKit-Backed Internal Editor (`Features/Editor/`)**: Wrap `NSTextView` (`NotepadTextView`) + `NSRulerView` (`NotepadLineNumberRuler`) in an isolated multi-tab `EditorSessionManager`, reusing active `SparkleThemePalette` tokens for syntax highlighting and `SecureTempDirectory` atomic staging for remote upload-on-save.
4. **Fail-Closed Auto-Update Controls (`App/SparkleUpdaterService.swift`, `Core/UpdateModels.swift`)**: Keep Sparkle 2 native auto-installation gated strictly on valid HTTPS feeds + non-placeholder 32-byte Ed25519 `SUPublicEDKey`, while providing configurable `AutoUpdateSettings` and read-only TLS GitHub Releases version checks for community builds.

## Consequences

- Packaged `.app` builds copy `SparkleSFTP_SparkleDesignSystem.bundle` into `Contents/Resources/` (`Tools/Release/build-universal.sh`) and never crash if launched standalone.
- Future translation contributors can inspect coverage percentages and import/export locale JSON directly in Preferences without recompiling Swift sources.
- Retaining `ObservableObject` (`AppState`) remains backward-compatible with macOS 13+, while future `v1.1+` sub-store decomposition (`TD-01`) can split state cleanly without changing JSON/storage schemas.
