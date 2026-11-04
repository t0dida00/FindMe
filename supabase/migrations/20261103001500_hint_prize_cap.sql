-- =====================================================================
--  Find Me! — thưởng mốc của hint không được lớn hơn giải thưởng tổng
--  (chạy sau 20261103001400_live_hint_editing.sql)
--
--  1. Thêm/sửa hint với prize > games.grand_prize → 'hint_prize_over_grand'.
--  2. Hạ games.grand_prize xuống dưới thưởng của một hint đã có → 'grand_prize_below_hint'.
--  Chỉ kiểm tra khi giá trị thay đổi, nên dữ liệu cũ (nếu có) không bị chặn khi sửa cột khác.
-- =====================================================================

-- 1 ------------------------------------------------------------------
create or replace function public._hint_prize_cap()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and new.prize is not distinct from old.prize then return new; end if;
  if new.prize > (select grand_prize from games where id = new.game_id) then
    raise exception 'hint_prize_over_grand';
  end if;
  return new;
end $$;

drop trigger if exists hint_prize_cap on public.hints;
create trigger hint_prize_cap before insert or update of prize on public.hints
  for each row execute function public._hint_prize_cap();

-- 2 ------------------------------------------------------------------
create or replace function public._grand_prize_cap()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.grand_prize is not distinct from old.grand_prize then return new; end if;
  if exists (select 1 from hints where game_id = new.id and prize > new.grand_prize) then
    raise exception 'grand_prize_below_hint';
  end if;
  return new;
end $$;

drop trigger if exists grand_prize_cap on public.games;
create trigger grand_prize_cap before update of grand_prize on public.games
  for each row execute function public._grand_prize_cap();

notify pgrst, 'reload schema';
