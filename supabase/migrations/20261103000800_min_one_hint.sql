-- =====================================================================
--  Find Me! — mỗi cuộc săn có ít nhất 1 hint (chạy sau 20261103000700_hint_description.sql)
--
--  App tạo game rồi mới tạo hint (wizard bắt buộc ≥ 1 hint và tự xóa game nếu tạo hint lỗi).
--  Phía server giữ quy tắc ở những chỗ cuộc săn "đi tiếp":
--  1. schedule_game(): báo 'game_has_no_hints' nếu chưa có hint (start_game đã kiểm tra sẵn).
--  2. Không cho xóa hint cuối cùng của một cuộc săn ('last_hint'). Xóa cả game (cascade) vẫn được,
--     vì lúc đó game đã biến mất. Trigger chạy AFTER mỗi dòng nên thấy trạng thái cuối câu lệnh:
--     xóa nhiều hint một lúc mà hết sạch cũng bị chặn.
-- =====================================================================

-- 1 ------------------------------------------------------------------
create or replace function public.schedule_game(p_game_id uuid, p_starts_at timestamptz)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_game_staff(p_game_id) then raise exception 'not_game_staff'; end if;
  if not exists (select 1 from hints where game_id = p_game_id) then
    raise exception 'game_has_no_hints';
  end if;
  update games set status = 'scheduled', starts_at = p_starts_at
   where id = p_game_id and status in ('draft', 'scheduled');
  if not found then raise exception 'game_not_editable'; end if;
end $$;

-- 2 ------------------------------------------------------------------
create or replace function public.keep_one_hint()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from games where id = old.game_id)
     and not exists (select 1 from hints where game_id = old.game_id) then
    raise exception 'last_hint';
  end if;
  return null;
end $$;

create trigger hints_keep_one after delete on public.hints
  for each row execute function public.keep_one_hint();

revoke all on function public.keep_one_hint() from public, anon, authenticated;

notify pgrst, 'reload schema';
