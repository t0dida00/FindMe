-- =====================================================================
--  Find Me! — Globe: bản đồ mọi cuộc săn (chạy sau 20261103000300_rankings.sql)
--
--  1. games.is_public + khu vực (area_lat/lng/name) do quản trò ghim. Khu vực được làm tròn
--     2 chữ số thập phân (~1 km) ngay khi ghi, nên vị trí chính xác không bao giờ được lưu.
--     Bật công khai thì bắt buộc có khu vực.
--  2. get_globe_games(): game công khai (không phải nháp, không bị hủy) + game của chính mình
--     có khu vực. KHÔNG trả join_code: người lạ vẫn phải xin mã từ quản trò.
-- =====================================================================

-- 1 ------------------------------------------------------------------
alter table public.games
  add column is_public  boolean not null default false,
  add column area_lat   double precision check (area_lat between -90 and 90),
  add column area_lng   double precision check (area_lng between -180 and 180),
  add column area_name  text check (char_length(area_name) <= 80),
  add constraint games_area_pair check ((area_lat is null) = (area_lng is null)),
  add constraint games_public_needs_area check (not is_public or area_lat is not null);

create or replace function public.round_game_area()
returns trigger language plpgsql as $$
begin
  new.area_lat := round(new.area_lat::numeric, 2)::float8;
  new.area_lng := round(new.area_lng::numeric, 2)::float8;
  new.area_name := nullif(trim(new.area_name), '');
  return new;
end $$;

create trigger games_round_area before insert or update of area_lat, area_lng, area_name
  on public.games for each row execute function public.round_game_area();

create index games_public_idx on public.games (status) where is_public;

grant insert (is_public, area_lat, area_lng, area_name) on public.games to authenticated;
grant update (is_public, area_lat, area_lng, area_name) on public.games to authenticated;

-- 2 ------------------------------------------------------------------
create or replace function public.get_globe_games()
returns table (id uuid, title text, status public.game_status, is_public boolean,
               area_lat float8, area_lng float8, area_name text,
               host_name text, player_count int, hint_count int,
               grand_prize numeric, currency char(3),
               starts_at timestamptz, started_at timestamptz, ended_at timestamptz,
               my_role public.participant_role)
language sql stable security definer set search_path = public as $$
  select g.id, g.title, g.status, g.is_public, g.area_lat, g.area_lng, g.area_name,
         p.display_name,
         (select count(*)::int from game_participants x where x.game_id = g.id and x.role = 'player'),
         (select count(*)::int from hints h where h.game_id = g.id),
         g.grand_prize, g.currency, g.starts_at, g.started_at, g.ended_at, me.role
    from games g
    join profiles p on p.id = g.host_id
    left join game_participants me on me.game_id = g.id and me.user_id = auth.uid()
   where auth.uid() is not null
     and g.area_lat is not null
     and ((g.is_public and g.status not in ('draft', 'cancelled')) or me.user_id is not null)
   order by g.status = 'live' desc, coalesce(g.started_at, g.starts_at, g.created_at) desc
   limit 2000;
$$;

revoke all on function public.get_globe_games(), public.round_game_area() from public, anon, authenticated;
grant execute on function public.get_globe_games() to authenticated;
