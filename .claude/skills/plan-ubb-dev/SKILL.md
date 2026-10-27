---
name: plan-ubb-dev
description: Workflows for the Plan UBB repo (iOS app in ios/, Android app in android/). Use when installing the app on the connected iPhone or Android phone, running the tests, adding or changing user-facing text (English + Polish translations), releasing to Google Play or the App Store (builds, review, store images), or retaking the framed README screenshots.
---

# Plan UBB development

The repo has two native apps with the same features: `ios/` (SwiftUI, XcodeGen project) and `android/`
(Kotlin + Compose). `test-fixtures/` holds captured server responses that both apps' parser tests read.
The README covers features and architecture; this skill covers how to do things and what goes wrong.

## Install on a phone

```sh
ios/install-on-device.sh        # builds, signs with the personal team, installs, launches
android/install-on-device.sh    # release build signed with ~/.android/debug.keystore
```

- Both pick the first phone connected **over USB**. Override with `DEVICE_ID=…`; iOS also takes `TEAM_ID`/`CONFIGURATION`, Android `BUILD_TYPE=debug`.
- If the Android script says no phone is connected but `system_profiler SPUSBHostDataType` lists it, USB debugging is off or the "Allow USB debugging" prompt wasn't accepted. Ask the user to fix that on the phone; don't retry.
- After installing, check it didn't crash: `adb shell pidof it.mwojtowicz.planubb` and `adb logcat -d -b crash | grep planubb`. Release builds are minified with R8, so a crash on launch there may not happen in debug.
- The iOS project (`*.xcodeproj`) is gitignored; `xcodegen generate` (in `ios/`) recreates it. The install script runs it.
- Without `TEAM_ID`, the iOS script reads the team from Xcode's accounts (`defaults export com.apple.dt.Xcode -` → `IDEProvisioningTeamByIdentifier`), preferring the free personal team. Don't hard-code a team ID. The signing certificate's `OU` field holds the team ID too, but the ID in brackets in its name doesn't.
- Free-team iOS installs expire after 7 days; rerunning the script re-signs.

## Android release

`android/build-release.sh` builds `android/build/release/plan-ubb-<version>.apk` and `.aab`, signed with the release key. The key's and its password's locations are in `SIGNING.local.md` at the repo root, and the release scripts read them from `signing.local.env` (both gitignored; read them when you need them). The repo is public: never write key locations, Keychain item names, key IDs or passwords into committed files, and never print the password. If the keystore is missing but the Keychain item exists, stop and ask the user to restore the backup. Don't create a new key: installed copies couldn't be updated. Release and debug-signed installs can't replace each other.

Keep the two apps' versions in step where possible: Android `versionCode`/`versionName` in `android/app/build.gradle.kts`, iOS `CURRENT_PROJECT_VERSION`/`MARKETING_VERSION` in `ios/project.yml`. Every upload needs a new build number. Don't rebuild a version that was already uploaded: `build-release.sh` overwrites `build/release/plan-ubb-<version>.*`, so bump first.

To smoke-test a release build on the emulator without touching `build/release/`: `./gradlew :app:assembleRelease` without the signing properties gives `app-release-unsigned.apk`; sign a copy in the scratchpad with `apksigner sign --ks ~/.android/debug.keystore --ks-pass pass:android` (needs `JAVA_HOME`), uninstall the release-signed app (`adb uninstall`, sometimes `--user 0`), install, launch, and check `logcat` for `FATAL`.

### Google Play

There's no Play API setup; releases go through Play Console in Chrome (the user is signed in; never sign in yourself).
1. Production track → "Utwórz nową wersję" (Create new release). Upload the `.aab` with `file_upload` on the hidden file input (find "input type=file for app bundles"); don't click the upload button, it opens a native picker. Wait until Play finishes "optimizing for distribution".
2. The release name fills in as `<versionCode> (<versionName>)`. Release notes go in one textarea with language tags: `<pl-PL>…</pl-PL>` and `<en-US>…</en-US>`.
3. "Dalej" (Next) → check warnings → "Zapisz" (Save). Then the publishing overview ("Przegląd publikowanych zmian") → "Prześlij zmiany do sprawdzenia" → confirm "Wyślij zmiany do sprawdzenia". Sending for review needs the user's go-ahead in chat. Sometimes Play moves a saved draft into review on its own, so check the overview after saving.
4. Managed publishing is off: the release goes live as soon as Google approves it.

Expected warnings and suggestions that need no action:
- "App Bundle contains native code but debug symbols weren't uploaded": the `.so` files come from AndroidX libraries, not from us.
- "Bitmap downsampling / BitmapFactory without inSampleSize": the only `BitmapFactory` call in the dex is in AndroidX `IconCompat` (URI icons), which the app never uses; our notification icons come from `createWithBitmap`.
- "R8 optimization": R8 runs with `proguard-android-optimize.txt` plus resource shrinking. `app/proguard-rules.pro` adds no keep rules; the remaining kept code is from AndroidX consumer rules. To find which class calls something, dump the dex (`build-tools/*/dexdump -d`) and look up the obfuscated class in `app/build/outputs/mapping/release/mapping.txt` (use `LC_ALL=C` with grep/awk, the dump isn't valid UTF-8). `configuration.txt` in the same folder is the merged R8 config.

## iOS App Store release

`ios/upload-to-app-store.sh` archives with the paid team and uploads to App Store Connect. The App Store Connect API key is in the login Keychain; `SIGNING.local.md` says how it's stored. Never write it into the repo or print it; for other API calls, decode it into a `mktemp -d` file and delete it afterwards. Creating an app record and publishing App Privacy answers can only be done on the website.

- Signing uses Apple's cloud-managed distribution certificate: the account has no Apple Distribution certificate and the Mac holds no distribution key (only "Apple Development"). Don't create a distribution certificate or manual profiles; `-allowProvisioningUpdates` with the API key makes Xcode sign during export and manage the App Store profiles for the app and widget bundle IDs.
- The paid team is detected from Xcode accounts (the non-free team) or given with `TEAM_ID`. Don't hard-code it.
- The upload doesn't leave a local `.ipa` (`destination` is `upload`). To inspect the signature, export with `destination` `export` into a scratch directory instead.

### App Store Connect API

Everything after the upload can go through the API, which avoids the website (the user signs in there themselves; never sign in for them). In a scratchpad venv with `pyjwt`, `cryptography` and `requests`, read the key from the Keychain into memory (as `SIGNING.local.md` describes) and sign an ES256 JWT (`aud` `appstoreconnect-v1`, at most 20 minutes). Never write the key to the repo or print it.
- New version: create an `appStoreVersions` record (or PATCH `versionString` on the editable one), attach the build (`relationships/build`), set `usesNonExemptEncryption` false on the build, and fill `appStoreVersionLocalizations` (description, keywords, promotional text, what's new).
- Review notes: `appStoreReviewDetails` (`notes`, max 4000 characters). Give the reviewer an exact path to a group that has classes on the review date, not "the first entry".
- Submit: `reviewSubmissions` (platform IOS) → `reviewSubmissionItems` with the version → PATCH the submission `submitted: true`. To withdraw, PATCH `canceled: true`. Replying to App Review messages is web-only.
- Screenshots: `appScreenshotSets` per localization (`APP_IPHONE_67` holds the 1320×2868 shots). Each asset's `imageAsset.templateUrl` downloads the full-size image (`{w}`, `{h}`, `{f}` = png).

### Product page header and search results images (iOS 27+)

App Store Connect's "Header and Search Results" tab, next to "App Previews and Screenshots".
- Sizes: header 21:9 at 3840×1646, search results 3:2 from 1920×1280 up to 3840×2560 (JPEG/PNG), or one universal 16:9 PNG at 5244×2950 for both. There must be no alpha channel. Videos are 5–30 s at 30/60 fps, muted and looping.
- Apple's rules: one clear idea, a short localized phrase, the app's real UI; no prices, URLs, copyright symbols, other platforms' logos, awards or unverifiable claims; content suitable for 4+. The safe area is only in Apple's templates, so keep text and the main subject inside the middle ~70% of the width, and check with the Preview button.
- `docs/screenshots/store_assets.py <shots> <out>` draws both from the App Store screenshots (`<locale>-0/1/2.png` = Upcoming, Week, Details) with `frame.py`'s phone frames. The phrases are in its `TEXT`. Look at every image before uploading.
- Upload through the asset library: POST `appAssetLibraryImages` (`category` `CREATIVE_ASSETS`, `fileName`, `fileSize`, relationship `assetLibrary` → `appAssetLibraries` with the app's id) → PUT the bytes to each `uploadOperations` URL with only its `requestHeaders` (no bearer token) → PATCH `uploaded: true` (no checksum) → poll until `state` leaves `AWAITING_UPLOAD`/`UPLOAD_COMPLETE`. Then POST `appAssetLibraryPlacements` with `placementType` `PRODUCT_PAGE_HEADER_ASSET` or `APP_STORE_SEARCH_RESULTS_ASSET` and relationships `appStoreVersionLocalization` and `image`. Placements can't be edited: delete the old one of the same type first (`GET appStoreVersionLocalizations/{id}/placements`). `GET /v1/appAssetLibraryRefData` lists the valid types.
- Placements can only be created while the version is editable. With the version waiting for review the API answers 409 `STATE_ERROR.INVALID_STATE`, so add them before submitting, or to the next version.

## Live notification (Android) and Live Activity (iOS)

Both are up from the start of the day's first class to the end of the last one, and the button on Upcoming turns them on/off (same setting as the Settings switch).

- Android 17+ uses `Notification.MetricStyle` (platform API, not in NotificationCompat); Android 16 and older the `ProgressStyle` timeline. Metrics are narrow: a time as a value gets cut off with a 12-hour clock ("11:30 …"), and labels fit only about 12 characters, so the next class shows as "→ 11:30" over its room. The first metric is the critical one (the status bar chip); don't add a header timer, it repeats it.
- The notification removes itself at the end of the day with `setTimeoutAfter` (the alarms are inexact). That removal also fires the delete intent, so `dismissedByUser` ignores removals outside the class day.
- Test on the Android 17 emulator by moving its clock: `settings put global auto_time 0`, then `cmd alarm set-time <epoch ms>` (the app listens for `TIME_SET`). Unlock with `wm dismiss-keyguard`; show the lock screen with `locksettings set-disabled false` and `KEYCODE_SLEEP`/`KEYCODE_WAKEUP`. Check promotion with `dumpsys notification --noredact` (`PROMOTED_ONGOING`, `template=…MetricStyle`).
- iOS 26+ schedules the next class day's activity with `Activity.request(…, start:)` (state `.pending`); `.pending` needs `#available(iOS 26.0, *)`. Without a push server, iOS can't end an activity at an exact time: at the last class's end it shows "Done for today" until a background refresh or app launch ends it. Check scheduling in the simulator log: `log show --info --predicate 'subsystem == "it.mwojtowicz.PlanUbb"'`.

## Tests and checks

```sh
cd ios && xcodebuild -scheme PlanUbb -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath build -only-testing:PlanUbbTests test
cd android && ./gradlew :app:testDebugUnitTest :app:lintDebug
```

- Android needs `JAVA_HOME="$HOME/Applications/Android Studio.app/Contents/jbr/Contents/Home"` if no JDK is on PATH.
- Run lint after Android changes: `minSdk` is 29, and lint catches newer APIs (e.g. `Duration.toMinutesPart` is API 31) and missing translations.
- Stale build output can hide resource problems: an old file left in a test bundle once made a broken fixture path look fine. Delete the product (e.g. `build/Build/Products/Debug-iphonesimulator/PlanUbbTests.xctest`) when checking resource changes.

## User-facing text (English + Polish)

Every string must exist in both languages. Both apps follow the phone's language.

**iOS** — `ios/Shared/Localizable.xcstrings`, one catalog compiled into the app, the widget and the Live Activity.
- Literals in `Text`/`Label`/`Button`/`Section` are localized automatically. A `String` *variable* passed to them is not: build it with `String(localized: "…")`. That includes ternaries such as `cond ? "Rooms" : "Room"` — write `cond ? String(localized: "Rooms") : String(localized: "Room")`.
- Command-line builds don't update the catalog; edit it by hand. To get the exact keys (interpolations become `%@`, `%lld`), build with `SWIFT_EMIT_LOC_STRINGS=YES` and read the keys from the `*.stringsdata` JSON files under `build/Build/Intermediates.noindex`.
- Plurals with more than one argument use substitutions: value `"%#@classes@ · %2$@ h"` with a `classes` substitution (`argNum: 1`, `formatSpecifier: "lld"`, plural variations using `%arg`).
- Check the compiled result: `plutil -p …/PlanUbb.app/pl.lproj/Localizable.strings` (and `.stringsdict`), and the same in `PlugIns/PlanUbbWidget.appex/pl.lproj`.
- UI tests look for English labels, so every `XCUIApplication` launch passes `-AppleLanguages (en) -AppleLocale en_US`. Keep that in new UI tests.

**Android** — `res/values/strings.xml` and `res/values-pl/strings.xml`.
- Composables use `stringResource(R.string.…)`. Code without Compose (notification, widget, formatting helpers in `ui/Format.kt`) takes a `Context`.
- The data layer stays free of UI strings: `ClassEvent.kindNameRes` returns a resource id, `PlanTreeNode.shortName` takes `TreeLabels`, and errors are `ScheduleException` subclasses that `Throwable.userMessage(context)` turns into text. The view model keeps the `Throwable`, not a message.
- Dates use `formatSkeleton("EEEEdMMMM")` and similar helpers (locale-ordered patterns), never fixed `ofPattern` strings.
- Polish plurals need `one`, `few`, `many` and `other`.

**Polish wording already in use** — keep it consistent: Upcoming = Najbliższe, Week = Tydzień, Settings = Ustawienia, Now = Teraz, Next = Następne, Lecture = Wykład, Language class = Lektorat, Exercises = Ćwiczenia, Teacher(s) = Prowadzący, Semester/Group/Subgroup = Semestr/Grupa/Podgrupa, Live Activity = Aktywność na żywo, hours = godz.

To check a translation visually: iOS — `xcrun simctl launch <sim> it.mwojtowicz.PlanUbb -UITestPlan 142113 -AppleLanguages "(pl)" -AppleLocale pl_PL`, then `xcrun simctl io <sim> screenshot`. Android — the user's phone is set to Polish; `adb exec-out screencap -p`.

## README screenshots

Six framed images in `docs/screenshots/` (Upcoming, Week, class details × iOS, Android), made with `docs/screenshots/frame.py`. Its docstring has the full steps. In short:

1. **iOS**: `xcrun simctl status_bar <sim> override --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3`, then from `ios/` run `TEST_RUNNER_SCREENSHOT_DIR=<dir> xcodebuild … -only-testing:PlanUbbUITests/ScreenshotTests test`. Clear the override afterwards (`status_bar <sim> clear`).
2. **Android**: start the `Pixel_10_Pro` AVD headless (`emulator -avd Pixel_10_Pro -no-window -no-audio`, in the background), install with `DEVICE_ID=emulator-5554 BUILD_TYPE=debug android/install-on-device.sh`, grant `POST_NOTIFICATIONS`, open with `am start -n it.mwojtowicz.planubb/.ui.MainActivity --ei plan 142113` (debug builds only). Clean the status bar with demo mode (`settings put global sysui_demo_allowed 1`, then `am broadcast -a com.android.systemui.demo -e command …`: `enter`, `clock -e hhmm …`, `battery …`, `network -e mobile hide`). Find tap targets with `uiautomator dump`. Stop the emulator with `adb emu kill` when done.
3. **Frame**: Pillow isn't installed system-wide; make a venv in the scratchpad (`python3 -m venv … && pip install Pillow`), then `python frame.py ios <shots>` / `python frame.py android <shots>`. Look at the result on a dark background too.

Gotchas:
- In zsh, `E="-s emulator-5554"; adb $E …` doesn't split into two arguments. Use an array: `A=(adb -s emulator-5554); $A shell …`.
- This Android version ignores demo mode's `notifications -e visible false`: the app's own live notification and a "no screen lock" tip still show as icons.
- The two platforms show live data, so countdowns differ slightly between the shots.

## Git

- `.gitattributes` keeps `test-fixtures/**` byte for byte (some fixtures use CRLF) and `*.bat` with CRLF. Don't normalize them.
- Never commit `local.properties`, build output, or signing keys. The debug keystore lives in `~/.android`, outside the repo.
- Commit and push only when the user asks.
