-- =====================================================================
--  Find Me! — bảng xếp hạng chung (chạy sau 20261103000200_current_hint.sql)
--
--  1. host_ratings: người chơi chấm 1–5 sao cho quản trò sau khi cuộc săn kết thúc
--     (completed hoặc cancelled). Chỉ đọc/ghi qua hàm.
--  2. rate_host() / get_my_host_rating().
--  3. get_player_rankings(): số game đã tham gia → số game thắng (giải tổng) → hint đã giải.
--     Xếp theo: thắng ↓, hint ↓, số game ↓.
--  4. get_host_rankings(): uy tín (sao) → số game đã tạo → phần thưởng đã trao.
--     Xếp theo điểm uy tín Bayes: (tổng sao + 3×3) / (số lượt + 3), để quản trò mới có
--     1 lượt 5★ không vượt người có nhiều lượt 4.8★. App hiển thị sao trung bình thật.
--     Tiền thưởng chỉ cộng các phần thưởng bằng VND; số lượt thưởng đếm mọi tiền tệ.
--
--  "Đã tham gia" / "đã tạo" chỉ tính game đã bắt đầu (live, completed): bản nháp, game
--  hẹn giờ chưa chạy và game bị hủy không được tính.
--  Cả hai bảng trả top p_limit dòng, cộng thêm dòng của chính người gọi nếu nằm ngoài top.
-- =====================================================================

-- 1 ------------------------------------------------------------------
create table public.host_ratings (
  game_id     uuid not null references public.games (id) on delete cascade,
  rater_id    uuid not null references public.profiles (id) on delete cascade,
  stars       smallint not null check (stars between 1 and 5),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  primary key (game_id, rater_id)
);
create index on public.host_ratings (rater_id);
alter table public.host_ratings enable row level security;
-- Không grant bảng: người chơi chỉ chấm qua rate_host(), không ai đọc lượt chấm của người khác.

-- 2 ------------------------------------------------------------------
create or replace function public.rate_host(p_game_id uuid, p_stars int)
returns void language plpgsql security definer set search_path = public as $$
declare v_status game_status;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  if p_stars not between 1 and 5 then raise exception 'invalid_stars'; end if;
  select status into v_status from games where id = p_game_id;
  if v_status is null then raise exception 'game_not_found'; end if;
  if v_status not in ('completed', 'cancelled') then raise exception 'game_not_finished'; end if;
  if not exists (select 1 from game_participants
                  where game_id = p_game_id and user_id = auth.uid() and role = 'player') then
    raise exception 'not_game_player';
  end if;
  insert into host_ratings (game_id, rater_id, stars) values (p_game_id, auth.uid(), p_stars)
  on conflict (game_id, rater_id) do update set stars = excluded.stars, updated_at = now();
end $$;

create or replace function public.get_my_host_rating(p_game_id uuid)
returns int language sql stable security definer set search_path = public as $$
  select stars::int from host_ratings where game_id = p_game_id and rater_id = auth.uid();
$$;

-- 3 ------------------------------------------------------------------
create or replace function public.get_player_rankings(p_limit int default 100)
returns table (rank bigint, user_id uuid, display_name text, avatar_path text,
               games_joined int, games_won int, hints_solved int)
language sql stable security definer set search_path = public as $$
  with joined as (
    select gp.user_id, count(*)::int as n
      from game_participants gp join games g on g.id = gp.game_id
     where gp.role = 'player' and g.status in ('live', 'completed')
     group by gp.user_id),
  won as (
    select winner_id, count(*)::int as n from rewards where kind = 'grand' group by winner_id),
  solved as (
    select user_id, count(*)::int as n from submissions where status = 'approved' group by user_id),
  ranked as (
    select rank() over (order by coalesce(w.n, 0) desc, coalesce(s.n, 0) desc, j.n desc) as rank,
           j.user_id, p.display_name, p.avatar_path, j.n as games_joined,
           coalesce(w.n, 0) as games_won, coalesce(s.n, 0) as hints_solved
      from joined j
      join profiles p     on p.id = j.user_id
      left join won w     on w.winner_id = j.user_id
      left join solved s  on s.user_id = j.user_id)
  select * from ranked
   where auth.uid() is not null and (rank <= greatest(p_limit, 1) or user_id = auth.uid())
   order by rank, display_name;
$$;

-- 4 ------------------------------------------------------------------
create or replace function public.get_host_rankings(p_limit int default 100)
returns table (rank bigint, user_id uuid, display_name text, avatar_path text,
               rating_avg float8, rating_count int, games_created int,
               rewards_given int, rewards_vnd numeric)
language sql stable security definer set search_path = public as $$
  with created as (
    select host_id, count(*)::int as n from games
     where status in ('live', 'completed') group by host_id),
  ratings as (
    select g.host_id, count(*)::int as n, sum(r.stars)::int as total
      from host_ratings r join games g on g.id = r.game_id group by g.host_id),
  given as (
    select g.host_id, count(*)::int as n,
           coalesce(sum(r.amount) filter (where r.currency = 'VND'), 0) as vnd
      from rewards r join games g on g.id = r.game_id group by g.host_id),
  ranked as (
    select rank() over (order by (coalesce(rt.total, 0) + 9.0) / (coalesce(rt.n, 0) + 3) desc,
                                 coalesce(rt.n, 0) desc, c.n desc, coalesce(gv.vnd, 0) desc) as rank,
           c.host_id as user_id, p.display_name, p.avatar_path,
           round(rt.total::numeric / nullif(rt.n, 0), 1)::float8 as rating_avg,
           coalesce(rt.n, 0) as rating_count, c.n as games_created,
           coalesce(gv.n, 0) as rewards_given, coalesce(gv.vnd, 0) as rewards_vnd
      from created c
      join profiles p     on p.id = c.host_id
      left join ratings rt on rt.host_id = c.host_id
      left join given gv   on gv.host_id = c.host_id)
  select * from ranked
   where auth.uid() is not null and (rank <= greatest(p_limit, 1) or user_id = auth.uid())
   order by rank, display_name;
$$;

-- Supabase tự cấp quyền mặc định cho object mới (cả anon): thu hồi rồi chỉ cấp cho authenticated.
revoke all on public.host_ratings from anon, authenticated;
revoke all on function public.rate_host(uuid, int), public.get_my_host_rating(uuid),
                       public.get_player_rankings(int), public.get_host_rankings(int)
  from public, anon;
grant execute on function public.rate_host(uuid, int), public.get_my_host_rating(uuid),
                          public.get_player_rankings(int), public.get_host_rankings(int)
  to authenticated;
