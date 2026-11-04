#!/usr/bin/env bash
# Chạy 2 migration + kịch bản một game hoàn chỉnh trên Postgres cục bộ (không cần Docker/Supabase).
# Cần: initdb/pg_ctl/psql (Homebrew postgresql@15+). Dùng: bash supabase/tests/run.sh
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
PORT="${PORT:-54329}"
export PGHOST=127.0.0.1 PGPORT="$PORT" PGUSER=postgres

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
  -f "$DIR/../migrations/20261104000100_game_events_notify.sql" 2>&1 | grep -v -e wal_level -e HINT || true
psql -d t -f "$DIR/game_flow.sql" 2>&1 | grep -v -e '^SET' -e '^INSERT' -e '^UPDATE' -e '^CREATE' -e '^GRANT' -e '^RESET' -e '^Output' -e '^$'
# Kịch bản tạm (agent tester): EXTRA_SQL=/đường/dẫn/file.sql bash supabase/tests/run.sh
# Chạy sau game_flow.sql trên cùng DB (người dùng 0…a/b/c đã có; 0…d đã bị xóa).
if [ -n "${EXTRA_SQL:-}" ]; then
  echo "=== EXTRA_SQL: $EXTRA_SQL"
  psql -d t -f "$EXTRA_SQL" 2>&1 | grep -v -e '^SET' -e '^RESET' -e '^$'
fi
# Các lỗi "hint_title_required", "hint_location_locked", "hint_order_locked", "game_not_editable", "row-level security" (hint_items của hint đã giải), "permission denied for table code_attempts/host_ratings/games", "not_game_player", "invalid_stars",
# "not_game_host", "game_full", "max_players_below_count", "game_has_no_hints", "last_hint", "hint_prize_over_grand", "grand_prize_below_hint", "game_not_open" và "game_closed" là lỗi MONG ĐỢI (kiểm tra RLS/quyền/giới hạn).

# Seed demo (10 cuộc săn quanh TP.HCM) + Globe
psql -d t -v ON_ERROR_STOP=1 -q -f "$DIR/../seed.sql"
psql -d t -At -f "$DIR/globe.sql"
