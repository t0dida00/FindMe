-- =====================================================================
--  Find Me! — giới hạn người chơi + giữ ảnh proof cố định (chạy sau 20261103000500_one_active_hunt.sql)
--
--  1. games.max_players: quản trò đặt 1–50 người chơi (mặc định 50). Chỉ đếm vai trò 'player';
--     quản trò và co-host không tính. Chặn bằng trigger trên game_participants (thêm mới, hoặc
--     đổi co-host → player) với lỗi 'game_full'. Vào lại cuộc săn mình đã ở thì không bị chặn.
--     Không cho hạ giới hạn xuống dưới số người chơi hiện có ('max_players_below_count').
--  2. Ảnh proof luôn giữ 7 ngày sau khi cuộc săn kết thúc: thu hồi quyền ghi cột
--     proof_retention_days và khóa giá trị = 7. purge-proofs vẫn đọc cột này như cũ.
-- =====================================================================

-- 1 ------------------------------------------------------------------
alter table public.games
  add column max_players int not null default 50 check (max_players between 1 and 50);

grant insert (max_players) on public.games to authenticated;
grant update (max_players) on public.games to authenticated;

create or replace function public.enforce_max_players()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_max int; v_count int;
begin
  if new.role <> 'player' then return new; end if;
  if tg_op = 'UPDATE' and old.role = 'player' then return new; end if;
  -- join_game dùng ON CONFLICT DO NOTHING: trigger BEFORE chạy trước khi xét trùng, nên
  -- người đã ở trong cuộc săn vào lại thì bỏ qua.
  if tg_op = 'INSERT' and exists (select 1 from game_participants
                                   where game_id = new.game_id and user_id = new.user_id) then
    return new;
  end if;
  -- Khóa theo game để hai người vào cùng lúc không cùng lọt qua chỗ trống cuối.
  perform pg_advisory_xact_lock(hashtextextended('max_players:' || new.game_id::text, 0));
  select max_players into v_max from games where id = new.game_id;
  select count(*) into v_count from game_participants
   where game_id = new.game_id and role = 'player' and user_id <> new.user_id;
  if v_count >= v_max then raise exception 'game_full'; end if;
  return new;
end $$;

create trigger game_participants_max_players
  before insert or update of role on public.game_participants
  for each row execute function public.enforce_max_players();

create or replace function public.check_max_players_change()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform pg_advisory_xact_lock(hashtextextended('max_players:' || new.id::text, 0));
  if new.max_players < (select count(*) from game_participants
                         where game_id = new.id and role = 'player') then
    raise exception 'max_players_below_count';
  end if;
  return new;
end $$;

create trigger games_check_max_players before update of max_players on public.games
  for each row when (new.max_players < old.max_players)
  execute function public.check_max_players_change();

revoke all on function public.enforce_max_players(), public.check_max_players_change()
  from public, anon, authenticated;

-- 2 ------------------------------------------------------------------
update public.games set proof_retention_days = 7 where proof_retention_days <> 7;
alter table public.games add constraint games_proof_retention_fixed check (proof_retention_days = 7);
revoke insert (proof_retention_days) on public.games from authenticated;
revoke update (proof_retention_days) on public.games from authenticated;
