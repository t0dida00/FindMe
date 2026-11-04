-- Find Me!: chạy bù các migration còn thiếu trên server (theo kiểm tra ngày 2026-11-04):
--   0900 my_stats, 1000 leaderboard_order, 1100 globe_recent_finished, 1500 hint_prize_cap,
--   1700 game_summary, 1800 item_prizes, 1900 host_avatar.
-- Dán toàn bộ vào Supabase SQL Editor rồi bấm Run MỘT lần. Cả file nằm trong một transaction:
-- lỗi ở đâu thì không có gì thay đổi.

begin;

-- >>>>>>>>>>>>>>>>>>>> 20261103000900_my_stats.sql
-- =====================================================================
--  Find Me! — thống kê và lịch sử cá nhân cho tab Hồ sơ (chạy sau 20261103000800_min_one_hint.sql)
--
--  1. get_my_stats(): một dòng cho người đang đăng nhập.
--     games_played: số cuộc săn đã chơi với vai người chơi (live/completed, giống get_player_rankings)
--     games_hosted: số cuộc săn đã tổ chức (live/completed)
--     hints_found : số proof được duyệt; games_won: số giải chung cuộc
--     prizes      : tổng tiền thưởng theo từng loại tiền, [{"currency":"VND","amount":300000}, …]
--  2. get_my_history(): mọi cuộc săn đã chơi/tổ chức trừ bản nháp, mới nhất trước, kèm số hint
--     đã tìm và tiền thưởng nhận được trong cuộc săn đó.
-- =====================================================================

-- 1 ------------------------------------------------------------------
create or replace function public.get_my_stats()
returns table (games_played int, games_hosted int, hints_found int, games_won int, prizes jsonb)
language sql stable security definer set search_path = public as $$
  select
    (select count(*)::int from game_participants gp join games g on g.id = gp.game_id
      where gp.user_id = auth.uid() and gp.role = 'player' and g.status in ('live', 'completed')),
    (select count(*)::int from games
      where host_id = auth.uid() and status in ('live', 'completed')),
    (select count(*)::int from submissions where user_id = auth.uid() and status = 'approved'),
    (select count(*)::int from rewards where winner_id = auth.uid() and kind = 'grand'),
    coalesce((select jsonb_agg(jsonb_build_object('currency', currency, 'amount', amount) order by amount desc)
                from (select currency, sum(amount) as amount from rewards
                       where winner_id = auth.uid() group by currency) t), '[]'::jsonb)
   where auth.uid() is not null;
$$;

-- 2 ------------------------------------------------------------------
create or replace function public.get_my_history(p_limit int default 50)
returns table (game_id uuid, title text, status public.game_status, role public.participant_role,
               played_at timestamptz, hint_count int, hints_found int,
               reward_amount numeric, currency char(3))
language sql stable security definer set search_path = public as $$
  select g.id, g.title, g.status, gp.role,
         coalesce(g.ended_at, g.started_at, g.starts_at, gp.joined_at),
         (select count(*)::int from hints h where h.game_id = g.id),
         (select count(*)::int from submissions s
           where s.game_id = g.id and s.user_id = auth.uid() and s.status = 'approved'),
         coalesce((select sum(r.amount) from rewards r
                    where r.game_id = g.id and r.winner_id = auth.uid()), 0),
         g.currency
    from game_participants gp
    join games g on g.id = gp.game_id
   where gp.user_id = auth.uid() and g.status <> 'draft'
   order by coalesce(g.ended_at, g.started_at, g.starts_at, gp.joined_at) desc
   limit greatest(p_limit, 1);
$$;

revoke all on function public.get_my_stats(), public.get_my_history(int) from public, anon;
grant execute on function public.get_my_stats(), public.get_my_history(int) to authenticated;


-- >>>>>>>>>>>>>>>>>>>> 20261103001000_leaderboard_order.sql
-- =====================================================================
--  Find Me! — sửa thứ tự bảng xếp hạng trong cuộc săn (chạy sau 20261103000900_my_stats.sql)
--
--  get_leaderboard() cũ xếp theo số mốc thắng rồi tổng thời gian, bỏ qua tổng thưởng; nên người
--  thắng giải tổng có thể đứng sau hoặc đồng hạng với người chỉ thắng một mốc nhỏ.
--  Thứ tự đúng theo F-25: mốc thắng ↓ → tổng thưởng ↓ → tổng thời gian ↑.
--  Kiểu trả về giữ nguyên nên create or replace là đủ (quyền thực thi giữ nguyên).
-- =====================================================================

create or replace function public.get_leaderboard(p_game_id uuid)
returns table (rank bigint, user_id uuid, display_name text, milestones_won int,
               total_reward numeric, total_seconds int)
language sql stable security definer set search_path = public as $$
  with wins as (
    select s.user_id, count(*)::int as won,
           sum(extract(epoch from (s.reserved_at - h.activated_at)))::int as secs
      from submissions s join hints h on h.id = s.hint_id
     where s.game_id = p_game_id and s.status = 'approved'
     group by s.user_id),
  money as (
    select winner_id, sum(amount) as total from rewards
     where game_id = p_game_id group by winner_id)
  select rank() over (order by coalesce(w.won, 0) desc, coalesce(m.total, 0) desc,
                               w.secs asc nulls last),
         gp.user_id, p.display_name, coalesce(w.won, 0), coalesce(m.total, 0), coalesce(w.secs, 0)
    from game_participants gp
    join profiles p     on p.id = gp.user_id
    left join wins w    on w.user_id = gp.user_id
    left join money m   on m.winner_id = gp.user_id
   where gp.game_id = p_game_id and gp.role = 'player' and is_participant(p_game_id)
   order by 1, p.display_name;
$$;


-- >>>>>>>>>>>>>>>>>>>> 20261103001100_globe_recent_finished.sql
-- =====================================================================
--  Find Me! — Globe chỉ giữ cuộc săn đã kết thúc trong 1 ngày (chạy sau 20261103001000_leaderboard_order.sql)
--
--  get_globe_games() (Globe + danh sách "Các cuộc săn" ở tab Cuộc săn) bỏ các cuộc săn đã kết thúc
--  hoặc bị hủy quá 1 ngày (theo ended_at), kể cả của chính mình. Lịch sử cá nhân (get_my_history)
--  vẫn giữ đủ; người chơi vẫn mở lại được cuộc săn cũ từ đó.
--  Kiểu trả về giữ nguyên nên create or replace là đủ (quyền thực thi giữ nguyên).
-- =====================================================================

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
     and (g.status not in ('completed', 'cancelled')
          or coalesce(g.ended_at, g.updated_at) > now() - interval '1 day')
   order by g.status = 'live' desc, coalesce(g.started_at, g.starts_at, g.created_at) desc
   limit 2000;
$$;


-- >>>>>>>>>>>>>>>>>>>> 20261103001500_hint_prize_cap.sql
-- =====================================================================
--  Find Me! — thưởng mốc của hint không được lớn hơn giải thưởng tổng
--  (chạy sau 20261103001400_live_hint_editing.sql)
--
--  1. Thêm/sửa hint với prize > games.grand_prize → 'hint_prize_over_grand'.
--  2. Hạ games.grand_prize xuống dưới thưởng của một hint đã có → 'grand_prize_below_hint'.
--  Chỉ kiểm tra khi giá trị thay đổi, nên dữ liệu cũ (nếu có) không bị chặn khi sửa cột khác.
-- =====================================================================

-- 1 ------------------------------------------------------------------
create or replace function public._hint_prize_cap()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and new.prize is not distinct from old.prize then return new; end if;
  if new.prize > (select grand_prize from games where id = new.game_id) then
    raise exception 'hint_prize_over_grand';
  end if;
  return new;
end $$;

drop trigger if exists hint_prize_cap on public.hints;
create trigger hint_prize_cap before insert or update of prize on public.hints
  for each row execute function public._hint_prize_cap();

-- 2 ------------------------------------------------------------------
create or replace function public._grand_prize_cap()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.grand_prize is not distinct from old.grand_prize then return new; end if;
  if exists (select 1 from hints where game_id = new.id and prize > new.grand_prize) then
    raise exception 'grand_prize_below_hint';
  end if;
  return new;
end $$;

drop trigger if exists grand_prize_cap on public.games;
create trigger grand_prize_cap before update of grand_prize on public.games
  for each row execute function public._grand_prize_cap();


-- >>>>>>>>>>>>>>>>>>>> 20261103001700_game_summary.sql
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


-- >>>>>>>>>>>>>>>>>>>> 20261103001800_item_prizes.sql
-- =====================================================================
--  Find Me! — giải thưởng hiện vật (chạy sau 20261103001700_game_summary.sql)
--
--  Mỗi giải (giải tổng của game, thưởng mốc của hint) là TIỀN (số tiền + games.currency) hoặc
--  HIỆN VẬT (tên món quà, 1–120 ký tự). Quản trò chọn; người chơi chỉ xem.
--
--  1. Cột games.grand_prize_item, hints.prize_item, rewards.item (null = tiền).
--     Trigger chuẩn hóa: tên trim, rỗng → null; có hiện vật thì tiền = 0.
--  2. Luật 20261103001500 (thưởng mốc ≤ giải tổng) chỉ áp dụng khi CẢ HAI là tiền.
--  3. rewards.item tự điền khi ghi phần thưởng (approve hint), không phải sửa _approve.
--  4. create_hint nhận thêm p_prize_item; sửa prize_item khi live cũng bắn 'hint_updated'.
--  5. get_hint_items / get_current_hint / get_globe_games trả thêm tên hiện vật.
--  6. get_my_stats: prizes chỉ cộng tiền, thêm items_won; get_my_history thêm reward_items.
-- =====================================================================

-- 1 ------------------------------------------------------------------
alter table public.games  add column if not exists grand_prize_item text
  check (grand_prize_item is null or char_length(grand_prize_item) between 1 and 120);
alter table public.hints  add column if not exists prize_item text
  check (prize_item is null or char_length(prize_item) between 1 and 120);
alter table public.rewards add column if not exists item text;

grant insert (grand_prize_item), update (grand_prize_item) on public.games to authenticated;
grant update (prize_item) on public.hints to authenticated;

-- 1 + 2: games -------------------------------------------------------
-- Thay trigger grand_prize_cap của 20261103001500: chuẩn hóa + kiểm tra trong một hàm.
drop trigger if exists grand_prize_cap on public.games;
create or replace function public._grand_prize_cap()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.grand_prize_item := nullif(trim(new.grand_prize_item), '');
  if new.grand_prize_item is not null then new.grand_prize := 0; end if;

  if tg_op = 'UPDATE'
     and (new.grand_prize, new.grand_prize_item) is distinct from (old.grand_prize, old.grand_prize_item)
     and new.grand_prize_item is null
     and exists (select 1 from hints where game_id = new.id and prize_item is null and prize > new.grand_prize) then
    raise exception 'grand_prize_below_hint';
  end if;
  return new;
end $$;
create trigger grand_prize_cap before insert or update on public.games
  for each row execute function public._grand_prize_cap();

-- 1 + 2: hints -------------------------------------------------------
drop trigger if exists hint_prize_cap on public.hints;
create or replace function public._hint_prize_cap()
returns trigger language plpgsql security definer set search_path = public as $$
declare g games%rowtype;
begin
  new.prize_item := nullif(trim(new.prize_item), '');
  if new.prize_item is not null then new.prize := 0; end if;

  if tg_op = 'UPDATE' and (new.prize, new.prize_item) is not distinct from (old.prize, old.prize_item) then
    return new;
  end if;
  select * into g from games where id = new.game_id;
  if new.prize_item is null and g.grand_prize_item is null and new.prize > g.grand_prize then
    raise exception 'hint_prize_over_grand';
  end if;
  return new;
end $$;
create trigger hint_prize_cap before insert or update on public.hints
  for each row execute function public._hint_prize_cap();

-- 3 ------------------------------------------------------------------
create or replace function public._reward_fill_item()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.item is null then
    if new.kind = 'grand' then
      select grand_prize_item into new.item from games where id = new.game_id;
    else
      select prize_item into new.item from hints where id = new.hint_id;
    end if;
  end if;
  if new.item is not null then new.amount := 0; end if;
  return new;
end $$;
drop trigger if exists reward_fill_item on public.rewards;
create trigger reward_fill_item before insert on public.rewards
  for each row execute function public._reward_fill_item();

-- 4 ------------------------------------------------------------------
drop function if exists public.create_hint(uuid, int, text, float8, float8, numeric, text, text);
create function public.create_hint(
  p_game_id uuid, p_hint_order int, p_code text,
  p_answer_lat float8, p_answer_lng float8,
  p_prize numeric default 0, p_title text default null, p_description text default null,
  p_prize_item text default null)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare v_id uuid;
begin
  if not is_game_staff(p_game_id) then raise exception 'not_game_staff'; end if;
  if not game_is_editable(p_game_id) then raise exception 'game_not_editable'; end if;
  if nullif(trim(p_title), '') is null then raise exception 'hint_title_required'; end if;
  if char_length(normalize_code(p_code)) < 6 then raise exception 'code_too_short'; end if;

  insert into hints (game_id, hint_order, title, description, prize, prize_item, answer_lat, answer_lng, code_hash)
  values (p_game_id, p_hint_order, trim(p_title), nullif(trim(p_description), ''),
          p_prize, p_prize_item, p_answer_lat, p_answer_lng, crypt(normalize_code(p_code), gen_salt('bf')))
  returning id into v_id;
  insert into hint_codes (hint_id, code) values (v_id, trim(p_code));
  return v_id;
end $$;

create or replace function public._emit_hint_updated()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (new.title, new.description, new.prize, new.prize_item)
     is not distinct from (old.title, old.description, old.prize, old.prize_item) then
    return null;
  end if;
  if exists (select 1 from games where id = new.game_id and status = 'live') then
    perform _emit(new.game_id, 'hint_updated', jsonb_build_object('hint_order', new.hint_order));
  end if;
  return null;
end $$;
drop trigger if exists hints_emit_updated on public.hints;
create trigger hints_emit_updated after update of title, description, prize, prize_item on public.hints
  for each row execute function public._emit_hint_updated();

-- 5 ------------------------------------------------------------------
drop function if exists public.get_hint_items(uuid);
create function public.get_hint_items(p_game_id uuid)
returns table (hint_id uuid, hint_order int, hint_title text, hint_description text, prize numeric,
               prize_item text, hint_activated_at timestamptz, hint_solved boolean,
               item_id uuid, item_order int, type public.hint_item_type,
               text_content text, image_path text,
               map_center_lat float8, map_center_lng float8, map_radius_m int)
language sql stable security definer set search_path = public as $$
  select h.id, h.hint_order, h.title, h.description, h.prize, h.prize_item,
         h.activated_at, h.revealed_at is not null,
         i.id, i.item_order, i.type, i.text_content, i.image_path,
         i.map_center_lat, i.map_center_lng, i.map_radius_m
    from hints h
    join hint_items i on i.hint_id = h.id
   where h.game_id = p_game_id
     and is_participant(p_game_id)
     and h.activated_at is not null
     and (h.revealed_at is not null
          or i.reveal_after_minutes is null
          or h.activated_at + make_interval(mins => i.reveal_after_minutes) <= now())
   order by h.hint_order, i.item_order;
$$;

drop function if exists public.get_current_hint(uuid);
create function public.get_current_hint(p_game_id uuid)
returns table (hint_id uuid, hint_order int, hint_title text, hint_description text, prize numeric,
               prize_item text, activated_at timestamptz, hint_count int)
language sql stable security definer set search_path = public as $$
  select h.id, h.hint_order, h.title, h.description, h.prize, h.prize_item, h.activated_at,
         (select count(*)::int from hints where game_id = g.id)
    from games g
    join hints h on h.game_id = g.id and h.hint_order = g.current_hint_order
   where g.id = p_game_id and is_participant(p_game_id);
$$;

drop function if exists public.get_globe_games();
create function public.get_globe_games()
returns table (id uuid, title text, status public.game_status, is_public boolean,
               area_lat float8, area_lng float8, area_name text,
               host_name text, player_count int, hint_count int,
               grand_prize numeric, currency char(3), grand_prize_item text,
               starts_at timestamptz, started_at timestamptz, ended_at timestamptz,
               my_role public.participant_role)
language sql stable security definer set search_path = public as $$
  select g.id, g.title, g.status, g.is_public, g.area_lat, g.area_lng, g.area_name,
         p.display_name,
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

-- 6 ------------------------------------------------------------------
drop function if exists public.get_my_stats();
create function public.get_my_stats()
returns table (games_played int, games_hosted int, hints_found int, games_won int, prizes jsonb,
               items_won int)
language sql stable security definer set search_path = public as $$
  select
    (select count(*)::int from game_participants gp join games g on g.id = gp.game_id
      where gp.user_id = auth.uid() and gp.role = 'player' and g.status in ('live', 'completed')),
    (select count(*)::int from games
      where host_id = auth.uid() and status in ('live', 'completed')),
    (select count(*)::int from submissions where user_id = auth.uid() and status = 'approved'),
    (select count(*)::int from rewards where winner_id = auth.uid() and kind = 'grand'),
    coalesce((select jsonb_agg(jsonb_build_object('currency', currency, 'amount', amount) order by amount desc)
                from (select currency, sum(amount) as amount from rewards
                       where winner_id = auth.uid() and item is null and amount > 0
                       group by currency) t), '[]'::jsonb),
    (select count(*)::int from rewards where winner_id = auth.uid() and item is not null)
   where auth.uid() is not null;
$$;

drop function if exists public.get_my_history(int);
create function public.get_my_history(p_limit int default 50)
returns table (game_id uuid, title text, status public.game_status, role public.participant_role,
               played_at timestamptz, hint_count int, hints_found int,
               reward_amount numeric, currency char(3), reward_items text)
language sql stable security definer set search_path = public as $$
  select g.id, g.title, g.status, gp.role,
         coalesce(g.ended_at, g.started_at, g.starts_at, gp.joined_at),
         (select count(*)::int from hints h where h.game_id = g.id),
         (select count(*)::int from submissions s
           where s.game_id = g.id and s.user_id = auth.uid() and s.status = 'approved'),
         coalesce((select sum(r.amount) from rewards r
                    where r.game_id = g.id and r.winner_id = auth.uid() and r.item is null), 0),
         g.currency,
         (select string_agg(r.item, ', ' order by r.created_at) from rewards r
           where r.game_id = g.id and r.winner_id = auth.uid() and r.item is not null)
    from game_participants gp
    join games g on g.id = gp.game_id
   where gp.user_id = auth.uid() and g.status <> 'draft'
   order by coalesce(g.ended_at, g.started_at, g.starts_at, gp.joined_at) desc
   limit greatest(p_limit, 1);
$$;

-- Supabase tự cấp quyền mặc định cho hàm mới (cả anon): thu hồi rồi chỉ cấp cho authenticated.
revoke all on function public.create_hint(uuid, int, text, float8, float8, numeric, text, text, text),
                       public.get_hint_items(uuid), public.get_current_hint(uuid), public.get_globe_games(),
                       public.get_my_stats(), public.get_my_history(int)
  from public, anon;
grant execute on function public.create_hint(uuid, int, text, float8, float8, numeric, text, text, text),
                          public.get_hint_items(uuid), public.get_current_hint(uuid), public.get_globe_games(),
                          public.get_my_stats(), public.get_my_history(int)
  to authenticated;


-- >>>>>>>>>>>>>>>>>>>> 20261103001900_host_avatar.sql
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


commit;

notify pgrst, 'reload schema';
