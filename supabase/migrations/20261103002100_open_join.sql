-- =====================================================================
--  Find Me! — game công khai "mở cho mọi người" (chạy sau 20261103002000_stats_started_games.sql)
--
--  Game công khai có 2 cách tham gia: cần mã (mặc định, như cũ) hoặc mở cho mọi người.
--  1. games.join_open (chỉ có nghĩa khi is_public; game riêng tư luôn bị đưa về false).
--  2. join_open_game(p_game_id): vào game mở mà không cần mã. Chỉ game công khai, đang mở,
--     sắp diễn ra hoặc đang diễn ra. Giới hạn người chơi và luật "1 người, 1 game" vẫn do các
--     trigger trên game_participants giữ (game_full, already_in_active_game).
--  3. get_globe_games() trả thêm join_open để app hiện nút "Tham gia ngay".
-- =====================================================================

-- 1 ------------------------------------------------------------------
alter table public.games add column if not exists join_open boolean not null default false;
grant insert (join_open), update (join_open) on public.games to authenticated;

create or replace function public._join_open_normalize()
returns trigger language plpgsql set search_path = public as $$
begin
  if not new.is_public then new.join_open := false; end if;
  return new;
end $$;
drop trigger if exists join_open_normalize on public.games;
create trigger join_open_normalize before insert or update of is_public, join_open on public.games
  for each row execute function public._join_open_normalize();

-- 2 ------------------------------------------------------------------
create or replace function public.join_open_game(p_game_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare g games%rowtype; v_new int;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  select * into g from games where id = p_game_id and status in ('scheduled', 'live');
  if g.id is null then raise exception 'game_not_found'; end if;
  if not (g.is_public and g.join_open) then raise exception 'game_not_open'; end if;
  insert into game_participants (game_id, user_id, role)
  values (g.id, auth.uid(), 'player') on conflict do nothing;
  get diagnostics v_new = row_count;
  if v_new > 0 then
    perform _emit(g.id, 'player_joined', jsonb_build_object('user_id', auth.uid()));
  end if;
  return g.id;
end $$;

-- 3 ------------------------------------------------------------------
drop function if exists public.get_globe_games();
create function public.get_globe_games()
returns table (id uuid, title text, status public.game_status, is_public boolean,
               area_lat float8, area_lng float8, area_name text,
               host_name text, host_avatar_path text, player_count int, hint_count int,
               grand_prize numeric, currency char(3), grand_prize_item text, join_open boolean,
               starts_at timestamptz, started_at timestamptz, ended_at timestamptz,
               my_role public.participant_role)
language sql stable security definer set search_path = public as $$
  select g.id, g.title, g.status, g.is_public, g.area_lat, g.area_lng, g.area_name,
         p.display_name, p.avatar_path,
         (select count(*)::int from game_participants x where x.game_id = g.id and x.role = 'player'),
         (select count(*)::int from hints h where h.game_id = g.id),
         g.grand_prize, g.currency, g.grand_prize_item, g.join_open, g.starts_at, g.started_at, g.ended_at, me.role
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

revoke all on function public.join_open_game(uuid), public.get_globe_games() from public, anon;
grant execute on function public.join_open_game(uuid), public.get_globe_games() to authenticated;

notify pgrst, 'reload schema';
