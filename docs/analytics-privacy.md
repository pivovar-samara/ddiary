# Analytics privacy: App Store Connect answers and console settings

What has to be true in App Store Connect and in the Firebase / GA4 consoles for the published
privacy policy to be accurate and for the app to pass review, plus the reasoning behind each
answer so it does not have to be re-derived.

The privacy policy and support pages themselves live on Notion:
https://circular-drug-3ff.notion.site/DIA-ry-Legal-3338f966e50380bf8a74f62e3d3761a8

## 1. App Store Connect -> App Privacy -> Data Types

| Category | Data type | Purpose | Linked to user | Used for tracking | Comes from |
|---|---|---|---|---|---|
| Usage Data | Product Interaction | Analytics | **Yes** | No | Amplitude + Firebase Analytics |
| Identifiers | Device ID | Analytics | **Yes** | No | Amplitude device ID + Firebase app-instance ID |
| Diagnostics | Crash Data | App Functionality | No | No | Firebase Crashlytics |
| Diagnostics | Other Diagnostic Data | App Functionality | No | No | Crashlytics + Firebase Installations |

"Linked to user" is Yes on the first two because both SDKs attach a persistent per-install
device identifier to every event. No account identifier is involved — `setUserId` / `setUserID`
is never called in either SDK.

### The app's own `PrivacyInfo.xcprivacy` must mirror those two rows

`DDiary/Resources/PrivacyInfo.xcprivacy` declares Product Interaction and Device ID, both
`Linked = true`, `Tracking = false`, purpose Analytics — deliberately the same as the table
above. Keep them in sync; a shipped manifest that disagrees with the App Store answers is worse
than either one being wrong on its own.

Device ID in particular cannot be left to the SDKs. Amplitude declares its own device ID, but
**Firebase Analytics ships no manifest at all**, so without this entry the Firebase app-instance
ID would be declared nowhere in the bundle. The tempting rule "only declare what the app's own
code collects, let each SDK declare its own" breaks down precisely because one of the SDKs
declares nothing.

Crash Data and Other Diagnostic Data are *not* repeated in the app manifest: Crashlytics and
Installations do declare those themselves, so the aggregated report already carries them.

### Coarse Location: declared by Amplitude's manifest, deliberately NOT declared here

`Amplitude-Swift`'s bundled `PrivacyInfo.xcprivacy` declares `CoarseLocation` as linked to the
user, so it will appear in the aggregated Privacy Report. We do not declare it in App Store
Connect, and this is why:

- Amplitude's manifest is explicitly a **default**. Their docs say: "Amplitude sets the privacy
  manifest based on a default configuration. Update the privacy manifest according to your
  configuration and your app."
  https://amplitude.com/docs/sdks/analytics/ios/ios-swift-sdk#apple-privacy-manifest
- Amplitude defines its own Coarse Location as "Country, region, and city based on IP address.
  Amplitude doesn't collect them from device GPS or location features." That basis does not
  apply to us: `enableCoppaControl = true` suppresses `ip_address`, so `event.ip` is never set
  to `$remote` and the server has nothing to derive geography from.
- Verified in `Amplitude-Swift` 1.15.5 sources: `ContextPlugin` never populates `city`, `region`,
  `dma` or latitude/longitude at all — those fields only ever come from server-side IP lookup.
  `TrackingOptions.forCoppaControl()` disables `idfa`, `idfv`, `city` and `ip_address`.
- The one location-adjacent value that is still sent is `country`, and it comes from
  `Locale.current.regionCode` (`ContextPlugin.swift:79`) — the user's device region setting, not
  a measurement of where the device is. A device set to another region reports that region.

If this ever needs to be airtight rather than merely defensible, add `.disableTrackCountry()` to
the `TrackingOptions` chain in `AmplitudeAnalyticsEventSink` and nothing location-adjacent leaves
the device. The cost is losing the country breakdown in Amplitude reports.

**Do not declare:**

- *Performance Data* — Crashlytics does not declare it and `FirebasePerformance` is not linked.
- *User ID* — `setUserID` is never called, in either SDK.
- *Health & Fitness* — unaffected by this change. Check what is already declared and leave it alone.
- *Coarse Location* — see the section above.

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
