# Antinote — reverse-engineering report

Date: 2026-10-08. Targets analyzed:

| Source | Version | How obtained | Evidence type |
|---|---|---|---|
| `/Applications/Antinote.app` (installed) | 1.1.7 | local install, trial expired | static binary + live sandbox data + one screenshot |
| `Antinote_2.1.3.dmg` | 2.1.3 | downloaded from the public Sparkle appcast, mounted read-only | static binary + bundled resources only |
| antinote.io user manual, GitHub `johnsonfung/antinote-extensions`, `dracula/antinote` | 2.x docs | web | documentation (unverified against binary unless noted) |

Every claim below is tagged **[1.1.7 bin]**, **[2.1.3 bin]**, **[live data]**, or **[docs]**. Nothing was decompiled: no Hopper/Ghidra/IDA was available, and the binary's Swift symbol table is stripped. All binary facts come from `strings`, Objective-C runtime metadata (`otool -oV`, which still exposes Swift class names and stored-property names), `otool -L`, Info.plist, entitlements, and bundled resources. Raw extracts are in `evidence/`.

Licensing: the app has a 7-day trial, a `verifyLicense` endpoint, and stores the key plus a server token in the Keychain. This report describes that it exists and does not cover circumventing it. The installed copy is trial-expired, so the live editing UI could not be observed (see `evidence/antinote-1.1.7-trial-expired-window.png`).

---

## 1. Architecture in one paragraph

Antinote is a sandboxed, universal (arm64 + x86_64) native macOS app written in Swift, mixing SwiftUI (settings, overlays) with AppKit (the editor is an `NSTextView` subclass driven by a custom `NSLayoutManager`). All "features" are modes of a single plain-text buffer: the first line is parsed for a *keyword* (`math`, `list`, `timer`, …) and the rest of the note is re-rendered with text attributes and computed inline results. There is no backend of its own: 1.x stores notes in one SQLite file, 2.x in Core Data mirrored to the user's private CloudKit database. The only network calls are a handful of small `antinote.io/api/*` endpoints (license verification, currency rates, update appcast, app notices), each gated by a privacy toggle. 2.x adds a JavaScriptCore extension host.

---

## 2. Bundle, signing, entitlements

**[1.1.7 bin]**
- Bundle ID `com.chabomakers.Antinote`, min macOS 14.0, built with Xcode 16.2 / SDK 15.2.
- Frameworks: `Sparkle.framework` (updater), `Sentry.framework` (crash reporting).
- Resources: `Highlightr_Highlightr.bundle` (highlight.js + ~90 CSS themes for the `code` keyword), `Assets.car`, three sounds (`backtowork.m4a`, `workdone.m4a`, `countdowndone.m4a`), `setappPublicKey.pem` + `InfoSetApp.plist` (a Setapp build variant exists; strings: "Running the Setapp build", "SetApp - license initiated").
- URL scheme: `antinote://`. Exported UTType for `.md`.
- Entitlements: app-sandbox, user-selected files r/w, network client **and** server, mach-lookup exceptions for `-spks`/`-spki` (Sparkle's XPC installer services).
- Sparkle: `SUFeedURL = https://antinote.io/updates/appcast.xml`, EdDSA public key present, `SUEnableInstallerLauncherService = true`.

**[2.1.3 bin]** changes:
- `Sentry.framework` is gone; zero `sentry` strings in the binary. This matches the site's privacy claim.
- New entitlements: CloudKit (`iCloud.com.chabomakers.Antinote`, production), `aps-environment` (push, used by CloudKit change notifications), `files.bookmarks.app-scope` (persisted access to a user-chosen extensions folder), `print`.
- New frameworks linked: CloudKit, CryptoKit, LocalAuthentication (private notes), Accessibility, CoreText, `libcompression`.
- New resources: `AntinoteDataModel.momd` (9 model versions), `DataModel.md`, `BundledExtensions/` (18 extensions), `antinote-extensions-base-v0.0.1.js`, `sample-openai-extension.js`, `ZIPFoundation` bundle (export-all-as-zip), `Setapp_SetappResources.bundle`, 14 `.lproj` localizations, an iOS 26 icon set.

Linked system frameworks that explain features **[both]**: `Vision` (screenshot-to-text OCR, `VNRecognizeTextRequest`), `Carbon` (global hotkey via `RegisterEventHotKey`; ivars `carbonHotKeyID`, `carbonKeyCode`, `carbonModifiers`), `JavaScriptCore` (Highlightr runs highlight.js in a JSContext; in 2.x also the extension host), `AVFAudio` (timer sounds), `UserNotifications` (timer alerts), `MetricKit` (1.1.7 only), `ServiceManagement` (login item).

---

## 3. Third-party Swift packages (identified from embedded source file names and type names)

| Package | Evidence | Used for |
|---|---|---|
| **SQLite.swift** (stephencelis) | `Connection.swift`, `Statement.swift`, `Query.swift`, `SchemaChanger.swift`, `SchemaReader.swift`, `Coding.swift`, `Aggregation.swift` | all 1.x persistence; still present in 2.x (migration + `reloadDB`) |
| **MathParser** (davedelong's Swift DDMathParser) | `$s10MathParser16VariableResolverP`, `Expressionizer.swift`, `TokenGrouper.swift`, `TokenResolver.swift`, `OperatorSet.swift`, `FunctionSet.swift`, operator names `implicitMultiply`, `factorial2`, `dtor`, `percent`, config flags `allowImplicitMultiplication`, `useHighPrecedenceImplicitMultiplication`, `angleMeasurementMode` | the `math` keyword |
| **Highlightr** | bundle + `Highlightr/Theme.swift`, `hljs-*` class strings, `strippedTheme`, `themeBackgroundColor` | syntax highlighting for `code` notes; `SyntaxHighlightingPreferences` has `_defaultLanguage`, `_syntaxDarkTheme`, `_syntaxLightTheme` |
| **Sparkle 2** | framework, `UpdaterDelegate` class, `SU*` defaults | updates |
| **Sentry-cocoa** (1.x only) | framework, DSN strings | crash reports |
| **ZIPFoundation** (2.x) | resource bundle | "Export all notes" as `.zip` of `.txt` |
| **Setapp SDK** | `setappPublicKey.pem`, `InfoSetApp.plist` | Setapp distribution |

App-authored files seen by name: `ProcessMath.swift`, `SanitizeExpression.swift`, `ConversionRequestParser.swift`, `ConversionRequestValidator.swift`, `AnalyzeText.swift` (OCR), `KeywordDetectionManagement.swift`, `AppKitDropView.swift`, `Theme.swift`, `Defaults.swift`; 2.x adds `InlineListMarkers.swift`, `KeystrokeParser.swift` (vim), `LocaleNumberParser.swift`, `ExtensionsManager.swift`, `CoreDataStack.swift`, `SyncState.swift`, `URLSchemeManager.swift`.

---

## 4. Data layer

### 4.1 1.x: SQLite **[live data]**

Location: `~/Library/Containers/com.chabomakers.Antinote/Data/Documents/notes.sqlite3`. A timestamped copy `notes_backup_YYYY-MM-DD_HH-MM-SS.sqlite3` is written on every launch (12 present, one per launch; two days have two). `Documents/Themes/` is the custom-theme folder (empty here). Full schema in `evidence/schema-1.1.7.sql`:

```sql
notes(id TEXT PK, created TEXT, lastModified TEXT, content TEXT,
      dbIndex INTEGER UNIQUE, skippedURLs TEXT DEFAULT '[]')
checklist_items(id TEXT PK, note_id, content, checked INT, verticalPosition REAL,
      responsibilityRangeLocation INT, responsibilityRangeLength INT, "index" INT, isHidden INT)
antilinks(id TEXT PK, note_id, fullUrl, shortenedUrl, currentRangeLocation INT, currentRangeLength INT)
fts_notes  -- FTS5 virtual table (note_id UNINDEXED, content, tokenize='porter')
note_stats(total_notes, total_words, lines_with_equals, avg_notes_per_day)
```

Observations:
- `id` is an uppercase UUID string; dates are ISO-8601 with millisecond precision, no timezone (`2026-04-23T02:02:12.047`).
- `dbIndex` is the stack order (the "swipe" order). "Promote" / "jump to front" are reorderings of `dbIndex`.
- Search is FTS5 with the Porter stemmer; the app maintains it manually (`INSERT INTO fts_notes(note_id, content)`, `DELETE FROM fts_notes WHERE note_id = ?`) rather than via triggers.
- `checklist_items.responsibilityRange*` is the character range in `content` that a checkbox "owns"; `verticalPosition` caches its y-offset for hit-testing the drawn checkbox.
- `antilinks` stores the full URL and the current display range of the shortened form; `notes.skippedURLs` is a JSON array of URLs the user manually expanded (so they are not re-shortened).
- `note_stats` is recomputed with SQL such as `SELECT SUM(LENGTH(content) - LENGTH(REPLACE(content, '=', ''))) …` (counts "lines with equals", i.e. math usage) and `SELECT MIN(created) FROM notes` for notes-per-day. In 1.1.7 this fed the (now removed) analytics.
- The tutorial note that ships with the app is just a normal row (first row, `dbIndex = 1`).

### 4.2 2.x: Core Data + CloudKit **[2.1.3 bin]**

`DataModel.md` (shipped inside the app, copied to `evidence/datamodel-2.1.3.md`) declares entities `Note`, `ChecklistItem`, `Antilink`, `Attachment`. Note adds `isSlotted: Bool`, `slotIndex: Int32`, and `skippedURLs` as Transformable. The `.momd` version names tell the migration history: `2 - SoftDelete`, `3 - addCkChangeTag`, `4 - added isTutorial tag`, `5 - added deletedAt for Trash`, `6 - added ckSystemFields`, `7 - sync state entity`, `8 - added isLocked`, `9 - added isArchived isPrivate`. Entity class names surfaced from the compiled `.mom` files are `CDNote`, `CDChecklistItem`, `CDAntilink`; `Attachment` is documented in `DataModel.md` but was not surfaced by the (lossy) strings pass, so treat it as doc-level.

Sync classes: `CloudKitSyncManager` (ivars `syncEngine`, `container`, `database`, `stateStore`, `lastQuotaToastDate`, `manualRefreshInFlight`), `CloudKitStateStore`, `CloudKitSyncEngineDelegate`. Inferred from those names: it uses Apple's `CKSyncEngine` (macOS 14+) rather than `NSPersistentCloudKitContainer`; not confirmed from code. `NotesPreferences` has `_encryptCloudKitData`, `_syncWithICloud`, `_syncPreferencesWithICloud`, `_trashRetentionRawValue`, `_migratedToCoreData`. `PreferencesSyncManager` syncs settings. Docs say line-level merge with "SYNC CONFLICT" notes on same-line conflicts **[docs]**; the merge code was not examined.

Notes manager in 2.x (`CoreDataNotesManager`) keeps two arrays: `_noteViewModels` (ephemeral stack) and `_slottedNoteViewModels` (nine fixed slots), plus `deletedNotes` (The Void). `NotesPreferences._slotedNotesLimit`, `_isSplitView`, `_isSplitHorizontal`, `_alwaysShowSlottedBar` back the slotted/split UI.

### 4.3 Preferences **[live data]**

`~/Library/Containers/com.chabomakers.Antinote/Data/Library/Preferences/com.chabomakers.Antinote.plist`. Scalars are plain keys (`mathMainTrigger = "math"`, `checkMainTrigger = "/x"`, `selectedDarkTheme = "Knight"`, `licenseType = "Free"`, `installDate`, `windowOriginX/Y`, `windowWidth/Height`, `popoverWidth`, `lastWindowCloseTime`, `lastPinState`, Sparkle `SU*` keys). Two values are JSON blobs stored as `Data`:

- `keyboardShortcuts`: array of `{id, action, key, defaultKey, modifiersRawValue, defaultModifiersRawValue}`. Modifier raw values follow `NSEvent.ModifierFlags` shifted (16 = ⌘, 18 = ⌘⇧, 8 = ⌃). Default action table (from the `defaultKey`/`defaultModifiersRawValue` fields; the user's current bindings are identical):

| action | default |
|---|---|
| newNote | ⌘N |
| moveNoteToFront | ⌘⇧1 |
| deleteNote | ⌘D |
| searchNotes | ⌘F |
| findAndReplace | ⌘⇧F |
| pinNote | ⌘P |
| increaseTextSize / decreaseTextSize | ⌘+ / ⌘- |
| jumpToFront | ⌘1 |
| showPreviousNote / showNextNote | ⌘[ / ⌘] |
| hideShowMainWindow | ⌘O |
| globalShowApp | ⌃A in 1.1.7 (2.x docs say the default is ⌥A) |
| quickExport | ⌘S |

- `currencySettings`: array of `{id, currency, conversionRate}` for ~270 ISO and crypto codes, USD = 1.0, refreshed daily from `antinote.io/api/conversionRates` (`lastCurrencyUpdateDate`). Manual overrides are in `MathPreferences._manualCurrencyRates`.

Keychain items (names from strings): `com.antinote.analyticsId`, `com.antinote.notionAccessToken`, plus the license key/token. 2.x adds extension API keys (`apikey_<name>`) in Keychain via `APIKeyPreferences`.

---

## 5. Runtime structure (class inventory)

**[1.1.7 bin]** 58 app classes; **[2.1.3 bin]** 93. Full lists in `evidence/classes-*.txt`. Grouped by role, with the stored properties that reveal behaviour:

**App shell**: `AppDelegate` (owns `hotKeyManager`), `StartupManager`, `AppStateManager` (`_currentMode` ∈ `dockOnly` / `both` / menu-bar modes; changing it requires a restart), `StatusItemManager` (menu-bar `NSStatusItem` + `NSPopover`), `WindowManagement` (`mainWindow`, `popoverWindow`, `settingsWindow`), `WindowTopBar`/`CustomTitleBarView`/`WindowButtonCustomizer` (custom traffic lights, pin button), `PinStateManager`, `HotKeyManager` (Carbon hot key), `URLSchemeManager` (`pendingURLs` queued until `isAppReadyForURLSchemeHandling`), `AppNoticeManager` (`noticeURL`, `dismissedNoticesKey`), `UpdaterDelegate`/`CheckForUpdatesViewModel` (Sparkle), `ResettingConfigs` (reset prefs / keychain / currency / factory).

**Editor**: `TextEditorViewWrapper` (tracks `lastModifiedRange`, `preModifiedContent`, `lastModificationAction`, `cursorMovedRecently`: the per-keystroke diff that drives keyword re-processing), `TextViewRegistry`, `RoundedCodeLayoutManager` (draws rounded backgrounds behind code spans), `UndoManagement` (own `_undoStates`/`_redoStates` stacks rather than `NSUndoManager`), `UserActionRecord`/`UserSelectionRecord`, `FindAndReplaceManager` (`_matchCase`, `_matchType` = "Matches Word"), `Debouncer`, `GridTileCache` (grid-paper background tiles), `DropReceivingView` (`onImageDropped` → OCR), `KeyOverrideManager` (`rules`: keystroke remaps), `SwipeGestureDetector` (struct; `onSwipeLeft`/`onSwipeRight`). 2.x adds `CheckboxAttachmentManager` (inline checkboxes as `NSTextAttachment`), `Keybindings`, `VimModePreferences` (`_enabled`, `_motionTimeout`, `wrappedTextAsLines`), `PrintManager`.

**Keyword features**: `KeywordDefinitionsContainer` (`definitions`, `mainKeywords`), `KeywordPreferences` (per-feature `*TriggersStorage` list + `*MainTriggerStorage` for sum/avg/math/list/count/code/paste/timer/check, `_disableAllKeywords`, `_disableLinkHighlighting`, `_disableLinkShortening`), `MathManager` (`storedVariables`, `storedVariablesReverseIndex`, `duplicateVariables`, `variableUseIndex`, `variableUseReverseIndex`: the reactive-variable dependency graph), `MathPreferences` (`_primaryCurrency`, `_secondaryCurrency`, `_primaryCurrencySymbol`, `_primaryMeasurementSystem`, `_numberOfDecimalPoints`, `_useThousandSeparators`, `_manualCurrencyRates`), `ChecklistManager` (`_checklist`, `_keywordLineText`, `_currentlyEditingChecklistIndex`), `TimerManager` (`_timerType`, `_timerTitle`, `_startTime`, `_breakTime`, `_timeLeft`, `_cycleCount`, `_isWorkPhase`, `_isPaused`, `audioPlayer`, `overlayController`, `timerStateTimestamp`, `userDefaultsKey`: timer state survives relaunch), `TimerPreferences`, `TimerCompleteAlertController` (full-screen alert window), `AutoPasteMonitor` (`timer` polling `NSPasteboard.general` changeCount, `lastClipboardContent`, `delimiter`, `numberOfItems`), `AntilinkManager` (`_antilinks`, `_skippedURLs`, `temporarilyUnshortenedAntilinks`, `debounceTimerForAntilinks`), `HighlighterManager` (`highlightr`), `PersistentPillManager` (the bottom status "pill": `_message`, `_messageType`).

**Persistence/export**: `SQLiteManager` (column-expression ivars mirror the schema above), `NotesManagement` (`_noteViewModels`, `_searchResults`, `_currentIndex`, `previouslyViewedIndex`, `deletedNotes`), `NoteViewModel`, `ChecklistItem`, `ExportManager` (`_providers`: `ObsidianExportProvider`, `AppleNotesExportProvider`, …), `ExportPreferences` (Plain text, Markdown, Bear, Obsidian (`_exportObsidianVault`), Apple Notes (`ConvertToRichText`), **Notion** (`_exportNotionEnabled`, `_exportNotionSaveInDatabase`, `_exportNotionDatabaseName`: present in both binaries but absent from current docs), Custom URL (`_exportCustomURLTemplate`)), `CopyPastePreferences` (`_skipKeyword`, `_skipChecked`, `_removeLeadingTabs`, `_removeNumbers`, `_removeBullets`, `_removeMarkdown`, `_keepIndentation`, `_removeEmptyLines`, `_autoCopyOnSelect`, `_enableTexReplacements`).

**Preferences**: `VisualPreferences` (`_fontSize`, `_selectedLightThemeName`/`_selectedDarkThemeName`, 2.x adds slotted-theme variants, `_paperTypeRawValue`, `_paperOpacityRawValue`, `_translucentWindow`, `_translucentAmount`, `_hideWhenUnfocused`, `_popoverWidth/Height`, `_appIconPreference`), `MiscPreferences` (`_fontFamily`, `_forceRTLStorage`, `_showTopBarUI`, `_showBottomBarUI`, `_showLastNoteIndicator`, `_solidBarsInTransparencyMode`, `_disableSwipeNavigation`; 2.x adds `_inlineChecklistCheckboxesEnabled`, `_inlineChecklistBulletsEnabled`, `_inlineNumberedListsEnabled`, `_listDefaultMarkerStyle`, `_onCheckItemBehavior`, `_enableSpellCheck`, `_enableAutocorrect`, `_swipeNavigationThresholdRaw`, `_appLanguageOverride`), `NotesPreferences` (`_launchWithNewNote`, `_autoDeleteBeforeRawValue`, `_autoNewNoteTimingRawValue`, `_showNoteCount`, `_autoBackupQuantity`, `_autoBackupIntervalRawValue`), `ThemeManager` (`_customThemes`), `TutorialPreferences`, `LicensePreferences` (`freeTrialLengthInDays`, `_licenseType`, `_installDateTimeInterval`, `licenseKey`, `token`), `PrivacyPreferences` / `PrivacyGroupData` / `PrivacyOption` (each option has `networkCall` text and `isOn`).

**2.x extension host**: `ExtensionsManager` (`context` = JSContext, `commands`, `logger`, `currentExecutingExtension`, `executionLock`), `ExtensionParser`, `ExtensionMetadataRegistry`, `ExtensionRegistryManager`, `CommandRegistryManager`, `CommandAliasManager`, `DependencyResolver`, `ExtensionSignatureVerifier`, `ExtensionUpdateManager`, `ExtensionCloudSync`, `ExtensionAutocompleteManager`, `ExtensionLogger`, `ExtensionsPreferences` (`_enableExtensions`, `_enableExtensionLogs`, `_customExtensionsFolder`, `_commandUsageHistory`, `_commandUsageStats`), `APIBridge`, `MathEvaluatorBridgeImpl`, `APIKeyPreferences`, `AIModelCatalog` (fetches `https://openrouter.ai/api/v1/models`). Also `PrivateNotesSession` (`authInFlight`, `lastPrivateFocus`; LocalAuthentication) and `DebugManager`.

---

## 6. Feature behaviour spec

### 6.1 Keyword detection **[docs + bin]**
- The first line is matched against every trigger list (`sumTriggers`, `mathTriggers`, …). Each feature has one *main* trigger (what the `/` slash menu pastes) and optional additional comma-separated triggers; triggers must be unique across features (error string "The following keywords are not unique").
- `keyword: Title` sets a title; the keyword line is kept in the note text but can be omitted on copy/export (`_skipKeyword`, `_exportGeneralOmitKeyword`).
- Typing `/` as the first character of a line shows the main keywords; pressing the number pastes it and replaces an existing keyword (`handleSlashCommand:`, `slashCommandInvoked`).
- `//` at line start comments the line out of checklists and calculations.
- Keyword detection runs on the first line only ("mid-line-detect" debug strings exist for the timer line).

### 6.2 `math` **[docs; engine identity from bin]**
- A line ending in `=` is evaluated and the result is appended inline (rendered as a non-editable "calculated field": "Calculated fields and shortened links cannot be edited via drag and drop").
- Words and currency symbols are stripped before evaluation (`SanitizeExpression.swift`, regex with `(?<=^|[\s,;:|/\-+*()\[\]{}])[-]?[$…`).
- Operators: `+ - * x X / ÷ ^ **`, parentheses, `!`, `!!`, `√`, `∛`, `sqrt log log2 ceil floor`, percentages (`100 + 15% = 115`, `50% of 200 = 100`), implicit multiplication (MathParser flag).
- Variables: `name : value` assigns (names may contain spaces); `name + 1 =` uses it; `ans` = nearest result above. `MathManager` keeps forward and reverse indexes so editing a variable re-evaluates dependants (the "reactive variables" feature).
- Number formats: locale-aware (`LocaleNumberParser.swift` in 2.x; `1.000,25` accepted).
- Conversions: `10 USD to JPY =`, `$10 to JPY =` (symbol → primary currency), `$10 =` (primary → secondary), `10" to cm =`. Categories: distance, area, volume, mass, temperature; parsed by `ConversionRequestParser`/`Validator`, computed with Foundation `Measurement`/`NSMeasurementFormatter`. Conversions cannot be nested in arithmetic. Conversion results assigned to a variable store only the number.
- Settings: decimals 0–7, thousands separator, primary/secondary currency, primary symbol, manual rates (`NTD:30.23`), daily rate update (needs both the Math and the Privacy toggle).

### 6.3 `sum`, `avg`, `count` **[docs]**
Every number in the note is summed / averaged (punctuation stripped, fractions unsupported); `count` reports items, lines, words, characters. `//` lines are excluded.

### 6.4 `list` and inline checklists **[docs + bin]**
- `list` keyword: every non-empty line becomes an item (default style checkbox; bullets or numbers configurable). `#` headings and `//` comments are not items. Tab / ⇧Tab nest. Math is disabled in lists.
- Check trigger: type `/x` (customisable `checkMainTrigger`) at the end of a line to toggle; it is consumed as you type. ⌘⇧K also checks the current line.
- Inline markers in any note (2.x): `[ ]`, `- [ ]`, `[x]`, `- [x]`, `-`, `1.`; ⌘⇧M cycles checkbox/bullet/number; Return continues, Return on an empty item ends; numbering auto-renumbers; nested numbers display `a.`/`i.` but store digits.
- On check: stay / move to bottom of group / delete (`_onCheckItemBehavior`).
- Storage: `checklist_items` rows carry the owned text range and checked state; the drawn checkbox is positioned from `verticalPosition`. In 2.x checkboxes are `NSTextAttachment`s (`CheckboxAttachmentManager`).

### 6.5 `timer` **[docs + bin]**
- `timer` → stopwatch; `timer 3.5` / `timer 3:30` → countdown; `timer 9AM` / `timer 21:15` → countdown to a time; `timer 5 1` → pomodoro (work/break); `timer pomo` → 25/5; `timer 5: Title` names it (title starts at the first colon not followed by a number). Controls: `timer p` pause/resume, `timer r` restart, `timer s` / `timer 0` stop; click pauses, double-click stops, Esc stops.
- Binary regex fragments confirm the grammar: `(?:(?:(?:pomo|pomodoro|breath|breathe|p|r|s)|…` (note the undocumented `breath`/`breathe` mode) and the duration token `(?:[0-9]+(?:\.[0-9]+)?|\.[0-9]+|[0-9]*:[0-5]?[0-9])(?:\s+(…))?`. The full regex is assembled at runtime from fragments, so it was not recovered verbatim.
- State (`timerStateTimestamp`, `userDefaultsKey`) is persisted so the timer survives relaunch; `_pauseTheTimerIfAppClosed` toggles that. Alerts: notification, full-screen window, sound (three bundled m4a, volume 0–100, pomodoro alerts only when > 30 s). Can show remaining time in the menu bar (menu-bar modes only).

### 6.6 `code` **[bin]**
Highlightr with `_defaultLanguage` and separate light/dark highlight.js themes; `RoundedCodeLayoutManager` draws the block background; link shortening and inline list markers are disabled in code notes and inside fenced blocks (regex `(?m)^([-*_=]{3,}|\`{3,})$` detects fences).

### 6.7 `paste` (AutoPaste) **[docs + bin]**
"Enter to start AutoPaste. Everything you copy will be added here." `AutoPasteMonitor` polls the general pasteboard on a timer, compares with `lastClipboardContent`, appends new text with `delimiter`, counts `numberOfItems`; Esc stops.

### 6.8 Links (Antilinks) **[docs + bin]**
- URL detection regex (from strings): `(?:(?<=\s)|^)(?<!@)((https?|ftp):\/\/)?((?:[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,})|(localhost)|(\d{1,3}(\.\d{1,3}){3}))(:\d+)?(?=[\/?#\s(),]|$)([\/?#][^\s(),\r\n@…`.
- Shortening is purely visual: the display text is replaced by a short form (duplicates get `[#]`), while `antilinks.fullUrl` keeps the original; copying yields the full URL. Shortening happens only after the caret leaves the URL (debounced). ⌘⇧Click toggles expand/shorten and expanded URLs are remembered in `skippedURLs`. ⌘Click / ⌘Return opens. Editing inside a shortened link is blocked ("Cannot partially edit shortened links. Expand before editing."). Toggles: `_disableLinkShortening`, `_disableLinkHighlighting`.

### 6.9 Screenshot to text **[docs + bin]**
Drag or paste a JPG/PNG/static GIF; `DropReceivingView.onImageDropped` → `AnalyzeText.swift` runs `VNRecognizeTextRequest` locally ("OCR initiated…", `ocrTextProcessed`), inserts plain text.

### 6.10 Navigation and lifecycle **[docs + bin]**
- Two-finger swipe (or ⌘[ / ⌘]) moves through the stack ordered by `dbIndex`; swiping past the newest creates a note; swiping away from an empty note deletes it; ⌘1 jumps to front; ⌘⇧1 promotes (moves current to front); ⌘D deletes to The Void (confirmation suppressible via `suppressDeleteWarning`). After navigating, an arrow key places the caret at start or end.
- Auto-delete of unmodified notes: Never / 1 day / 3 days / 1 week / 1 month / 1 year (enum `AutoDeleteOption`: `never, oneDay, threeDays, oneWeek, oneMonth, oneYear`). "Delete all notes not modified since" bulk action.
- Auto new note: "Create a new note after" Always / 3 min / 30 min / 1 h / 1 day / Never, measured from `lastWindowCloseTime` (focus loss). "Start with a new note" on launch.
- Backups: always at launch; also on quit/focus-loss when `_autoBackupIntervalRawValue` elapsed; keep `_autoBackupQuantity` (1–100), oldest overwritten.
- 2.x slotted notes: nine permanent slots (`isSlotted`, `slotIndex`), ⌘T swaps stacks, ⌘⇧T split view, ⌘1–9 jump to slot when enabled, planet bar. Private notes (`isPrivate`) relock after `_privateRelockMinutesStorage` and re-prompt with LocalAuthentication; `isLocked` = read-only; `isArchived` with `_showArchivedInStackStorage`.
- Window modes: Dock, Pseudo Menu Bar ("app will hide/show when you click the menu bar"), Traditional Menu (status item + popover of `popoverWidth`/`popoverHeight`), with `hideWhenUnfocused`, translucency (macOS 15+), paper types (grid tiles via `GridTileCache`, `gridSuperlight/gridClear/gridBold` theme colours), optional top/bottom bars, note count, last-note indicator.

### 6.11 Copy/export **[docs + bin]**
On copy: optionally drop keyword line, checked items, leading tabs, numbers, bullets, markdown markers, empty lines; `_autoCopyOnSelect`; `_enableTexReplacements` (TeX-style symbol substitutions). Quick Export ⌘S to one configured provider. Providers: `.txt`, `.md`, PDF, Print, Obsidian (`obsidian://new?vault=…`), Bear (`bear://x-callback-url/create`), Apple Notes (via an Apple Shortcut; `https://antinote.io/shortcuts/AppleNotes`), Notion (OAuth token in Keychain; hidden from docs), Custom URL template with `{CONTENT}`, `{TITLE}`, `{DATE}` (in a path position `&`→`+` and `%`→` percent`), Export-all as zip.

### 6.12 URL scheme **[docs; only partially confirmed in bin: `newNote`/`open`/`search` strings in 1.1.7, `overwriteCurrent`/`search`/`searchTerm` in 2.1.3]**
`antinote://` opens the app. x-callback-url actions: `createNote?content=`, `appendToCurrent?content=`, `overwriteCurrent?content=`, `promoteAndOpen?noteId=<UUID>`, `togglePin`, `hotkey`, `search?searchTerm=&x-success=` (returns JSON array of `{id, content, lastModified}`), `reloadDB` (re-read SQLite after external edits). `URLSchemeManager` queues URLs received before the UI is ready. The Raycast extension and Alfred workflow are thin wrappers over these.

### 6.13 Formatting ("Simple Markdown") **[docs + bin]**
`#`/`##`/`###` headings, `**bold**`, `*italic*`, `__underline__`, `~~strike~~`, `//` comment; shortcuts ⌘B/⌘I/⌘U/⌘⇧X/⌘⇧H (cycle heading)/⌘/ (comment), ⌥↑/⌥↓ move line (single undo step). Regexes in the binary match headings, setext underlines, blockquotes, bullets, numbered lines, horizontal rules, fenced blocks, footnotes, and `(?<=\w)(\*\*|__)(.*?)(\*\*|__)(?=\w)` style emphasis. Rendering is attribute-only; the markers stay in the text.

### 6.14 Themes **[community sample + bin]**
A theme is one JSON file dropped in the Themes folder (Settings > Appearance > open folder, then "Reload Custom Themes"). Keys, from `evidence/theme-sample-dracula.json`:

```
name, isDarkTheme,
background, backgroundFade,
typeMain, typeSubtle, typeSubtlePlus, typeHighlight, typeLight, typeSuperlight, typeHyperLight, typeReverse,
accent1Main, accent1Secondary, accent1Tertiary,
accent2Main, accent2Secondary, accent3Main, accent3Secondary,
accent4Main, accent4Secondary, accent5Main, accent5Secondary,
gridSuperlight, gridClear, gridBold
```

Built-in theme names (2.x official repo): a24, agrabah, demogorgon, gundam-wing, knight, mononoke, muaddib, nord, piccolo, sanrio, shadow-moses, tartan, tokyo-drift, totoro, vancouver, vendetta. Light and dark slots are chosen separately (and separately again for slotted notes in 2.x).

### 6.15 Extensions (2.x) **[2.1.3 bin + repo]**
- Host: a single `JSContext` (`ExtensionsManager.context`) that first evaluates `antinote-extensions-base-v0.0.1.js` (copied to `evidence/`), which defines `Command`, `Extension`, `Preference`, `Parameter`, `TutorialCommand`, `ReturnObject`, `MathEvaluator`, and two global registries (`global.commandRegistry`, `global.extensionRegistry`). Native functions injected into the context that are visible from the JS/strings: `callAPI` (HTTP, restricted to URLs declared in `endpoints` and gated by the privacy toggle "Let extensions call their own APIs"), `__evaluateMathExpression` (bridges to the Swift MathParser via `MathEvaluatorBridgeImpl`), and `console.*` routed to `ExtensionLogger` (500-entry buffer).
- Packaging: a folder with `extension.json` + `index.js` (+ optional `files[]`, `preferences`, `dependencies`, `isService`, `includedByDefault`, `dataScope` ∈ `none|line|full`, `endpoints`, `requiredAPIKeys`) or a legacy single `.js`. Default folder `~/Library/Application Support/Antinote/Extensions/` or a bookmarked custom folder. Sample manifest in `evidence/extension-sample-date.json`.
- Command types: `insert`, `replaceLine`, `replaceAll`, `openURL`. Invocation: type `::`, pick a command, `::name(arg1, "quoted, arg", 0.05/12)` (parameters may be math expressions, parsed via `MathEvaluator.parseNumeric`). A command's `execute(payload)` returns a `ReturnObject{status, message, payload}`.
- 18 bundled extensions: ai_process, ai_providers (service; OpenAI, Anthropic, Google, OpenRouter, Ollama), business, checklists, clean_line, date, dice, filter_lines, finance, json_tools, line_format, line_sort, list_tools, llm, random, regex, templates, text_format. `DependencyResolver` topologically orders them; `ExtensionSignatureVerifier` and `ExtensionUpdateManager` handle signed updates from GitHub (`_checkGithubForExtensions` privacy toggle). `ExtensionCloudSync` syncs installed extensions via CloudKit.

---

## 7. Network surface

| Endpoint | Purpose | Gating toggle | Evidence |
|---|---|---|---|
| `GET https://antinote.io/updates/appcast.xml` | Sparkle updates (EdDSA signed) | "Check for updates automatically" / `_enableUpdater` | Info.plist; live fetch shows 2.1.3 (2026-09-16), 2.1.2, 2.1.1 |
| `GET https://antinote.io/api/appNotices` | "urgent alerts" banner, filtered by `versions[]` | "Check for urgent alerts" / `_queryUrgentAlerts` | live response: one notice telling 2.0.8 users to update to 2.0.9 |
| `antinote.io/api/conversionRates` (strings also mention `/api/currencies`) | daily currency table (expects ≥ 50 rates, else warns) | "Automatically update conversion rates daily" / `_updateConversionRates` | strings, `lastCurrencyUpdateDate` |
| `antinote.io/api/verifyLicense` | license key → token (Keychain) | "the only call that cannot be turned off, but it is only made when you verify your license key" | strings |
| `antinote.io/api/updates/` | referenced in strings; purpose not determined | — | strings |
| Sentry DSN (1.1.7 only) | crash reports | "Send crash logs" / `_sendCrashLogs` | framework; removed in 2.x |
| `https://openrouter.ai/api/v1/models` (2.x) | AI model catalogue for the LLM extensions | extension API toggle | strings, `AIModelCatalog` |
| CloudKit (2.x) | note + preference sync, private DB, encrypted fields | `_allowCloudKitSync`, `_syncWithICloud` | entitlements, classes |

Analytics: 1.1.7 has an `AnalyticsManager` class, Sentry, and `PrivacyPreferences` keys `_usedAntinote`, `_featuresUsage`, `_personalizationChoices`, `_tutorialViews`. In 2.1.3 the Sentry framework, all DSN strings, and the `AnalyticsManager` class are gone and no analytics endpoint appears in the strings, but those four usage-preference keys are still present in `PrivacyPreferences` (2.x also adds `_commandUsageHistory`/`_commandUsageStats` for extensions). Whether anything is still tallied locally cannot be settled statically.

---

## 8. Observed live state **[live data]**

- Installed 1.1.7, `licenseType = Free`, trial expired; the main window shows only the "Trial Expired" overlay (`TrialExpiredOverlay`) with Verify / Buy / Export-all-notes.
- 19 notes, 15 checklist items, 0 antilinks in `notes.sqlite3`; 12 launch backups since 2026-04-24.
- Dark theme "Knight"; window 376×476 at (1029, 473); `appIconPreference = "neither"` (meaning not determined; see unknowns); Sparkle auto-update off, auto-check on.

---

## 9. Unknowns and limits

- No decompiler was available, so control flow (exact keyword parsing order, merge algorithm, antilink range maintenance, undo coalescing) is inferred from names, strings, and docs, not read from code.
- Swift symbols are stripped; only classes bridged to the ObjC runtime expose stored-property names. Pure Swift structs/enums (`Theme`, `KeywordDefinition`, `AppMode`, `SwipeDirection`) are known by name only.
- The timer regex is assembled from fragments at runtime; only fragments were recovered.
- The live editor could not be exercised (trial expired), so no runtime capture of keyword behaviour was made.
- 2.1.3 was analyzed statically from the DMG only; it was not run. iOS-specific classes (`iOSKeyboardPreferences`, `_iosAppIcon`) show the codebase is shared with the upcoming iOS app.
- Meaning of `appIconPreference = "neither"` (likely "show in neither Dock nor menu bar", unverified).
- `antinote.io/api/updates/` purpose, the exact `verifyLicense` payload (`VerifyLicensePayload`, `ActivateLicenseResponseData`, `ActivationData` type names only), and Notion export status are unresolved.

## 10. Evidence index

The raw extracts this report cites (binary string dumps, Objective-C runtime dumps, Antinote's bundled extension JavaScript, the SQLite schema, a theme sample) were kept in an `evidence/` folder while the analysis was done. They are Antinote's own shipped artifacts, so they were removed before this repository was made public. Regenerate them with `strings -a -arch arm64` and `otool -arch arm64 -oV` on `Antinote.app/Contents/MacOS/Antinote`, and `sqlite3 notes.sqlite3 .schema` on a copy of the notes database.
