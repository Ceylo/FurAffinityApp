# Driving the iOS app on the simulator

An agent can run, tap through and inspect the app on its own, on the worktree's
simulator (`Scripts/iOS/simulator.sh`).

## Taps and screenshots

Xcode's MCP tools, with Xcode running:

1. `DeviceInteractionStartSession` with the simulator's UDID and a session name. A name
   cannot be reused for a while after its session ends; pick a new one.
2. `DeviceInteractionSynthesize` with no command captures a screenshot and the
   accessibility hierarchy — read the hierarchy for coordinates, not the screenshot.
   `t <x> <y>` taps, in points, at an element's `hitPoint`. SpringBoard's alerts and
   notification banners are in the hierarchy too.
3. `DeviceInteractionEndSession` when done.

`xcodebuildmcp ui-automation` does not work with Xcode 27.2, which moved SimulatorKit.

## Setting up

- **Install:** `xcodebuild build -scheme FurAffinity -destination "id=$UDID"`, then
  `xcrun simctl install` the `.app` and `xcrun simctl launch $UDID com.example.id1234`.
- **Login:** copy another simulator's `Library/Caches/SessionCookies/*` into the app
  container (`xcrun simctl get_app_container $UDID com.example.id1234 data`) while the
  app is stopped. Its `cf_clearance` is usually stale, so the first launch goes through a
  Cloudflare challenge, which tends to clear by itself.
- **Logs:** `xcrun simctl spawn $UDID log show --last 1m --info --predicate
  'process == "Fur Affinity" AND subsystem == "com.example.id1234"'`.

## Reaching a screen

- **Deep link:** `xcrun simctl openurl $UDID
  "furaffinity-app-navigation://www.furaffinity.net/view/<id>/"`, then tap *Ouvrir* on
  the system prompt. A prompt that appears meanwhile (notification permission) swallows
  the link; send it again.
- **Notification tap:** `xcrun simctl push $UDID com.example.id1234 payload.json`, with
  `NotificationDeepLink`'s keys beside an `aps` alert. A banner only shows while the
  app is not in the foreground (`xcrun simctl launch $UDID com.apple.Preferences`) and
  lasts a few seconds: push, then tap it with no capture in between.

## Arranging state

- **Image cache:** a Kingfisher disk entry's modification date is its *expiry*: give a
  file planted in the cache a future one (`touch -t`), or Kingfisher treats it as
  missing.
- **Cookies:** attach with `xcrun lldb -p <pid> --batch -s script.lldb`, where the
  script runs Objective-C on `NSHTTPCookieStorage.sharedHTTPCookieStorage` (a bogus
  `cf_clearance` forces a Cloudflare challenge) and ends with `detach`. The pid is in
  `xcrun simctl spawn $UDID launchctl list`.
