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

notify pgrst, 'reload schema';
