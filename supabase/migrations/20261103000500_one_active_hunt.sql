-- =====================================================================
--  Find Me! — 1 người, 1 cuộc săn (chạy sau 20261103000400_globe.sql)
--
--  Mỗi người chỉ được ở trong MỘT cuộc săn chưa kết thúc (draft, scheduled, live), dù với
--  vai trò quản trò, co-host hay người chơi. Cuộc săn completed / cancelled không tính.
--
--  Chặn tại một chỗ duy nhất: trigger BEFORE INSERT trên game_participants. Mọi đường vào
--  đều đi qua đây:
--    - tạo game → trigger games_add_host chèn dòng 'host' → bị chặn → cả lệnh tạo game rollback;
--    - join_game() → chèn dòng 'player' → bị chặn;
--    - vào lại chính cuộc săn mình đang ở thì không bị chặn.
--  Khóa advisory theo user để hai lệnh join/tạo chạy đồng thời không cùng lọt qua.
--  Không kiểm tra lại dữ liệu cũ: chỉ áp dụng cho lượt tham gia mới.
-- =====================================================================

create or replace function public.enforce_one_active_hunt()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_other uuid;
begin
  -- Cuộc săn đích đã kết thúc thì không cần kiểm tra
  if not exists (select 1 from games where id = new.game_id
                  and status in ('draft', 'scheduled', 'live')) then
    return new;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('one_active_hunt:' || new.user_id::text, 0));
  select gp.game_id into v_other
    from game_participants gp join games g on g.id = gp.game_id
   where gp.user_id = new.user_id and gp.game_id <> new.game_id
     and g.status in ('draft', 'scheduled', 'live')
   limit 1;
  if v_other is not null then raise exception 'already_in_active_game'; end if;
  return new;
end $$;

create trigger game_participants_one_active_hunt
  before insert on public.game_participants
  for each row execute function public.enforce_one_active_hunt();

-- Cuộc săn chưa kết thúc của mình (0..1 dòng), để app biết vì sao bị chặn.
create or replace function public.get_my_active_game()
returns table (game_id uuid, title text, status public.game_status, role public.participant_role)
language sql stable security definer set search_path = public as $$
  select g.id, g.title, g.status, gp.role
    from game_participants gp join games g on g.id = gp.game_id
   where gp.user_id = auth.uid() and g.status in ('draft', 'scheduled', 'live')
   order by g.created_at desc
   limit 1;
$$;

revoke all on function public.enforce_one_active_hunt(), public.get_my_active_game()
  from public, anon, authenticated;
grant execute on function public.get_my_active_game() to authenticated;
