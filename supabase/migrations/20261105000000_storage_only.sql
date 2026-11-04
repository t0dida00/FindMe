-- =====================================================================
--  Find Me! — database chỉ lưu dữ liệu (chạy sau 20261104000200_push_outbox.sql)
--
--  Toàn bộ luật chơi đã chuyển sang server Go (FindMe-Go, internal/application/hunt): tham gia,
--  nhập mã, ảnh proof, duyệt, bộ hẹn giờ, soạn game, quyền xem/sửa, quyền ảnh Storage. App chỉ nói
--  chuyện với server Go (và Supabase Auth để đăng nhập); server kết nối bằng role chủ bảng.
--
--  Migration này gỡ mọi thứ còn lại trong database mà không phải dữ liệu:
--  1. Mọi hàm của app trong schema public (RPC, hàm trigger, hàm tiện ích) và trigger của chúng,
--     kể cả trigger tạo profile trên auth.users (server tạo profile lần đầu thấy người dùng).
--  2. Mọi policy RLS trên bảng public và policy Storage của app. RLS vẫn BẬT và không có policy:
--     anon/authenticated (PostgREST, Realtime) không đọc/ghi được gì.
--  3. Thu hồi mọi quyền của anon/authenticated trên bảng, sequence và hàm trong public.
--  4. Bỏ cron 'treasure-hunt-timers' (server chạy bộ hẹn giờ) và bỏ game_events khỏi Supabase
--     Realtime (server đẩy sự kiện qua SSE).
--
--  Giữ nguyên: bảng, cột, khóa chính/ngoại, unique, check, default, index, extension pgcrypto (mã cũ
--  đã băm bằng bcrypt vẫn kiểm tra được trong Go).
--
--  CHÚ Ý TRIỂN KHAI: chỉ chạy trên server thật SAU KHI server Go đã chạy ổn định ở một địa chỉ cố
--  định và mọi bản app đang dùng đều gọi server Go. Bản app cũ (gọi Supabase trực tiếp) sẽ ngừng
--  hoạt động ngay khi migration này chạy.
-- =====================================================================

-- 1 ------------------------------------------------------------------
drop trigger if exists on_auth_user_created on auth.users;

do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as fn
      from pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and p.prokind = 'f'
       and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')  -- hàm của extension
       and p.proname = any (array[
         '_activate_hint', '_approve_submission', '_emit', '_emit_hint_item_updated', '_emit_hint_updated',
         '_enqueue_push', '_grand_prize_cap', '_hint_live_guard', '_hint_prize_cap', '_join_open_normalize',
         '_notify_game_event', '_release_code', '_reward_fill_item', '_start_game', 'add_host_participant',
         'attach_photo', 'can_view_hint_image', 'can_view_proof', 'cancel_game', 'check_max_players_change',
         'claim_proofs_to_purge', 'create_hint', 'delete_my_account', 'enforce_max_players',
         'enforce_one_active_hunt', 'fill_map_center', 'game_is_editable', 'generate_hint_code',
         'get_current_code_status', 'get_current_hint', 'get_game_summary', 'get_globe_games', 'get_hint_items',
         'get_host_rankings', 'get_leaderboard', 'get_my_active_game', 'get_my_code_state', 'get_my_history',
         'get_my_host_rating', 'get_my_stats', 'get_next_reveal_at', 'get_player_rankings', 'get_revealed_answers',
         'handle_new_user', 'hint_is_editable', 'is_game_staff', 'is_participant', 'join_game', 'join_open_game',
         'keep_one_hint', 'mark_proofs_purged', 'normalize_code', 'process_timers', 'random_map_center',
         'rate_host', 'recenter_maps_on_move', 'redeem_code', 'register_device_token', 'review_submission',
         'round_game_area', 'schedule_game', 'set_hint_code', 'set_participant_role', 'start_game',
         'touch_updated_at', 'try_uuid'])
  loop
    execute format('drop function %s cascade', r.fn);  -- cascade: trigger và policy dùng hàm này
  end loop;
end $$;

-- 2 ------------------------------------------------------------------
do $$
declare r record;
begin
  for r in select schemaname, tablename, policyname from pg_policies where schemaname = 'public' loop
    execute format('drop policy %I on %I.%I', r.policyname, r.schemaname, r.tablename);
  end loop;
  for r in
    select policyname from pg_policies
     where schemaname = 'storage' and tablename = 'objects'
       and policyname in ('proofs_upload', 'proofs_read', 'hint_media_write', 'hint_media_read',
                          'hint_media_delete', 'avatars_insert', 'avatars_update')
  loop
    execute format('drop policy %I on storage.objects', r.policyname);
  end loop;
end $$;

do $$
declare t text;
begin
  foreach t in array array['profiles', 'games', 'game_participants', 'hints', 'hint_items', 'hint_codes',
                           'submissions', 'code_attempts', 'rewards', 'game_events', 'device_tokens',
                           'host_ratings', 'push_outbox'] loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

-- 3 ------------------------------------------------------------------
revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke all on functions from public, anon, authenticated;

-- 4 ------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'treasure-hunt-timers';
  end if;
  if exists (select 1 from pg_publication_tables
              where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'game_events') then
    alter publication supabase_realtime drop table public.game_events;
  end if;
end $$;
