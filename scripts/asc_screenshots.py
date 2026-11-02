#!/usr/bin/env python3
"""Replace App Store screenshots of one device class through the App Store Connect API.

Screenshots live in docs/app-store/<version>/screenshots/<device>/<folder>/<device_dir>/Screen<N>/*.png,
where <folder> is the app's localization folder (en, de, pt-BR, ...) and maps to an ASC locale.
Screen<N> sets the order on the product page.

Dry run by default: prints the screenshot sets each locale has now and what would be replaced.
Pass --apply to upload the new screenshots and delete the old ones of that display type.

Auth is the same as scripts/asc_metadata.py (ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH).

Usage:
  scripts/asc_screenshots.py 1.3                        # dry run, iPhone 6.5", all locales
  scripts/asc_screenshots.py 1.3 --device ipad          # dry run, iPad 13"
  scripts/asc_screenshots.py 1.3 --device duo --apply   # iPhone Duo outer display
"""

import argparse
import hashlib
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request
from pathlib import Path

from asc_metadata import BUNDLE_ID, EDITABLE_STATES, ROOT, Client

# Localization folder name -> App Store Connect locale code, where they differ.
ASC_LOCALES = {"en": "en-US", "de": "de-DE", "es": "es-ES", "fr": "fr-FR", "nl": "nl-NL", "ar": "ar-SA"}
DEVICES = {
    # device folder: (subfolder inside each locale, display type, accepted sizes)
    "iphone": ("iPhone", "APP_IPHONE_65", {(1284, 2778), (1242, 2688)}),
    "ipad": ("iPad", "APP_IPAD_PRO_3GEN_129", {(2752, 2064), (2064, 2752), (2732, 2048), (2048, 2732)}),
    # Not in Apple's API docs yet; one set holds both the outer and the inner display shots.
    "duo": ("iPhone Duo", "APP_IPHONE_DUO", {(1398, 2034), (2034, 1398), (2007, 2853), (2853, 2007)}),
}
MAX_PER_SET = 10


def png_info(path: Path):
    """Width, height and whether the PNG declares an alpha channel (IHDR color type 4 or 6)."""
    head = path.read_bytes()[:26]
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        sys.exit(f"Not a PNG: {path}")
    return int.from_bytes(head[16:20], "big"), int.from_bytes(head[20:24], "big"), head[25] in (4, 6)


def load_screens(version: str, device: str, folders):
    subdir, _, sizes = DEVICES[device]
    base = ROOT / "docs" / "app-store" / version / "screenshots" / device
    if not base.is_dir():
        sys.exit(f"No screenshots folder: {base}")
    available = sorted(p.name for p in base.iterdir() if (p / subdir).is_dir())
    screens, errors = {}, []
    for folder in folders or available:
        screen_dirs = sorted((base / folder / subdir).glob("Screen*"), key=lambda p: int(p.name[6:] or 0))
        files = []
        for d in screen_dirs:
            pngs = sorted(d.glob("*.png"))
            if len(pngs) != 1:
                errors.append(f"{folder}: {d.name} must hold exactly one PNG, found {len(pngs)}")
                continue
            w, h, _ = png_info(pngs[0])
            if (w, h) not in sizes:
                errors.append(f"{folder}: {pngs[0].name} is {w}×{h}, expected one of {sorted(sizes)}")
            files.append(pngs[0])
        if not files:
            errors.append(f"{folder}: no screenshots in {base / folder / subdir}")
        elif len(files) > MAX_PER_SET:
            errors.append(f"{folder}: {len(files)} screenshots, max {MAX_PER_SET}")
        screens[ASC_LOCALES.get(folder, folder)] = files
    if errors:
        sys.exit("\n".join(errors))
    return screens


def opaque_copy(path: Path, tmp: Path) -> Path:
    """App Store Connect wants screenshots without transparency; drop the alpha channel if there is one."""
    if not png_info(path)[2]:
        return path
    if not shutil.which("magick"):
        sys.exit(f"{path} has an alpha channel; install ImageMagick (brew install imagemagick) to flatten it.")
    out = tmp / f"{path.parent.parent.parent.name}-{path.parent.name}-{path.name}"
    # Without date chunks the output is byte-identical between runs, so its checksum finds earlier uploads.
    subprocess.run(["magick", str(path), "-background", "white", "-alpha", "remove", "-alpha", "off",
                    "-define", "png:exclude-chunk=date,time", str(out)], check=True)
    return out


def upload(api: Client, set_id: str, path: Path, name: str) -> str:
    data = path.read_bytes()
    shot = api.request("POST", "/v1/appScreenshots", body={"data": {
        "type": "appScreenshots",
        "attributes": {"fileName": name, "fileSize": len(data)},
        "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}},
    }})["data"]
    for op in shot["attributes"]["uploadOperations"]:
        chunk = data[op["offset"]:op["offset"] + op["length"]]
        headers = {h["name"]: h["value"] for h in op.get("requestHeaders") or []}
        req = urllib.request.Request(op["url"], data=chunk, method=op["method"], headers=headers)
        with urllib.request.urlopen(req) as resp:
            resp.read()
    api.request("PATCH", f"/v1/appScreenshots/{shot['id']}", body={"data": {
        "type": "appScreenshots", "id": shot["id"],
        "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()},
    }})
    return shot["id"]


def wait_processed(api: Client, ids, timeout=20 * 60):
    """Polls until every screenshot is processed; returns {id: problem} for the failed and the still pending."""
    pending, problems = set(ids), {}
    deadline = time.time() + timeout
    while pending and time.time() < deadline:
        for shot_id in list(pending):
            state = api.get(f"/v1/appScreenshots/{shot_id}")["data"]["attributes"]["assetDeliveryState"]
            if state["state"] == "COMPLETE":
                pending.discard(shot_id)
            elif state["state"] == "FAILED":
                pending.discard(shot_id)
                problems[shot_id] = f"failed: {state.get('errors')}"
        if pending:
            print(f"  waiting for {len(pending)} screenshot(s) to be processed…")
            time.sleep(10)
    problems.update({shot_id: "still processing" for shot_id in pending})
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("version", help="App Store version string, e.g. 1.3")
    parser.add_argument("--device", default="iphone", choices=sorted(DEVICES))
    parser.add_argument("--locales", help="Comma-separated localization folders (en,ru,pt-BR,...); default: all")
    parser.add_argument("--display-type", help="Override the screenshot display type, e.g. APP_IPHONE_65")
    parser.add_argument("--apply", action="store_true", help="Upload and replace (default is a dry run)")
    parser.add_argument("--delete-first", action="store_true",
                        help="With --apply: delete old screenshots before uploading when both do not fit in a set")
    args = parser.parse_args()

    display_type = args.display_type or DEVICES[args.device][1]
    screens = load_screens(args.version, args.device, args.locales.split(",") if args.locales else None)
    api = Client()

    apps = api.get("/v1/apps", **{"filter[bundleId]": BUNDLE_ID})["data"]
    if not apps:
        sys.exit(f"No app with bundle ID {BUNDLE_ID} visible to this API key.")
    versions = api.get(f"/v1/apps/{apps[0]['id']}/appStoreVersions", **{
        "filter[versionString]": args.version, "filter[platform]": "IOS"})["data"]
    if not versions:
        sys.exit(f"Version {args.version} does not exist in App Store Connect yet. Create it there first.")
    version = versions[0]
    state = version["attributes"].get("appStoreState") or version["attributes"].get("appVersionState")
    if state not in EDITABLE_STATES:
        sys.exit(f"Screenshots cannot be changed in state {state}.")

    localizations = {
        loc["attributes"]["locale"]: loc["id"]
        for loc in api.get(f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations",
                           limit=200)["data"]
    }
    print(f"Version {args.version} ({version['id']}), state {state}; target display type {display_type}\n")

    plan = []
    for locale, files in screens.items():
        loc_id = localizations.get(locale)
        if not loc_id:
            print(f"[{locale}] ! not on the version, skipped\n")
            continue
        sets = api.get(f"/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets",
                       **{"include": "appScreenshots", "limit": 50})
        shots = {s["id"]: s["attributes"] for s in sets.get("included", []) if s["type"] == "appScreenshots"}
        target, old = None, []
        print(f"[{locale}]")
        for s in sets["data"]:
            shot_ids = [r["id"] for r in s["relationships"]["appScreenshots"]["data"]]
            kind = s["attributes"]["screenshotDisplayType"]
            listed = ", ".join((shots.get(i) or {}).get("fileName") or i for i in shot_ids)
            print(f"  now {kind}: {len(shot_ids)} — {listed or 'empty'}")
            if kind == display_type:
                target, old = s["id"], [(i, shots.get(i) or {}) for i in shot_ids]
        print(f"  new {display_type}: {', '.join(f.name for f in files)}\n")
        plan.append((locale, loc_id, target, old, files))

    if not args.apply:
        print(f"Dry run: {display_type} would be replaced in {len(plan)} locale(s). Re-run with --apply to send.")
        return

    # Upload into every locale first, then wait once: Apple processes the files in parallel,
    # and a slow one no longer holds up (or aborts) the remaining locales.
    work = []
    with tempfile.TemporaryDirectory() as tmp:
        staged, overflow = [], []
        for locale, loc_id, set_id, old, files in plan:
            # Failed uploads from an earlier run are deleted before uploading and take no room in the set.
            failed = [shot_id for shot_id, attrs in old
                      if (attrs.get("assetDeliveryState") or {}).get("state") == "FAILED"]
            old = [(shot_id, attrs) for shot_id, attrs in old if shot_id not in failed]
            # A screenshot already in the set with the same bytes (from an interrupted run) is reused.
            reusable = {attrs.get("sourceFileChecksum"): shot_id for shot_id, attrs in old}
            sources = [opaque_copy(f, Path(tmp)) for f in files]
            checksums = [hashlib.md5(p.read_bytes()).hexdigest() for p in sources]
            keep = {reusable[c] for c in checksums if c in reusable}
            stale = [shot_id for shot_id, _ in old if shot_id not in keep]
            # The old screenshots stay until the new ones are processed; that needs room for both in the set.
            if len(old) + len(files) - len(keep) > MAX_PER_SET:
                overflow.append(locale)
            staged.append((locale, loc_id, set_id, files, reusable, sources, checksums, keep, stale, failed))
        if overflow and not args.delete_first:
            sys.exit(f"Old and new screenshots do not fit in one set (max {MAX_PER_SET}) for: "
                     f"{', '.join(overflow)}. Nothing was changed. Re-run with --delete-first to remove "
                     "the old ones before uploading; an upload failure then leaves those sets incomplete.")

        for locale, loc_id, set_id, files, reusable, sources, checksums, keep, stale, failed in staged:
            if set_id is None:
                set_id = api.request("POST", "/v1/appScreenshotSets", body={"data": {
                    "type": "appScreenshotSets",
                    "attributes": {"screenshotDisplayType": display_type},
                    "relationships": {"appStoreVersionLocalization": {
                        "data": {"type": "appStoreVersionLocalizations", "id": loc_id}}},
                }})["data"]["id"]
            for shot_id in failed:
                api.request("DELETE", f"/v1/appScreenshots/{shot_id}")
            if locale in overflow:
                for shot_id in stale:
                    api.request("DELETE", f"/v1/appScreenshots/{shot_id}")
                stale = []
            new_ids = []
            for i, (f, path, checksum) in enumerate(zip(files, sources, checksums), 1):
                new_ids.append(reusable.get(checksum) or upload(api, set_id, path, f"{i}_{f.name}"))
            print(f"[{locale}] {len(new_ids) - len(keep)} uploaded, {len(keep)} reused")
            work.append((locale, set_id, stale, new_ids))

    problems = wait_processed(api, [i for *_, new_ids in work for i in new_ids])
    unfinished = []
    for locale, set_id, stale, new_ids in work:
        bad = {i: problems[i] for i in new_ids if i in problems}
        if bad:
            unfinished.append(locale)
            print(f"[{locale}] ! old screenshots kept, new ones not ready: {bad}")
            continue
        for shot_id in stale:
            api.request("DELETE", f"/v1/appScreenshots/{shot_id}")
        api.request("PATCH", f"/v1/appScreenshotSets/{set_id}/relationships/appScreenshots", body={
            "data": [{"type": "appScreenshots", "id": i} for i in new_ids]})
        print(f"[{locale}] {display_type}: {len(new_ids)} in place, {len(stale)} old removed")
    if unfinished:
        sys.exit(f"Not finished: {', '.join(unfinished)}. Re-run the same command to complete them.")
    print("Done.")


if __name__ == "__main__":
    main()
