-- =====================================================================
--  Find Me! — join_open_game báo rõ game đã kết thúc / bị hủy (chạy sau 20261103002100_open_join.sql)
--
--  Trước đây game mở đã kết thúc hoặc bị hủy trả 'game_not_found', mà câu báo của mã đó nói về
--  "mã tham gia" (người chơi không hề nhập mã). Nay: completed/cancelled → 'game_closed'.
--  Bản nháp và id không tồn tại vẫn là 'game_not_found'.
-- =====================================================================

create or replace function public.join_open_game(p_game_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare g games%rowtype; v_new int;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  select * into g from games where id = p_game_id and status <> 'draft';
  if g.id is null then raise exception 'game_not_found'; end if;
  if g.status in ('completed', 'cancelled') then raise exception 'game_closed'; end if;
  if not (g.is_public and g.join_open) then raise exception 'game_not_open'; end if;
  insert into game_participants (game_id, user_id, role)
  values (g.id, auth.uid(), 'player') on conflict do nothing;
  get diagnostics v_new = row_count;
  if v_new > 0 then
    perform _emit(g.id, 'player_joined', jsonb_build_object('user_id', auth.uid()));
  end if;
  return g.id;
end $$;

notify pgrst, 'reload schema';
