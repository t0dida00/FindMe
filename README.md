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
| [supabase/](supabase/) | Postgres schema with **all game rules** (RPCs, RLS, triggers, `pg_cron`), Edge Functions `push` and `purge-proofs`, tests |

A Go HTTP API that sits in front of the same database lives in a separate repo:
[FindMe-Go](https://github.com/t0dida00/FindMe-Go).

## How it fits together

```
iOS app ──(supabase-swift)──► Supabase
                                ├─ Postgres: RPCs + RLS + triggers = the game rules
                                ├─ Auth (Apple, Google, email OTP)
                                ├─ Storage: proofs, avatars, hint-media
                                ├─ Realtime: INSERTs on game_events
                                └─ Edge Functions: push (APNs), purge-proofs (daily)
```

The app never decides a game rule itself. It calls RPCs (`join_game`, `redeem_code`,
`review_submission`, …), reads the tables RLS allows, uploads photos and listens to `game_events`.
The player's GPS never leaves the device.

## Backend setup (Supabase)

1. Create a Supabase project. Enable `pg_cron` and `pg_net` (Dashboard → Database → Extensions).
2. Apply the migrations **in file-name order**:
   ```bash
   npx supabase link --project-ref <ref>
   npx supabase db push
   ```
   Or paste each file from [supabase/migrations/](supabase/migrations/) into the SQL Editor, oldest
   first. Never edit an applied migration; add a new file instead. The first file
   (`20261103000000_treasure_hunt.sql`) is the original schema from the plan and stays verbatim.
3. Auth → Providers: enable **Apple** and **Google**, and add the redirect URL `findme://login-callback`.
4. Edge Functions:
   ```bash
   npx supabase functions deploy push
   npx supabase functions deploy purge-proofs
   npx supabase secrets set PUSH_WEBHOOK_SECRET=... CRON_SECRET=... \
     APNS_KEY="$(cat AuthKey_XXXX.p8)" APNS_KEY_ID=... APNS_TEAM_ID=... \
     APNS_BUNDLE_ID=com.findme.app APNS_PRODUCTION=false
   ```
   - **push**: Database → Webhooks → new `INSERT` webhook on `public.game_events`, POST to
     `https://<ref>.supabase.co/functions/v1/push` with header `x-webhook-secret: <PUSH_WEBHOOK_SECRET>`.
   - **purge-proofs**: schedule it daily:
     ```sql
     select cron.schedule('find-me-purge-proofs', '0 3 * * *', $$
       select net.http_post('https://<ref>.supabase.co/functions/v1/purge-proofs',
         headers => jsonb_build_object('Authorization', 'Bearer <CRON_SECRET>'))
     $$);
     ```
5. Demo data (optional, **not for production**): [supabase/seed.sql](supabase/seed.sql) creates 10
   public games around Ho Chi Minh City (proof codes `DEMO<i>X<k>`).

Then set up the app: [ios/README.md](ios/README.md).

## Tests and checks

```bash
bash supabase/tests/run.sh                    # throwaway Postgres + every migration, plays whole games
python3 -I supabase/tests/check_contract.py   # every RPC/table the app uses exists; every SQL error code has an app message
python3 -I supabase/tests/check_server.py     # live Supabase vs migrations (read-only, anon key): lists missing migrations
bash ios/scripts/check-strings.sh             # build the app + check the string catalog (vi/en)
```

`run.sh` needs Homebrew `postgresql` (`initdb`, `pg_ctl`, `psql`); no Supabase or Docker. The
scenarios cover wrong codes and lockout, code reservation, deny/approve, auto-approve, item prizes,
the one-active-game rule, the player limit, open games, rankings, RLS and account deletion.

## Proof flow

```
type code ─ redeem_code ─┬─ wrong_code / code_entry_locked / code_in_use
                         └─ ok → code reserved (60 s) ─ photo + upload ─ attach_photo → pending
pending ─ host approves ─→ approved: answer pinned, next hint opens (or game ends + grand prize)
        ─ host denies ───→ denied: the code opens again
        ─ 15 min without review → auto-approve (pg_cron every minute; host reminded at 5 and 10 min)
reserved > 60 s → expired: the code opens again
```

## Contributing

Conventions (design tokens, layout pieces, i18n, where logic goes) are in [CLAUDE.md](CLAUDE.md).
