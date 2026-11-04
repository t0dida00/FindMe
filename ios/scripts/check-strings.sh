#!/usr/bin/env bash
# Builds the app, then compares the strings the Swift compiler extracted with
# FindMe/Resources/Localizable.xcstrings. Fails if a string in code is missing from the
# catalog, if a catalog entry has no English or Vietnamese value, or if a catalog entry is no longer
# used in code (stale). Keys starting with "push." are APNs loc-keys used by
# supabase/functions/push and are never extracted from Swift, so they are skipped in the stale check.
#
# Usage: bash ios/scripts/check-strings.sh
set -euo pipefail
cd "$(dirname "$0")/.."
DD="${DERIVED_DATA:-$(mktemp -d)}"

xcodebuild -project FindMe.xcodeproj -scheme FindMe -destination 'generic/platform=iOS Simulator' \
  -configuration Debug -derivedDataPath "$DD" build CODE_SIGNING_ALLOWED=NO -quiet >/dev/null

python3 - "$DD" <<'EOF'
import glob, json, sys
dd = sys.argv[1]
extracted = set()
for f in glob.glob(dd + "/**/*.stringsdata", recursive=True):
    for entry in json.load(open(f)).get("tables", {}).get("Localizable", []):
        extracted.add(entry["key"])
catalog = json.load(open("FindMe/Resources/Localizable.xcstrings"))["strings"]

missing = sorted(extracted - set(catalog))
stale = sorted(k for k in set(catalog) - extracted if not k.startswith("push."))
untranslated = sorted(k for k, v in catalog.items()
                      if "en" not in v.get("localizations", {}) and not v.get("shouldTranslate", True) is False)
# English is the source/fallback language, so the Vietnamese text (= the key) must be stored explicitly.
no_vi = sorted(k for k, v in catalog.items()
               if "vi" not in v.get("localizations", {}) and not v.get("shouldTranslate", True) is False)

for title, items in (("Missing from catalog", missing), ("Stale (not used in code)", stale),
                     ("No English translation", untranslated), ("No Vietnamese value", no_vi)):
    if items:
        print(f"{title} ({len(items)}):")
        for k in items:
            print(f"  {k!r}")
print(f"{len(extracted)} strings in code, {len(catalog)} in catalog.")
sys.exit(1 if missing or stale or untranslated or no_vi else 0)
EOF
