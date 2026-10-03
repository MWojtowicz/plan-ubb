---
name: plan-ubb-dev
description: Workflows for the Plan UBB repo (iOS app in ios/, Android app in android/). Use when installing the app on the connected iPhone or Android phone, running the tests, adding or changing user-facing text (English + Polish translations), or retaking the framed README screenshots.
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

`android/build-release.sh` builds `android/build/release/plan-ubb-<version>.apk`, signed with the release key `~/.android/planubb-release.jks`. Its password is in the Keychain item `planubb-release-keystore`; never print it or put it in the repo. If the keystore is missing but the Keychain item exists, stop and ask the user to restore the backup. Don't create a new key: installed copies couldn't be updated. Release and debug-signed installs can't replace each other.

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
