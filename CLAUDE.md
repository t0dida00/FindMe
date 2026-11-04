# CLAUDE.md

Find Me! is a live treasure-hunt app. A host publishes a chain of hints; players find a printed proof
sheet at each location, type the code printed on it, then photograph the sheet in the app. When the
host approves, everyone moves on to the next hint. Full plan: [docs/ke-hoach.txt](docs/ke-hoach.txt) (private: gitignored, local copies only).
Setup steps live in [README.md](README.md) (backend) and [ios/README.md](ios/README.md) (app); don't
duplicate them here.

- Reply to the user in English (the app UI stays Vietnamese-first, see i18n).
- iOS first. No web dashboard in the MVP; Android comes later.

## Layout

| Path | What |
| --- | --- |
| `supabase/migrations/` | Postgres schema. **All game rules live here** as RPCs, RLS, triggers and `pg_cron` jobs |
| `supabase/functions/push` | Edge Function: Database Webhook on `game_events` INSERT → APNs |
| `supabase/functions/purge-proofs` | Edge Function: daily cleanup of old proof photos |
| `supabase/tests/` | Local Postgres test that plays a whole game (no Supabase or Docker needed), plus `check_contract.py` (app ↔ SQL) and `check_server.py` (live server vs migrations) |
| `.claude/agents/tester.md` | The `tester` subagent: runs every check above and tries the cases of the latest change |
| `server/` | Go HTTP API (DDD: domain → application → infrastructure/interfaces) in front of the same Postgres. **Its own git repo** ([FindMe-Go](https://github.com/t0dida00/FindMe-Go), module `github.com/t0dida00/FindMe-Go`), ignored by this repo; commit and push it separately. See server/README.md |
| `ios/` | SwiftUI app (iOS 17+, Swift 6, strict concurrency) for both players and hosts |
| `ios/project.yml` | XcodeGen spec. The `.xcodeproj` is generated, so edit `project.yml` instead |

## Commands

```bash
bash supabase/tests/run.sh                 # schema test; needs Homebrew postgresql (initdb/pg_ctl/psql)
cd ios && xcodegen generate                # after adding/removing files or editing project.yml
xcodebuild -project ios/FindMe.xcodeproj -scheme FindMe \
  -destination 'generic/platform=iOS Simulator' -configuration Debug build CODE_SIGNING_ALLOWED=NO
bash ios/scripts/check-strings.sh          # build + check Localizable.xcstrings coverage (see i18n)
bash ios/scripts/install-device.sh         # build, install and launch on the paired iPhone (DEVICE=<UDID> to pick one)
python3 -I supabase/tests/check_contract.py # app RPCs/tables/error codes vs migrations (offline)
python3 -I supabase/tests/check_server.py   # live Supabase vs migrations, read-only with the anon key: lists missing migrations
EXTRA_SQL=/tmp/x.sql bash supabase/tests/run.sh   # also run an ad-hoc SQL scenario after game_flow.sql
cd server && go vet ./... && go test -race ./...  # Go API unit tests
bash server/scripts/test-integration.sh    # Go API against a throwaway Postgres with every migration
```

In `supabase/tests/run.sh` output, `permission denied for table code_attempts` and `not_game_host` at
the end are expected.

## Rules of thumb

- **After every update (SQL or iOS), run the `tester` agent** (Agent tool, `subagent_type: "tester"`) with a
  short description of what changed, and fix what it reports before telling the user the work is done.
  Report its result (PASS/FAIL per check, missing server migrations) in the reply.

- **After every change to the iOS app, reinstall it on the real iPhone** with
  `bash ios/scripts/install-device.sh` once the build passes, so the user can try it right away. If no
  iPhone is paired (or signing fails), say so in the reply instead of skipping silently. Backend-only
  changes (SQL, Edge Functions) don't need a reinstall.
- **Go server (`server/`)**: dependencies point inward (domain has no framework imports; use cases
  depend on domain ports; postgres/http are adapters). It calls the SQL functions through
  `postgres.DB.AsUser`, so it never duplicates game rules. A new SQL error code needs no Go change
  (rule codes pass through), but add it to `statusFor` in `internal/interfaces/httpapi/errors.go` if it
  is not a 409. Secrets go in `server/.env` (gitignored).
- **Game logic goes in SQL, not Swift.** The app only calls RPCs, reads tables that RLS allows,
  uploads to Storage and listens to Realtime on `game_events`. Add a new migration file; never edit
  `20261103000000_treasure_hunt.sql` (it is the verbatim schema from the plan).
- New migrations must also be listed in `supabase/tests/run.sh`, and new behaviour should get a
  scenario in `supabase/tests/game_flow.sql`.
- Errors raised in SQL as `raise exception '<code>'` need a matching message in
  `ios/FindMe/Core/AppError.swift` (both `knownCodes` and `message(code:)`).
- Every RPC/table call from iOS goes through `Core/GameAPI.swift` (player) or `Core/HostAPI.swift` (staff).
- The player's GPS never leaves the device.
- `ios/Config/Secrets.xcconfig` is gitignored; never commit keys, `.p8` files or the service_role key.
- UI colors, fonts and spacing come from the tokens in `ios/FindMe/Shared/Theme.swift` (its header documents
  each role). Brown `fmAccent` is "ink" (brand, icons, secondary buttons); orange `fmTreasure` is only for
  the primary action and hot things (live status, prize money), ~10% of a screen. One font family
  everywhere (SF Pro): no `design: .serif/.monospaced/.rounded`; codes and numbers use `.monospacedDigit()`.
  The only exception is the logo wordmark in `Brand.swift`. Spacing uses the `FM`
  scale (4/8/12/16/24/32/48, screen margin 20); primary buttons are `FM.buttonHeight` (56) tall.
- Screen layout comes from `ios/FindMe/Shared/Layout.swift` (its header lists each piece): grid-paper
  background (applied by `fmScreen()`), the floating tab bar in `MainTabView` (the system tab bar is not
  used), `FMGroup`/`FMRow` grouped rows with an `FMIconTile`, `FMSectionLabel`, 2-column `FMTile` cards
  in `FMTileGrid` (equal widths, equal heights per row) and `.fmPill` header buttons. Top-level tabs hide the navigation bar and draw their
  own header; a pushed screen that hides it uses `FMPushedHeader` (back square + titled box). Every screen shown inside a tab (including pushed ones) needs `.fmTabBarInset()`
  inside its NavigationStack, or the floating bar covers the bottom of the content. Scrolling screens use
  `FMScrollScreen` (the Home tab's padding: 20 side margin, `FM.m` between blocks, `FM.xl` at the bottom);
  don't add `.padding()` around the content. Build new screens from these instead of plain `List` rows.
- Keyboard dismissal is global (`ios/FindMe/Shared/Keyboard.swift`): every text field gets a "Xong" bar
  above the keyboard, tapping outside a field and scrolling hide the keyboard. Don't add per-screen
  `.toolbar(placement: .keyboard)` "Done" buttons (they would show twice).
- Copy-to-clipboard buttons use `FMCopyButton` (`ios/FindMe/Shared/Toast.swift`): icon turns into a tick,
  light haptic, and a toast (`FMToast.show(...)`, drawn in its own window so it shows above sheets).
  Use `FMToast` for other short confirmations too, not a per-screen overlay.
- Logo and full-screen loading come from `ios/FindMe/Shared/Brand.swift`: `FMLogoMark`/`FMWordmark`,
  `FMLoadingView` for a whole screen, `FMLoadingOverlay` on top of a screen. Keep `ProgressView` for inline
  spinners inside buttons and rows.

## i18n

Languages: English (`en`, development/fallback language: any phone not set to Vietnamese gets English)
and Vietnamese (`vi`). The user picks the language in iOS Settings → Find Me! → Language
(Profile → "Ngôn ngữ" opens it).

- **App UI**: `ios/FindMe/Resources/Localizable.xcstrings` (`sourceLanguage: en`). The key is still the
  Vietnamese text itself (historical), stored explicitly as the `vi` value too.
  - Write Vietnamese literals in code: `Text("...")`, `Button("...")`, `LocalizedStringKey`
    parameters, or `String(localized: "...")` when you need a `String` (errors, banners).
  - Don't pass a UI literal through a plain `String` variable/parameter into `Text(...)`; it won't be
    translated. Take `LocalizedStringKey` instead. User content (game titles, names, hint text) is
    the only thing that should be a plain `String`.
  - Every entry needs an `en` translation and a `vi` value (normally equal to the key). Strings with a count (`%lld người chơi`) need English
    plural variations (`one`/`other`); with more than one argument, use a substitution
    (see `"%lld mốc · %@"`). Every other specifier in a value that has `%#@…@` must be
    positional (`%#@milestones@ · %2$@`, not `· %@`): a plain `%@` reads argument 1 (the number)
    as an object and **crashes the app** when the text is shown.
  - Entries are `extractionState: manual`, so Xcode won't delete unused ones by itself. Run
    `bash ios/scripts/check-strings.sh` after changing UI text: it fails on strings missing from the
    catalog, entries without English or Vietnamese, and stale entries.
- **Info.plist strings** (permission prompts, display name): `ios/FindMe/Resources/InfoPlist.xcstrings`,
  with both `vi` and `en` values. Keep the `en` value in sync with `project.yml`.
- **Push notifications** are localized on the device: `supabase/functions/push` sends APNs
  `loc-key` / `title-loc-key` / `loc-args`, and iOS looks the key up in `Localizable.xcstrings`.
  Those keys are `push.*` (with explicit `vi` and `en` values). To add or change a push, update the
  function and the `push.*` entry together; an app build without the key shows the raw key. `loc-args`
  are strings, so use `%@` (positional `%1$@`, `%2$@` when there are several).
- **Server error codes** are stable English identifiers (`wrong_code`); only the app turns them into text.
- A prize (game grand prize, hint milestone, reward) is money **or** an item (gift name):
  `grand_prize_item` / `prize_item` / `rewards.item`, null = money. Show prizes with `Fmt.prize(...)`
  and edit them with `PrizeFields` (`Shared/PrizeInput.swift`); never show `Fmt.money` of a prize directly.
- Number, money, date and duration formatting goes through `Core/Formatters.swift` (`Fmt`), which
  follows the user's locale. Default currency is VND (no decimals).

## Keeping this file current

Update this file in the same change when you add a top-level folder, a command, a language, a new
convention, or change one of the rules above. Remove lines that stop being true.
