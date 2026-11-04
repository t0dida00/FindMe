#!/usr/bin/env bash
# Chạy mọi migration trên Postgres cục bộ (không cần Docker/Supabase), nạp seed demo, rồi kiểm tra
# database chỉ còn lưu dữ liệu (schema_check.sql). Luật chơi được test trong server Go:
# bash server/scripts/test-integration.sh
# Cần: initdb/pg_ctl/psql (Homebrew postgresql@15+). Dùng: bash supabase/tests/run.sh
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
PORT="${PORT:-54329}"
export PGHOST=127.0.0.1 PGPORT="$PORT" PGUSER=postgres PGOPTIONS="-c client_min_messages=warning"

initdb -D "$TMP/data" -U postgres -A trust >/dev/null
pg_ctl -D "$TMP/data" -o "-p $PORT -k '' -h 127.0.0.1" -l "$TMP/pg.log" start >/dev/null
trap 'pg_ctl -D "$TMP/data" stop -m fast >/dev/null; rm -rf "$TMP"' EXIT
sleep 1
createdb t
psql -d t -v ON_ERROR_STOP=1 -q \
  -f "$DIR/supabase_stubs.sql" \
  -f "$DIR/../migrations/20261103000000_treasure_hunt.sql" \
  -f "$DIR/../migrations/20261103000100_mvp_additions.sql" \
  -f "$DIR/../migrations/20261103000200_current_hint.sql" \
  -f "$DIR/../migrations/20261103000300_rankings.sql" \
  -f "$DIR/../migrations/20261103000400_globe.sql" \
  -f "$DIR/../migrations/20261103000500_one_active_hunt.sql" \
  -f "$DIR/../migrations/20261103000600_player_limit.sql" \
  -f "$DIR/../migrations/20261103000700_hint_description.sql" \
  -f "$DIR/../migrations/20261103000800_min_one_hint.sql" \
  -f "$DIR/../migrations/20261103000900_my_stats.sql" \
  -f "$DIR/../migrations/20261103001000_leaderboard_order.sql" \
  -f "$DIR/../migrations/20261103001100_globe_recent_finished.sql" \
  -f "$DIR/../migrations/20261103001200_hint_title_required.sql" \
  -f "$DIR/../migrations/20261103001300_hint_codes_visible.sql" \
  -f "$DIR/../migrations/20261103001400_live_hint_editing.sql" \
  -f "$DIR/../migrations/20261103001500_hint_prize_cap.sql" \
  -f "$DIR/../migrations/20261103001600_live_hint_items.sql" \
  -f "$DIR/../migrations/20261103001700_game_summary.sql" \
  -f "$DIR/../migrations/20261103001800_item_prizes.sql" \
  -f "$DIR/../migrations/20261103001900_host_avatar.sql" \
  -f "$DIR/../migrations/20261103002000_stats_started_games.sql" \
  -f "$DIR/../migrations/20261103002100_open_join.sql" \
  -f "$DIR/../migrations/20261103002200_open_join_closed.sql" \
  -f "$DIR/../migrations/20261104000100_game_events_notify.sql" \
  -f "$DIR/../migrations/20261104000200_push_outbox.sql" \
  -f "$DIR/../migrations/20261105000000_storage_only.sql" 2>&1 | grep -v -e wal_level -e HINT || true
# Seed demo, rồi kiểm tra schema
psql -d t -v ON_ERROR_STOP=1 -q -f "$DIR/../seed.sql"
OUT="$(psql -d t -v ON_ERROR_STOP=1 -q -f "$DIR/schema_check.sql")"
echo "$OUT"
# Kịch bản tạm (agent tester): EXTRA_SQL=/đường/dẫn/file.sql bash supabase/tests/run.sh
if [ -n "${EXTRA_SQL:-}" ]; then
  echo "=== EXTRA_SQL: $EXTRA_SQL"
  psql -d t -f "$EXTRA_SQL" 2>&1 | grep -v -e '^SET' -e '^RESET' -e '^$'
fi
if echo "$OUT" | grep -q '^FAIL'; then exit 1; fi
