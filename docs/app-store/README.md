# App Store version metadata

Promotional text and release notes ("What's New") for every App Store version, starting with 1.3.

```
docs/app-store/<version>/<locale>/promotional_text.txt   # max 170 chars
docs/app-store/<version>/<locale>/release_notes.txt      # max 4000 chars
```

`<locale>` is the App Store Connect locale code: `en-US`, `ru`, `de-DE`, `es-ES`, `fr-FR`, `it`, `ja`, `ko`, `nl-NL`, `pl`, `pt-BR`, `sv`, `tr`, `uk`, `zh-Hans`, `ar-SA`.

## Uploading

[`scripts/asc_metadata.py`](../../scripts/asc_metadata.py) writes the texts to the version's localizations through the App Store Connect API. It needs an API key with the App Manager or Admin role:

```bash
export ASC_KEY_ID=... ASC_ISSUER_ID=...
# key file: ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8, or set ASC_KEY_PATH

scripts/asc_metadata.py 1.3 --locales en-US,ru           # dry run: shows current vs new texts
scripts/asc_metadata.py 1.3 --locales en-US,ru --apply   # sends them
```

- The version must already exist in App Store Connect.
- Locales the version does not have yet are skipped unless `--create-missing` is passed.
- Release notes can only be changed until the version passes review; promotional text can be changed at any time.

## Screenshots

[`scripts/asc_screenshots.py`](../../scripts/asc_screenshots.py) replaces one device's screenshots in every locale. It reads `docs/app-store/<version>/screenshots/<device>/<folder>/<subfolder>/Screen<N>/*.png`, where `<folder>` is the app's localization folder (`en`, `de`, `pt-BR`, …), and uses the same API key:

| `--device` | Subfolder | Display type | Size |
|---|---|---|---|
| `iphone` (default) | `iPhone` | `APP_IPHONE_65` | 1284×2778 |
| `ipad` | `iPad` | `APP_IPAD_PRO_3GEN_129` | 2752×2064 |
| `duo` | `iPhone Duo` | `APP_IPHONE_DUO` (undocumented, holds both displays) | 1398×2034 |

```bash
scripts/asc_screenshots.py 1.3 --device ipad                          # dry run: current sets vs new files
scripts/asc_screenshots.py 1.3 --device ipad --locales en,ru --apply  # upload, then delete the old ones
```

An interrupted run can be repeated: screenshots already uploaded with the same content are reused.
