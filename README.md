# ZenSave (Unscroll) for iOS

A native SwiftUI port of the ZenSave / Unscroll web prototype. It notices when you've spent too long in an app like Instagram and nudges you with:

> You spent 20 min in Instagram and it is time to switch to Imprint or the gym.

…then asks what you did instead and tracks your switching habit.

## Getting started

Requirements: a Mac with Xcode 16+ (Xcode 26 to get the on-device AI coach) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
cd ZenSave
xcodegen            # creates ZenSave.xcodeproj from project.yml
open ZenSave.xcodeproj
```

Run the **ZenSave** scheme on the simulator. The app starts in **demo mode**, which works like the web prototype: tap *Scroll* on an app to fake a session, and the nudge appears when you reach the limit. Run the logic tests with `swift test` in `Packages/ZenCore`.

> The shared code in `Packages/ZenCore/Sources/ZenCore` is compiled directly into both the app and the extension, rather than linked as a Swift package. Xcode can't resolve local packages when the project's path contains an `@` (as in `/Users/name@company.com/...`).

### Running on an iPhone (real tracking)

Screen Time doesn't work in the simulator, so you need a real device.

1. Replace `com.yourcompany` in `project.yml` with your own reverse-DNS prefix, and set `DEVELOPMENT_TEAM` to your team ID.
2. Change the App Group to match, in two places: `project.yml` (both targets) and `SharedStore.appGroupID` in `Packages/ZenCore/Sources/ZenCore/SharedStore.swift`.
3. Run `xcodegen` again, then build to your phone. Under *Signing & Capabilities* Xcode should show **Family Controls**, **App Groups** and **Time Sensitive Notifications** on both targets.
4. In the app: Today → **Turn on Screen Time** → allow. Then on the Limits tab, tap **Pick app** for each entry and choose the real app (e.g. Instagram).

> **App Store distribution:** the Family Controls entitlement works for development builds right away. To ship on TestFlight or the App Store, you have to request the distribution entitlement from Apple (Account → *Family Controls (Distribution)* request form), separately for the app and for the extension bundle ID. Request it early, because approval can take a while.

## How it works

```
┌────────────── ZenSave (app) ──────────────┐        ┌──── ZenSaveMonitor (extension) ────┐
│ SwiftUI tabs: Today · Limits · Switch to  │        │ DeviceActivityMonitor               │
│ · Goals · Week                            │        │ runs in the background, even when   │
│                                           │        │ the app is closed                   │
│ ScreenTimeManager                         │ events │                                     │
│  - FamilyActivityPicker per tracked app   │──────▶│ "ig.5", "ig.10" … "ig.20" reached    │
│  - schedules daily DeviceActivity events  │        │  → SharedStore.reportUsage()        │
│    every 5 min up to each limit           │        │  → at the limit: posts the nudge    │
│                                           │        │    notification with buttons        │
│ AppDelegate: notification buttons record  │◀───────│                                     │
│ the choice; tapping opens the in-app nudge│        └─────────────────────────────────────┘
│ + AI suggestion                           │
└───────────────────┬───────────────────────┘
                    │ both link
            ┌───────▼────────┐
            │ ZenCore (SPM)  │  nudge rules, weekly summary, habit tracker,
            │                │  App Group store — Foundation only, unit tested
            └────────────────┘
```

| Web prototype | iOS |
|---|---|
| `src/lib/nudge.ts` | `Packages/ZenCore/Sources/ZenCore/Nudge.swift` (same rules, same tests) |
| `src/test/nudge.test.ts` | `Packages/ZenCore/Tests/ZenCoreTests/NudgeTests.swift` |
| `localStorage` | `SharedStore` (App Group `UserDefaults`, shared with the extension) |
| Fake scroll timer | Demo mode (`AppModel.toggleScroll`) |
| The tracking itself (not possible on the web) | `ScreenTimeManager` + `ZenSaveMonitor` extension |
| In-page nudge banner | Real notification with "What did you do instead?" buttons, plus `NudgeBanner` in the app |
| `suggest.functions.ts` (OpenAI through Lovable's gateway) | `SuggestionService` using Apple's on-device Foundation Models (no key, no server) |
| Tailwind tokens in `styles.css` | `Theme.swift` |

### Things worth knowing about Screen Time

- **iOS never tells the app which app a token is.** That's why each tracked entry has a name you type ("Instagram") next to the app you pick. The name is what shows in the nudge.
- **Usage arrives in 5-minute steps.** The extension only learns "threshold reached", so Today's numbers move in 5-minute increments, and the nudge fires exactly at the limit. Change `ScreenTimeEvent.step` for finer steps (each step adds one event per app).
- **One nudge per app per day**, the same as the prototype.
- The extension has a ~6 MB memory budget, so it only does the bookkeeping and the notification. The AI suggestion runs in the app when you tap the notification.

## Project layout

```
project.yml                     XcodeGen spec (targets, entitlements, Info.plist keys)
Packages/ZenCore/               shared logic (compiled into both targets) + `swift test` tests
ZenSave/
  ZenSaveApp.swift              app entry, notification handling
  AppModel.swift                state + actions (the prototype's Index component)
  Theme.swift                   colors, card/pill styles
  Services/                     ScreenTimeManager, NotificationManager, SuggestionService
  Views/                        RootView (tabs, nudge banner), Today, Limits, Switch, Coach, Week
  Assets.xcassets               app icon (placeholder), accent + launch colors
ZenSaveMonitor/                 DeviceActivityMonitor extension
```

## Next steps

- **Fonts:** the prototype uses Instrument Serif and Manrope (free from Google Fonts). Add the `.ttf` files to `ZenSave/`, list them under `UIAppFonts` in `project.yml`, and `Theme.display` picks Instrument Serif up automatically.
- **Exact usage charts:** a `DeviceActivityReport` extension can show precise per-app minutes and charts on the Today tab.
- **Harder nudge:** a `ShieldConfiguration` extension plus `ManagedSettingsStore` can put a "Time to switch" screen over Instagram at the limit, instead of just a notification.
- **Widgets:** the streak and today's minutes are already in the App Group, so a WidgetKit extension can read them directly.
- **Real app icon** to replace the placeholder "U".
