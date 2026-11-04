-- Kiểm tra sau khi chạy mọi migration: database chỉ lưu dữ liệu (20261105000000_storage_only.sql).
-- Luật chơi được kiểm tra trong server Go (bash server/scripts/test-integration.sh).
-- Mỗi dòng in "ok <tên>" hoặc "FAIL <tên>: <chi tiết>".
\pset tuples_only on
\pset format unaligned

select case when n = 0 then 'ok no app functions in public'
            else 'FAIL app functions left: ' || names end
  from (select count(*) n, string_agg(p.proname, ', ') names from pg_proc p
         where p.pronamespace = 'public'::regnamespace
           and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')) x;

select case when n = 0 then 'ok no triggers on app tables'
            else 'FAIL triggers left: ' || names end
  from (select count(*) n, string_agg(tgname, ', ') names from pg_trigger t
         join pg_class c on c.oid = t.tgrelid
        where not t.tgisinternal and c.relnamespace in ('public'::regnamespace, 'auth'::regnamespace)) x;

select case when n = 0 then 'ok no RLS policies' else 'FAIL policies left: ' || names end
  from (select count(*) n, string_agg(tablename || '.' || policyname, ', ') names from pg_policies
         where schemaname = 'public'
            or (schemaname = 'storage' and policyname in ('proofs_upload', 'proofs_read', 'hint_media_write',
                'hint_media_read', 'hint_media_delete', 'avatars_insert', 'avatars_update'))) x;

select case when n = 0 then 'ok anon/authenticated have no table rights' else 'FAIL table grants: ' || names end
  from (select count(*) n, string_agg(distinct grantee || ' ' || privilege_type || ' ' || table_name, ', ') names
          from information_schema.role_table_grants
         where table_schema = 'public' and grantee in ('anon', 'authenticated')) x;

select case when n = 0 then 'ok RLS on every app table' else 'FAIL RLS off: ' || names end
  from (select count(*) n, string_agg(relname, ', ') names from pg_class
         where relnamespace = 'public'::regnamespace and relkind = 'r' and not relrowsecurity) x;

select case when count(*) = 0 then 'ok game_events not in Realtime' else 'FAIL game_events still published' end
  from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'game_events';

-- Ràng buộc toàn vẫn còn (lớp bảo vệ cuối nếu server có lỗi)
select case when count(*) = 7 then 'ok integrity constraints kept'
            else 'FAIL integrity constraints: only ' || string_agg(conname, ', ') end
  from pg_constraint where conname in (
    'games_join_code_key', 'hints_game_id_hint_order_key', 'hint_item_payload', 'games_public_needs_area',
    'games_area_pair', 'rewards_hint_id_kind_key', 'games_proof_retention_fixed');

select case when count(*) = 2 then 'ok one open / one winner per hint (unique indexes)' else 'FAIL submission indexes' end
  from pg_indexes where indexname in ('submissions_one_open_per_hint', 'submissions_one_winner_per_hint');

-- Seed demo nạp được trên schema chỉ-dữ-liệu
select case when count(*) = 10 then 'ok seed: 10 demo games' else 'FAIL seed games: ' || count(*) end
  from games where host_id::text like 'de000000-%';
select case when bool_and(exists (select 1 from game_participants gp where gp.game_id = g.id and gp.role = 'host'))
            then 'ok seed: every demo game has its host row' else 'FAIL seed: host rows missing' end
  from games g where host_id::text like 'de000000-%';
select case when count(*) = 50 then 'ok seed: 50 demo profiles' else 'FAIL seed profiles: ' || count(*) end
  from profiles where id::text like 'de000000-%';
