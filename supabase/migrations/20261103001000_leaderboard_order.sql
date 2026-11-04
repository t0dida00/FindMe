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

notify pgrst, 'reload schema';
