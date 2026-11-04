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

notify pgrst, 'reload schema';
