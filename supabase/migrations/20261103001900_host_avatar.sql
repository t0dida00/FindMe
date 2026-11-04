-- =====================================================================
--  Find Me! — ảnh đại diện quản trò trên card game (chạy sau 20261103001800_item_prizes.sql)
--
--  get_globe_games() và get_game_summary(p_game_id) trả thêm host_avatar_path (profiles.avatar_path,
--  bucket công khai `avatars`) để app vẽ avatar nhỏ trước tên quản trò.
-- =====================================================================

drop function if exists public.get_globe_games();
create function public.get_globe_games()
returns table (id uuid, title text, status public.game_status, is_public boolean,
               area_lat float8, area_lng float8, area_name text,
               host_name text, host_avatar_path text, player_count int, hint_count int,
               grand_prize numeric, currency char(3), grand_prize_item text,
               starts_at timestamptz, started_at timestamptz, ended_at timestamptz,
               my_role public.participant_role)
language sql stable security definer set search_path = public as $$
  select g.id, g.title, g.status, g.is_public, g.area_lat, g.area_lng, g.area_name,
         p.display_name, p.avatar_path,
         (select count(*)::int from game_participants x where x.game_id = g.id and x.role = 'player'),
         (select count(*)::int from hints h where h.game_id = g.id),
         g.grand_prize, g.currency, g.grand_prize_item, g.starts_at, g.started_at, g.ended_at, me.role
    from games g
    join profiles p on p.id = g.host_id
    left join game_participants me on me.game_id = g.id and me.user_id = auth.uid()
   where auth.uid() is not null
     and g.area_lat is not null
     and ((g.is_public and g.status not in ('draft', 'cancelled')) or me.user_id is not null)
     and (g.status not in ('completed', 'cancelled')
          or coalesce(g.ended_at, g.updated_at) > now() - interval '1 day')
   order by g.status = 'live' desc, coalesce(g.started_at, g.starts_at, g.created_at) desc
   limit 2000;
$$;

drop function if exists public.get_game_summary(uuid);
create function public.get_game_summary(p_game_id uuid)
returns table (host_name text, host_avatar_path text, player_count int, hint_count int, solved_count int)
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_participant(p_game_id) then raise exception 'not_game_player'; end if;
  return query
    select p.display_name, p.avatar_path,
           (select count(*)::int from game_participants x where x.game_id = g.id and x.role = 'player'),
           (select count(*)::int from hints h where h.game_id = g.id),
           (select count(*)::int from hints h where h.game_id = g.id and h.revealed_at is not null)
      from games g join profiles p on p.id = g.host_id
     where g.id = p_game_id;
end $$;

revoke all on function public.get_globe_games(), public.get_game_summary(uuid) from public, anon;
grant execute on function public.get_globe_games(), public.get_game_summary(uuid) to authenticated;

notify pgrst, 'reload schema';
