-- Hint hiện tại của game (không lộ vị trí hay mã). Cần khi mọi khối của hint đang hẹn giờ:
-- get_hint_items() khi đó trả rỗng nên app không biết hint_id để gọi redeem_code().
create or replace function public.get_current_hint(p_game_id uuid)
returns table (hint_id uuid, hint_order int, hint_title text, prize numeric,
               activated_at timestamptz, hint_count int)
language sql stable security definer set search_path = public as $$
  select h.id, h.hint_order, h.title, h.prize, h.activated_at,
         (select count(*)::int from hints where game_id = g.id)
    from games g
    join hints h on h.game_id = g.id and h.hint_order = g.current_hint_order
   where g.id = p_game_id and is_participant(p_game_id);
$$;

grant execute on function public.get_current_hint(uuid) to authenticated;
