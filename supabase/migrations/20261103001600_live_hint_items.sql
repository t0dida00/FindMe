-- =====================================================================
--  Find Me! — quản trò sửa khối gợi ý (ảnh, văn bản, vùng bản đồ) khi cuộc săn đang diễn ra
--  (chạy sau 20261103001500_hint_prize_cap.sql)
--
--  Luật mới: khi game đã bắt đầu, staff sửa được MỌI THỨ của hint chưa giải (tiêu đề, mô tả,
--  tiền thưởng, khối gợi ý), trừ MÃ PROOF (set_hint_code giữ game_is_editable) và VỊ TRÍ ĐÁP ÁN
--  (trigger hint_live_guard trong 20261103001400). Thêm/xóa/đổi thứ tự hint vẫn chỉ trước khi bắt đầu.
--  Hint đã giải khóa hoàn toàn.
--
--  1. RLS ghi hint_items dùng hint_is_editable(hint_id) thay cho game_is_editable(game_id).
--  2. Thêm/sửa/xóa khối gợi ý (cột nội dung) khi live → sự kiện 'hint_updated' để app người chơi tải lại.
-- =====================================================================

-- 1 ------------------------------------------------------------------
drop policy if exists hint_items_staff_write on public.hint_items;
create policy hint_items_staff_write on public.hint_items for all to authenticated
  using (exists (select 1 from public.hints h where h.id = hint_id
                 and public.is_game_staff(h.game_id) and public.hint_is_editable(h.id)))
  with check (exists (select 1 from public.hints h where h.id = hint_id
                 and public.is_game_staff(h.game_id) and public.hint_is_editable(h.id)));

-- 2 ------------------------------------------------------------------
create or replace function public._emit_hint_item_updated()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_hint_id uuid := coalesce(new.hint_id, old.hint_id); v_game uuid; v_order int;
begin
  select h.game_id, h.hint_order into v_game, v_order
    from hints h join games g on g.id = h.game_id
   where h.id = v_hint_id and g.status = 'live';
  if v_game is not null then
    perform _emit(v_game, 'hint_updated', jsonb_build_object('hint_order', v_order));
  end if;
  return null;
end $$;

drop trigger if exists hint_items_emit_updated on public.hint_items;
-- Chỉ các cột nội dung: process_timers tự ghi reveal_announced_at khi mở khối theo giờ (đã có
-- sự kiện hint_item_revealed riêng), nên không được bắn thêm 'hint_updated' ở đó.
create trigger hint_items_emit_updated
  after insert or delete
     or update of item_order, type, text_content, image_path, map_radius_m, reveal_after_minutes
  on public.hint_items
  for each row execute function public._emit_hint_item_updated();

notify pgrst, 'reload schema';
