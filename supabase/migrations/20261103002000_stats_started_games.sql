-- =====================================================================
--  Find Me! — thống kê đếm mọi game đã thực sự bắt đầu (chạy sau 20261103001900_host_avatar.sql)
--
--  get_my_stats() trước đây chỉ đếm game live/completed, nên game bị hủy giữa chừng không được
--  tính vào "Đã tổ chức" / "Game đã chơi". Từ nay đếm theo started_at: game đã bắt đầu (kể cả bị hủy
--  sau đó) được tính; bản nháp, game hẹn giờ chưa chạy và game hủy trước khi bắt đầu thì không.
--  Kiểu trả về giữ nguyên (20261103001800) nên create or replace là đủ, quyền thực thi giữ nguyên.
-- =====================================================================

create or replace function public.get_my_stats()
returns table (games_played int, games_hosted int, hints_found int, games_won int, prizes jsonb,
               items_won int)
language sql stable security definer set search_path = public as $$
  select
    (select count(*)::int from game_participants gp join games g on g.id = gp.game_id
      where gp.user_id = auth.uid() and gp.role = 'player' and g.started_at is not null),
    (select count(*)::int from games
      where host_id = auth.uid() and started_at is not null),
    (select count(*)::int from submissions where user_id = auth.uid() and status = 'approved'),
    (select count(*)::int from rewards where winner_id = auth.uid() and kind = 'grand'),
    coalesce((select jsonb_agg(jsonb_build_object('currency', currency, 'amount', amount) order by amount desc)
                from (select currency, sum(amount) as amount from rewards
                       where winner_id = auth.uid() and item is null and amount > 0
                       group by currency) t), '[]'::jsonb),
    (select count(*)::int from rewards where winner_id = auth.uid() and item is not null)
   where auth.uid() is not null;
$$;

notify pgrst, 'reload schema';
