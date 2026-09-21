# App Privacy (App Store Connect) and Firebase console settings

Not a Notion page. This is what has to be true in App Store Connect and in the Firebase / GA4
consoles for the Privacy Policy to be accurate and for the app to pass review.

## 1. App Store Connect -> App Privacy -> Data Types

| Category | Data type | Purpose | Linked to user | Used for tracking | Comes from |
|---|---|---|---|---|---|
| Usage Data | Product Interaction | Analytics | **Yes** | No | Amplitude SDK manifest + Firebase |
| Identifiers | Device ID | Analytics | **Yes** | No | Amplitude SDK manifest + Firebase app-instance ID |
| Location | Coarse Location | Analytics | **Yes** | No | Amplitude SDK manifest |
| Diagnostics | Crash Data | App Functionality | No | No | Firebase Crashlytics |
| Diagnostics | Other Diagnostic Data | App Functionality | No | No | Crashlytics + Firebase Installations |

**Why "Linked to user = Yes" on the first three.** That is not our runtime configuration, it is
what `Amplitude-Swift`'s bundled `PrivacyInfo.xcprivacy` statically declares. The manifest ships
inside the package and lands in the app's aggregated Privacy Report no matter how we configure
the SDK at runtime, and reviewers compare the App Store answers against that report. Arguing
"but we disable city collection" does not help — the report says otherwise.

Worth raising with Amplitude separately: with `enableCoppaControl = true` the SDK does not send
`city` or `ip_address`, so the Coarse Location declaration overstates what actually happens.

**Do not declare:**

- *Performance Data* — Crashlytics does not declare it and `FirebasePerformance` is not linked.
- *User ID* — `setUserID` is never called, in either SDK.
- *Health & Fitness* — unaffected by this change. Check what is already declared and leave it alone.

**"Data Used to Track You" must stay empty.** `NSPrivacyTracking` is `false` in
`DDiary/Resources/PrivacyInfo.xcprivacy`, AdSupport is not linked, and IDFV collection is off.

**Before each submission:** generate the Privacy Report from the archive (Xcode Organizer ->
Generate Privacy Report) and reconcile the answers above with it.

**The report does not cover Firebase Analytics.** `GoogleAppMeasurement.xcframework`,
`FirebaseAnalytics.xcframework` and `GoogleAdsOnDeviceConversion.xcframework` ship **no**
`PrivacyInfo.xcprivacy` — verified against the signed archives on `dl.google.com` for 12.19.2.
Only Crashlytics, Installations, GoogleDataTransport, GoogleUtilities and Amplitude contribute
declarations. So the Product Interaction and Device ID rows above have to be justified from
Google's own documentation rather than from the report:
https://firebase.google.com/docs/ios/app-store-data-collection

To dump every manifest that actually ships in the app bundle:

```bash
APP=<path to DDiary.app>
find "$APP" -name "*.xcprivacy" -not -path "*/PlugIns/*" -exec sh -c \
  'echo "== ${1#$APP/}"; plutil -p "$1" | grep -E "DataType\"|Linked|Tracking"' _ {} \;
```

## 2. Firebase / Google Analytics 4 console

Without these, the declarations above become false.

1. **Google signals: OFF** — Analytics -> Admin -> Data Settings -> Data Collection.
   Critical: enabling it makes "Used for Tracking" = Yes and breaks `NSPrivacyTracking = false`.
2. **Event data retention: 2 months**; "Reset user data on new activity" off.
   Analytics -> Admin -> Data Settings -> Data Retention.
3. **Granular location and device data collection: OFF for all regions** —
   removes city/coordinate derivation from the IP address.
4. **Uncheck every Google data-sharing option** — Admin -> Account Settings:
   Google products & services, benchmarking, technical support, account specialists.
5. **Do not link** the property to Google Ads, AdMob, or any advertising product.
6. **Accept the Google Ads Data Processing Terms** and fill in the GDPR representative details —
   Project settings -> Data processing.
7. **Register custom dimensions and metrics**, otherwise event parameters are invisible in GA4:
   - custom dimensions: `kind`, `reason`, `result`
   - custom metrics: `success_count`, `failure_count`

## 3. Event reference

Eleven events, identical in Amplitude and Firebase. Defined in
`DDiary/Repository/Analytics/AnalyticsEventFactory.swift`.

| Event | Parameters |
|---|---|
| `app_open` | — |
| `measurement_logged` | `kind`: `bp` \| `glucose` |
| `measurement_save_failed` | `kind`, `reason` |
| `schedule_updated` | `kind` |
| `schedule_update_failed` | `kind`, `reason` |
| `export_csv` | — |
| `gsheets_sync_success` | — |
| `gsheets_sync_failure` | `reason` (omitted when blank) |
| `gsheets_sync_finished` | `success_count`, `failure_count`, `result`: `success` \| `failure` \| `partial` |
| `gsheets_enabled` | — |
| `gsheets_disabled` | — |

`reason` is always one of `google_invalid_grant`, `row_sync_failed`, `network`, `auth`, `unknown` —
raw error text never leaves the device. See `AnalyticsEventFactory.normalizeReason`.

The five `gsheets_*` events were called `google_*` until this change. `google_` is a reserved GA4
prefix, so Firebase would have dropped them. Amplitude charts built on the old names need
rebuilding, or a union of both names during the transition.

Firebase also collects its own automatic events that cannot be disabled while Analytics is on:
`first_open`, `session_start`, `user_engagement`, `app_update`, `os_update`, `app_remove`.
`screen_view` **is** disabled, via `FirebaseAutomaticScreenReportingEnabled = NO`.
