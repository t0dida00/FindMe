-- =====================================================================
--  Find Me! — tóm tắt một game cho card "Game của tôi" ở tab Cuộc săn
--  (chạy sau 20261103001600_live_hint_items.sql)
--
--  get_game_summary(p_game_id): tên quản trò, số người chơi, tổng số hint và số hint đã giải.
--  Chỉ thành viên của game gọi được (game riêng tư không có trong get_globe_games, và người chơi
--  không đọc được bảng hints). Không lộ nội dung/vị trí hint, chỉ đếm.
-- =====================================================================

create or replace function public.get_game_summary(p_game_id uuid)
returns table (host_name text, player_count int, hint_count int, solved_count int)
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_participant(p_game_id) then raise exception 'not_game_player'; end if;
  return query
    select p.display_name,
           (select count(*)::int from game_participants x where x.game_id = g.id and x.role = 'player'),
           (select count(*)::int from hints h where h.game_id = g.id),
           (select count(*)::int from hints h where h.game_id = g.id and h.revealed_at is not null)
      from games g join profiles p on p.id = g.host_id
     where g.id = p_game_id;
end $$;

revoke all on function public.get_game_summary(uuid) from public, anon;
grant execute on function public.get_game_summary(uuid) to authenticated;

notify pgrst, 'reload schema';
