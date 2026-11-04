\set ON_ERROR_STOP 1
-- Globe + seed: người lạ (B) thấy 7 game demo công khai chưa kết thúc, không thấy join_code
set role authenticated; set request.jwt.sub = '00000000-0000-0000-0000-00000000000b';
select 'globe demo games (7; 3 game đã kết thúc từ lâu bị ẩn)', count(*) from get_globe_games() where host_name in (select display_name from profiles where id::text like 'de000000-%');
select 'globe statuses', string_agg(status::text || '=' || c, ',' order by status) from (select status, count(*) c from get_globe_games() group by 1) x;
-- Đã kết thúc quá 1 ngày thì biến khỏi Globe; vừa kết thúc thì vẫn còn (kể cả của mình).
select 'globe finished > 1 day (0)', count(*) from get_globe_games()
 where status in ('completed', 'cancelled') and ended_at < now() - interval '1 day';
reset role;
update games set ended_at = now() - interval '2 hours'
 where id = (select id from games where status = 'completed' and is_public and title <> 'Test' order by id limit 1);
set role authenticated; set request.jwt.sub = '00000000-0000-0000-0000-00000000000b';
select 'globe finished 2h ago visible (1)', count(*) from get_globe_games()
 where status = 'completed' and ended_at > now() - interval '1 day' and my_role is null;
select 'globe in HCMC bbox', bool_and(area_lat between 10.6 and 10.95 and area_lng between 106.5 and 106.9) from get_globe_games() where is_public;
select 'area rounded 2dp', bool_and(area_lat = round(area_lat::numeric, 2)::float8) from get_globe_games();
select 'B sees demo games table (0)', count(*) from games where title like '%Chợ Lớn%';
select 'top players', string_agg(display_name || ' w=' || games_won || ' h=' || hints_solved, ' | ' order by rank) from (select * from get_player_rankings(3)) x;
select 'top hosts', string_agg(display_name || ' ' || coalesce(rating_avg::text, '-') || '★ g=' || games_created, ' | ' order by rank) from get_host_rankings(4);
\set ON_ERROR_STOP 0
-- Công khai mà không có khu vực → vi phạm ràng buộc
set request.jwt.sub = '00000000-0000-0000-0000-00000000000b';
insert into games (host_id, title, is_public) values (auth.uid(), 'x', true);

\set ON_ERROR_STOP 1
-- 1 người, 1 cuộc săn
reset role;
select 'demo players in >1 active game (0)', count(*) from (
  select gp.user_id from game_participants gp join games g on g.id = gp.game_id
   where g.status in ('draft','scheduled','live') group by gp.user_id having count(*) > 1) x;
select join_code as jc1 from games where title = 'Bí ẩn phố đi bộ Nguyễn Huệ' \gset
select join_code as jc2 from games where title = 'Dấu chân Hồ Con Rùa' \gset
select gp.user_id as p1 from game_participants gp join games g on g.id = gp.game_id
 where g.title = 'Bí ẩn phố đi bộ Nguyễn Huệ' and gp.role = 'player' limit 1 \gset
set role authenticated;
set request.jwt.sub = :'p1';
select 'p1 active game', title || ' ' || role from get_my_active_game();
select 'p1 rejoin own game ok', join_game(:'jc1') is not null;
\set ON_ERROR_STOP 0
select 'p1 join 2nd game (expect already_in_active_game)', join_game(:'jc2');
insert into games (host_id, title) values (auth.uid(), 'p1 tạo game (expect already_in_active_game)');
\set ON_ERROR_STOP 1
-- B (game Test đã kết thúc): tạo được game mới, rồi không tạo được game thứ hai
set request.jwt.sub = '00000000-0000-0000-0000-00000000000b';
select 'B active before (0)', count(*) from get_my_active_game();
insert into games (host_id, title) values (auth.uid(), 'Game mới của B');
select 'B active now', title || ' ' || role from get_my_active_game();
\set ON_ERROR_STOP 0
insert into games (host_id, title) values (auth.uid(), 'Game thứ hai của B (expect already_in_active_game)');
