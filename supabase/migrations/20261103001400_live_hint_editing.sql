-- =====================================================================
--  Find Me! — quản trò sửa hint khi cuộc săn đang diễn ra (chạy sau 20261103001300_hint_codes_visible.sql)
--
--  Trước đây hint chỉ sửa được khi game còn draft/scheduled. Từ nay khi game đang live, staff vẫn
--  sửa được TIÊU ĐỀ, MÔ TẢ và TIỀN THƯỞNG của những hint chưa giải (kể cả hint đang mở).
--  Vẫn khóa khi đã bắt đầu: vị trí đáp án, mã proof (set_hint_code giữ game_is_editable), khối gợi ý
--  (RLS hint_items giữ game_is_editable), thêm/xóa/đổi thứ tự hint. Hint đã giải khóa hoàn toàn.
--
--  1. hint_is_editable(hint_id): game draft/scheduled, hoặc game live và hint chưa giải.
--  2. RLS update trên hints dùng hint_is_editable.
--  3. Trigger: khi game đã bắt đầu không đổi được hint_order ('hint_order_locked') và vị trí
--     đáp án ('hint_location_locked').
--  4. Sửa tiêu đề/mô tả/thưởng khi live → sự kiện 'hint_updated' để app người chơi tải lại (không push).
-- =====================================================================

-- 1 ------------------------------------------------------------------
create or replace function public.hint_is_editable(p_hint_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from hints h join games g on g.id = h.game_id
     where h.id = p_hint_id
       and (g.status in ('draft', 'scheduled') or (g.status = 'live' and h.revealed_at is null)));
$$;
grant execute on function public.hint_is_editable(uuid) to authenticated;

-- 2 ------------------------------------------------------------------
drop policy if exists hints_staff_update on public.hints;
create policy hints_staff_update on public.hints for update to authenticated
  using (public.is_game_staff(game_id) and public.hint_is_editable(id))
  with check (public.is_game_staff(game_id) and public.hint_is_editable(id));

-- 3 ------------------------------------------------------------------
create or replace function public._hint_live_guard()
returns trigger language plpgsql set search_path = public as $$
begin
  if game_is_editable(new.game_id) then return new; end if;
  if new.hint_order is distinct from old.hint_order then raise exception 'hint_order_locked'; end if;
  if (new.answer_lat, new.answer_lng) is distinct from (old.answer_lat, old.answer_lng) then
    raise exception 'hint_location_locked';
  end if;
  return new;
end $$;

drop trigger if exists hint_live_guard on public.hints;
create trigger hint_live_guard before update of hint_order, answer_lat, answer_lng on public.hints
  for each row execute function public._hint_live_guard();

-- 4 ------------------------------------------------------------------
create or replace function public._emit_hint_updated()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (new.title, new.description, new.prize) is not distinct from (old.title, old.description, old.prize) then
    return null;
  end if;
  if exists (select 1 from games where id = new.game_id and status = 'live') then
    perform _emit(new.game_id, 'hint_updated', jsonb_build_object('hint_order', new.hint_order));
  end if;
  return null;
end $$;

drop trigger if exists hints_emit_updated on public.hints;
create trigger hints_emit_updated after update of title, description, prize on public.hints
  for each row execute function public._emit_hint_updated();

notify pgrst, 'reload schema';
