# App privacy: App Store Connect answers, data flows and console settings

Everything needed to fill in the App Privacy questionnaire without re-deriving it: the analytics
and diagnostics the SDKs collect, the app's own data flows, and what has to be true in the
Firebase / GA4 consoles for the published privacy policy to stay accurate.

This is engineering analysis of what the code actually does, not legal advice.

The privacy policy and support pages themselves live on Notion:
https://circular-drug-3ff.notion.site/DIA-ry-Legal-3338f966e50380bf8a74f62e3d3761a8

## 1. App Store Connect -> App Privacy -> Data Types

| Category | Data type | Purpose | Linked to user | Used for tracking | Comes from |
|---|---|---|---|---|---|
| Usage Data | Product Interaction | Analytics | **Yes** | No | Amplitude + Firebase Analytics |
| Identifiers | Device ID | Analytics | **Yes** | No | Amplitude device ID + Firebase app-instance ID |
| Diagnostics | Crash Data | App Functionality | No | No | Firebase Crashlytics |
| Diagnostics | Other Diagnostic Data | App Functionality, **Analytics** | No | No | Crashlytics (App Functionality); Firebase Installations and GoogleDataTransport (Analytics) |

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
- *Health & Fitness* — the health values never reach analytics, and the Google Sheets flow that does carry them is not developer-accessible. Reasoned through in section 2.
- *Coarse Location* — see the section above.

**"Data Used to Track You" must stay empty.** `NSPrivacyTracking` is `false` in
`DDiary/Resources/PrivacyInfo.xcprivacy`, AdSupport is not linked, and IDFV collection is off.

**Before each submission:** generate the Privacy Report from the archive (Xcode Organizer ->
Generate Privacy Report) and reconcile the answers above with it.

### Reading the Privacy Report

The report groups entries by the same categories App Store Connect uses. Each data type lists
every bundle that declares it — so one type can appear several times, once per SDK — with that
source's purposes and two columns, *Tracking* and *Linked*.

App Store Connect wants one answer per data type, for the **whole app including every SDK** —
not just what our own manifest declares. Collapse the rows like this:

- **Linked**: Yes if *any* source says Yes.
- **Tracking**: Yes if *any* source says Yes.
- **Purposes**: the union of all sources' purposes.

Then apply the two known adjustments, both explained above: drop Coarse Location (Amplitude
declares it for a configuration we do not run), and remember that Firebase Analytics appears
only through `DDiary.app`'s own manifest because it ships none of its own.

The report as of Firebase 12.19.2 / Amplitude-Swift 1.15.5, and what it collapses to:

| Report row(s) | Sources | → App Store Connect |
|---|---|---|
| Location · Coarse Location · Analytics · Linked | Amplitude | not declared — see "Coarse Location" above |
| Identifiers · Device ID · Analytics · Linked | Amplitude, DDiary.app | Device ID · Analytics · Linked · not tracking |
| Usage Data · Product Interaction · Analytics · Linked | Amplitude, DDiary.app | Product Interaction · Analytics · Linked · not tracking |
| Diagnostics · Crash Data · App Functionality · not linked | Crashlytics | Crash Data · App Functionality · not linked · not tracking |
| Diagnostics · Other Diagnostic Data · App Functionality / Analytics · not linked | Crashlytics; Installations, GoogleDataTransport | Other Diagnostic Data · App Functionality **and** Analytics · not linked · not tracking |

The Other Diagnostic Data purposes are the easy one to get wrong: Crashlytics declares App
Functionality, but Installations and GoogleDataTransport declare Analytics, so both must be ticked.

If a future SDK update adds a row that is not in this table, that is a change to review, not a
formality — rerun the report after every dependency bump.

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

## 2. The app's own data flows

None of these appear in any privacy manifest — not ours and not the SDKs' — because manifests
only describe what someone wrote into them. The Privacy Report cannot answer this part, so it has
to be reasoned about directly.

**Apple's test.** Data counts as *collected* when it is transmitted off the device in a way that
lets the developer, or the developer's third-party partners, access it for longer than it takes
to service the request in real time. Storage the developer cannot read is not collection.
See <https://developer.apple.com/app-store/app-privacy-details/>.

| Flow | What leaves the device | Who can read it | Collected? |
|---|---|---|---|
| Local SwiftData store | nothing | the user | No |
| iCloud / CloudKit | all records | the user's Apple account only — the container uses `cloudKitDatabase: .private`, and developers have no access to private databases | No |
| Google Sheets backup (opt-in) | BP: systolic, diastolic, pulse, timestamp, comment. Glucose: value, unit, measurement type, meal slot, timestamp, comment | the user's own Google account | **Judgment call — see below** |
| CSV export | nothing, by us | a file is written to the app's temporary directory and handed to the share sheet; the user picks the destination | No |
| Google OAuth | authorization code and token exchange with Google | Google, as the identity provider. The refresh token is stored in the device Keychain and never reaches us | No |
| Integration metadata | spreadsheet ID, Google account identifier | stored in SwiftData, so it follows the same private CloudKit path as the records | No |

### Google Sheets: recommendation is *not* to declare Health & Fitness

The health values genuinely leave the device, so this deserves an explicit answer rather than an
assumption. Four facts decide it:

1. **There is no developer backend.** The only hosts the app ever contacts are
   `sheets.googleapis.com`, `oauth2.googleapis.com`, Amplitude's and Firebase's. Nothing is ours.
2. **The OAuth scope is `drive.file` only** — access limited to files the app itself created, not
   the user's wider Drive.
3. **The refresh token lives in the device Keychain**, deliberately not in SwiftData/CloudKit, so
   there is no path by which it could reach us.
4. **The spreadsheet is created in the user's own Drive and owned by them.** They can read, share
   or delete it; we cannot.

So at no point can the developer access the data. Google holds it as the storage provider the
*user* chose, at the user's direction, rather than as our partner — which is what Apple's
definition turns on.

**The counter-argument, stated fairly:** the data does leave the device, it does land with a
third party, and a reviewer could read "third-party partners" more broadly than we do. If you
would rather not argue the point at review time, declaring Health & Fitness (App Functionality,
not linked, not used for tracking) is the conservative answer and costs nothing but a line on the
product page. Either answer is defensible; what is not defensible is answering without deciding.

**What would flip this to "collected", so watch for it:**

- adding any server-side component that touches the records or the OAuth token;
- broadening the OAuth scope beyond `drive.file`;
- writing to a spreadsheet the developer owns or has been shared on;
- any analytics event carrying a measurement value. `AnalyticsEventFactory` is the only place a
  value becomes an event property, and `normalizeReason` collapses free-form error text to a
  closed set — that is what keeps this true, and it is why those two stay together.

Regardless of how the App Store question is answered, the privacy policy has to describe these
flows, and it does.

## 3. Firebase / Google Analytics 4 console

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

## 4. Event reference

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
