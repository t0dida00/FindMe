# Find Me!

A live treasure-hunt app. A host publishes a chain of hints. Players find a printed proof sheet at
each location, type the code printed on it, then photograph the sheet in the app. When the host
approves, everyone moves on to the next hint. Each hint can carry a milestone prize (money or an
item); the last one leads to the grand prize.

iOS first (SwiftUI). One app covers both roles: you can host one game and play in another. The
interface is Vietnamese-first with an English translation.

| Folder | What |
| --- | --- |
| [ios/](ios/) | SwiftUI app (iOS 17+, Swift 6) for players and hosts. Setup: [ios/README.md](ios/README.md) |
| [supabase/](supabase/) | Postgres schema (data only: tables, keys, constraints), demo seed, schema tests |
| `server/` | The game server: [FindMe-Go](https://github.com/t0dida00/FindMe-Go), a separate repo checked out here. **All game rules live there** |

## How it fits together

```
iOS app ──(HTTPS + Supabase token)──► Go server (FindMe-Go) ──► Postgres (Supabase): data only
   │                                    ├─ game rules: joining, codes, proofs, review, prizes, timers
   │                                    ├─ realtime: SSE stream per game (LISTEN/NOTIFY)
   │                                    ├─ push: APNs worker on a durable outbox
   │                                    └─ photos: signs Storage upload/download URLs
   ├──► Supabase Auth (Apple, Google, email OTP): sign-in only
   └──► Supabase Storage (proofs, avatars, hint-media): only through URLs the server signed
```

The app never decides a game rule itself and never reads or writes Supabase data directly: it asks
the server (`/v1/...`) and shows the answer. The database only stores data; it has no functions,
triggers, RLS policies or cron. The player's GPS never leaves the device.

## Backend setup

1. Create a Supabase project (Postgres, Auth, Storage).
2. Apply the migrations **in file-name order**, with the server's migrator or the Supabase CLI:
   ```bash
   cd server && MIGRATIONS_DIR=../supabase/migrations go run ./cmd/migrate   # or: npx supabase db push
   ```
   Never edit an applied migration; add a new file instead. The first file
   (`20261103000000_treasure_hunt.sql`) is the original schema from the plan and stays verbatim.
   `20261105000000_storage_only.sql` removes every SQL function, trigger, policy and cron job and
   revokes direct access: apply it only once every app build talks to the Go server.
3. Auth → Providers: enable **Apple** and **Google**, and add the redirect URL `findme://login-callback`.
4. Run the Go server with `server/.env` (see `server/README.md`): `DATABASE_URL`, `SUPABASE_URL`,
   `SUPABASE_SERVICE_ROLE_KEY` (photo URLs, proof cleanup), APNs keys for push. It runs the timers
   (scheduled starts, upload expiry, review reminders, auto-approve, timed blocks) every minute.
   The legacy Edge Functions in `supabase/functions/` are replaced by it: don't deploy them.
5. Demo data (optional, **not for production**): [supabase/seed.sql](supabase/seed.sql) creates 10
   public games around Ho Chi Minh City (proof codes `DEMO<i>X<k>`).

Then set up the app: [ios/README.md](ios/README.md).

## Tests and checks

```bash
bash supabase/tests/run.sh                    # throwaway Postgres + every migration + seed: the DB stores data only
bash server/scripts/test-integration.sh       # the game rules (Go) play whole games on a throwaway Postgres
python3 -I supabase/tests/check_contract.py   # every server call the app makes exists; every rule code has an app message
python3 -I supabase/tests/check_server.py     # live Supabase vs migrations (read-only, anon key): lists missing migrations
bash ios/scripts/check-strings.sh             # build the app + check the string catalog (vi/en)
```

Both scripts need Homebrew `postgresql` (`initdb`, `pg_ctl`, `psql`); no Supabase or Docker. The Go
scenarios cover wrong codes and lockout, code reservation, deny/approve, timers and auto-approve, item
prizes, the one-active-game rule, the player limit (concurrent joins), open games, rankings, who may
see what, and account deletion.

## Proof flow

```
type code ─ POST /v1/hints/{id}/redeem ─┬─ wrong_code / code_entry_locked / code_in_use
                                        └─ ok → code reserved (60 s) ─ photo upload ─ attach → pending
pending ─ host approves ─→ approved: answer pinned, next hint opens (or game ends + grand prize)
        ─ host denies ───→ denied: the code opens again
        ─ 15 min without review → auto-approve (server timers every minute; host reminded at 5 and 10 min)
reserved > 60 s → expired: the code opens again
```

## Contributing

Conventions (design tokens, layout pieces, i18n, where logic goes) are in [CLAUDE.md](CLAUDE.md).
