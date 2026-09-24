# Analytics

Amplitude runs on both platforms with one configuration, and only in a build
carrying the real key — the placeholder in `Secrets.swift` leaves it off, so debug
builds and `build.yml` never send anything.

| | iOS | Android |
|---|---|---|
| SDK | AmplitudeSwift | `com.amplitude:analytics-android` |
| Started from | the `amplitude` global in `iOS/FurAffinityApp.swift` | `startAnalytics()` in `Helpers/Android/Analytics+Android.swift`, from `FurAffinityUIAppDelegate.onInit` |
| Autocapture | sessions, app lifecycles | the same |
| Not collected | city, region, carrier, DMA, IP address, IDFV | city, region, carrier, DMA, IP address, latitude/longitude, advertising id, app set id |

No custom events are logged on either. The Android device id is the SDK's random
one: `useAdvertisingIdForDeviceId` and `useAppSetIdForDeviceId` stay false. Both
platforms log `Amplitude is initialized` or `Amplitude is left uninitialized` at
startup.

`FAAnalyticsBridge.kt` is reached by class name through `AnyDynamicObject`, like
`FACrashReportingBridge`, so its `start` returns `Boolean` (AnyDynamicObject cannot
resolve a void overload) and R8 keeps it through `-keep class fur.affinity.ui.**`.
A debuggable build turns the SDK's logcat output up to `DEBUG`, which shows each
upload to `api2.amplitude.com` and its response.

To check the Android path without touching the production project, build a debug
app with any 32-character key in place of the placeholder: the SDK starts, logs its
lifecycle events, and `api2.amplitude.com` answers `Invalid API key`.
