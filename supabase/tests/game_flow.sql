\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
insert into auth.users (id, raw_user_meta_data) values
 ('00000000-0000-0000-0000-00000000000a', '{"display_name":"Host"}'),
 ('00000000-0000-0000-0000-00000000000b', '{"display_name":"An"}'),
 ('00000000-0000-0000-0000-00000000000c', '{"display_name":"Bình"}'),
 ('00000000-0000-0000-0000-00000000000d', '{}');
create temp table ctx (k text primary key, v uuid); grant all on ctx to authenticated;

-- HOST
set role authenticated; set request.jwt.sub = '00000000-0000-0000-0000-00000000000a';
with x as (insert into games (host_id, title, grand_prize) values (auth.uid(), 'Test', 1000000) returning id) insert into ctx select 'game', id from x;
select 'currency default', currency from games;
insert into ctx values ('h1', create_hint((select v from ctx where k='game'), 1, 'abc-def-12', 21.0285, 105.8542, 100000, 'Hồ Gươm', '  Quanh hồ, phía tháp Rùa  '));
insert into ctx values ('h2', create_hint((select v from ctx where k='game'), 2, generate_hint_code(), 21.0367, 105.8346, 200000, 'Lăng'));
select 'set code', set_hint_code((select v from ctx where k='h2'), 'LANG-2026');
select 'host sees codes', string_agg(code, ',' order by code) from hint_codes;
insert into hint_items (hint_id, item_order, type, text_content) values ((select v from ctx where k='h1'), 1, 'text', 'Nơi rùa thần');
insert into hint_items (hint_id, item_order, type, map_radius_m, reveal_after_minutes) values ((select v from ctx where k='h1'), 2, 'map', 300, 5);
insert into hint_items (hint_id, item_order, type, text_content) values ((select v from ctx where k='h2'), 1, 'text', 'Ba Đình');
select 'map center dist m (<=240)', round((111320*sqrt(power(map_center_lat-21.0285,2)+power((map_center_lng-105.8542)*cos(radians(21.0285)),2)))::numeric) from hint_items where type='map';
update hints set answer_lat = 21.03 where id = (select v from ctx where k='h1');
select 'recentred after move (<=240)', round((111320*sqrt(power(map_center_lat-21.03,2)+power((map_center_lng-105.8542)*cos(radians(21.03)),2)))::numeric) from hint_items where type='map';
update hints set answer_lat = 21.0285 where id = (select v from ctx where k='h1');
select 'description trimmed / h2 none', (select description from hints where id = (select v from ctx where k='h1')) || ' / ' || coalesce((select description from hints where id = (select v from ctx where k='h2')), 'null');
update hints set description = 'Lăng Bác, cổng chính' where id = (select v from ctx where k='h2');
-- Thưởng mốc không vượt giải thưởng tổng (1.000.000)
\set ON_ERROR_STOP 0
update hints set prize = 1000001 where id = (select v from ctx where k='h2'); -- expect hint_prize_over_grand
select 'create hint prize > grand (expect hint_prize_over_grand)', create_hint((select v from ctx where k='game'), 3, 'BIGPRIZE1', 21.03, 105.85, 2000000, 'Quá');
update games set grand_prize = 150000; -- expect grand_prize_below_hint (h2 = 200000)
\set ON_ERROR_STOP 1
update hints set prize = 1000000 where id = (select v from ctx where k='h1');
update hints set prize = 100000 where id = (select v from ctx where k='h1');
select 'prize cap: h2 prize / grand / hints', (select prize from hints where id = (select v from ctx where k='h2')) || ' / ' || (select grand_prize from games) || ' / ' || (select count(*) from hints);

-- PLAYERS JOIN
select join_code as jc from games \gset
select 'defaults max_players/retention', max_players || ' ' || proof_retention_days from games;
update games set max_players = 2;
set request.jwt.sub = '00000000-0000-0000-0000-00000000000b'; select 'join B', join_game(:'jc') is not null;
select 'player sees no codes (0)', count(*) from hint_codes;
set request.jwt.sub = '00000000-0000-0000-0000-00000000000c'; select 'join C', join_game(:'jc') is not null;
set request.jwt.sub = '00000000-0000-0000-0000-00000000000b'; select 'rejoin B when full', join_game(:'jc') is not null;
\set ON_ERROR_STOP 0
set request.jwt.sub = '00000000-0000-0000-0000-00000000000d'; select 'join D (expect game_full)', join_game(:'jc');
set request.jwt.sub = '00000000-0000-0000-0000-00000000000a';
update games set max_players = 1;
update games set max_players = 51;
update games set proof_retention_days = 30;
\set ON_ERROR_STOP 1
update games set max_players = 50;
set request.jwt.sub = '00000000-0000-0000-0000-00000000000d'; select 'join D', join_game(:'jc') is not null;
select 'players / max', (select count(*) from game_participants where role = 'player') || '/' || max_players from games;
reset role; select 'player_joined events (3)', count(*) from game_events where type='player_joined'; set role authenticated;

set request.jwt.sub = '00000000-0000-0000-0000-00000000000a'; select 'start', start_game((select v from ctx where k='game'));

-- B: 3 sai → khóa
set request.jwt.sub = '00000000-0000-0000-0000-00000000000b';
select 'B current hint', hint_order || ' ' || hint_title || ' (' || hint_description || ') of ' || hint_count from get_current_hint((select v from ctx where k='game'));
select 'B items visible (1: map locked 5m)', count(*) from get_hint_items((select v from ctx where k='game'));
select 'B item description', hint_description from get_hint_items((select v from ctx where k='game')) limit 1;
select 'B hints direct (0)', count(*) from hints;
select 'B wrong1', redeem_code((select v from ctx where k='h1'), 'nope');
select 'B wrong2', redeem_code((select v from ctx where k='h1'), 'nope');
select 'B wrong3', redeem_code((select v from ctx where k='h1'), 'nope');
select 'B locked', redeem_code((select v from ctx where k='h1'), 'ABCDEF12')->>'error';
select 'B state', get_my_code_state((select v from ctx where k='h1'));

-- C giữ mã, D nhập đúng → code_in_use
set request.jwt.sub = '00000000-0000-0000-0000-00000000000c';
select 'C redeem', redeem_code((select v from ctx where k='h1'), ' abc def 12 ')->>'ok';
set request.jwt.sub = '00000000-0000-0000-0000-00000000000d';
select 'D redeem', redeem_code((select v from ctx where k='h1'), 'ABCDEF12')->>'error';
select 'D code status', get_current_code_status((select v from ctx where k='game'));
set request.jwt.sub = '00000000-0000-0000-0000-00000000000c';
select 'C attach', attach_photo((select id from submissions where status='reserved'), (select v from ctx where k='game') || '/00000000-0000-0000-0000-00000000000c/p1.jpg');
select 'C sub status', status from submissions;
-- Host deny
set request.jwt.sub = '00000000-0000-0000-0000-00000000000a';
select 'deny', review_submission((select id from submissions where status='pending'), false, 'Ảnh mờ');
-- D lấy mã, để hết hạn
set request.jwt.sub = '00000000-0000-0000-0000-00000000000d';
select 'D redeem2', redeem_code((select v from ctx where k='h1'), 'ABCDEF12')->>'ok';
reset role; update submissions set upload_deadline = now() - interval '1 s' where status='reserved'; select process_timers();
select 'after expiry', string_agg(status::text, ',' order by reserved_at) from submissions;
-- C lấy lại mã, tải ảnh, nhắc phút 5, rồi tự approve
set role authenticated; set request.jwt.sub = '00000000-0000-0000-0000-00000000000c';
select 'C redeem2', redeem_code((select v from ctx where k='h1'), 'ABCDEF12')->>'ok';
select 'C attach2', attach_photo((select id from submissions where status='reserved'), (select v from ctx where k='game') || '/00000000-0000-0000-0000-00000000000c/p2.jpg');
reset role; update submissions set uploaded_at = now() - interval '6 min' where status='pending'; select process_timers();
select 'reminders', count(*) from game_events where type='proof_review_reminder';
update submissions set auto_approve_at = now() - interval '1 s' where status='pending'; select process_timers();
select 'auto approved', auto_approved from submissions where status='approved';
select 'current hint', current_hint_order from games;
-- Sửa hint khi đang live: h2 (chưa giải) sửa được tiêu đề/thưởng; h1 (đã giải) bị khóa;
-- vị trí, mã và thứ tự bị khóa
set role authenticated; set request.jwt.sub = '00000000-0000-0000-0000-00000000000a';
update hints set title = 'Lăng Bác', prize = 250000 where id = (select v from ctx where k='h2');
update hints set title = 'Đổi' where id = (select v from ctx where k='h1');
select 'live edit: h2 title prize / h1 title', (select title || ' ' || prize from hints where id = (select v from ctx where k='h2')) || ' / ' || (select title from hints where id = (select v from ctx where k='h1'));
\set ON_ERROR_STOP 0
update hints set answer_lat = 21.04 where id = (select v from ctx where k='h2'); -- expect hint_location_locked
update hints set hint_order = 9 where id = (select v from ctx where k='h2'); -- expect hint_order_locked
select 'live set code h2 (expect game_not_editable)', set_hint_code((select v from ctx where k='h2'), 'LANG-2027');
\set ON_ERROR_STOP 1
update hints set prize = 200000 where id = (select v from ctx where k='h2');
reset role; select 'hint_updated events (2)', count(*) from game_events where type='hint_updated';
-- Khối gợi ý (20261103001600): live vẫn thêm/sửa/xóa được ở hint chưa giải (h2), không được ở hint đã giải (h1)
set role authenticated; set request.jwt.sub = '00000000-0000-0000-0000-00000000000a';
insert into hint_items (hint_id, item_order, type, image_path) values ((select v from ctx where k='h2'), 2, 'image', (select v from ctx where k='game') || '/live.jpg');
update hint_items set image_path = (select v from ctx where k='game') || '/live2.jpg' where hint_id = (select v from ctx where k='h2') and type = 'image';
select 'live item h2 image', image_path like '%/live2.jpg' from hint_items where hint_id = (select v from ctx where k='h2') and type = 'image';
delete from hint_items where hint_id = (select v from ctx where k='h2') and type = 'image';
\set ON_ERROR_STOP 0
insert into hint_items (hint_id, item_order, type, text_content) values ((select v from ctx where k='h1'), 9, 'text', 'x'); -- expect RLS
\set ON_ERROR_STOP 1
reset role; select 'hint_updated events (5)', count(*) from game_events where type='hint_updated';
-- Tóm tắt game cho card "Game của tôi" (20261103001700): người chơi B thấy số người chơi và x/y hint
set role authenticated; set request.jwt.sub = '00000000-0000-0000-0000-00000000000b';
select 'B game summary (solved 1)', * from get_game_summary((select v from ctx where k='game'));
select 'B game summary host avatar (null)', coalesce(host_avatar_path, 'null') from get_game_summary((select v from ctx where k='game'));
reset role;
-- Hint 2: B giải, host approve
set role authenticated; set request.jwt.sub = '00000000-0000-0000-0000-00000000000b';
select 'B h1 after solved', (select count(*) from get_hint_items((select v from ctx where k='game')));
select 'B redeem h2', redeem_code((select v from ctx where k='h2'), 'lang 2026')->>'ok';
select 'B attach h2', attach_photo((select id from submissions where status='reserved'), (select v from ctx where k='game') || '/00000000-0000-0000-0000-00000000000b/p.jpg');
set request.jwt.sub = '00000000-0000-0000-0000-00000000000a';
select 'approve', review_submission((select id from submissions where status='pending'), true);
select 'game status', status from games;
select 'rewards', string_agg(kind || ':' || amount || ' ' || currency, ', ' order by amount) from rewards;
set request.jwt.sub = '00000000-0000-0000-0000-00000000000d';
-- Cùng 1 mốc thắng: người có tổng thưởng cao hơn (An, có giải tổng) phải đứng trên, không đồng hạng.
select 'leaderboard (1 An | 2 Bình | 3 Người chơi)', string_agg(rank || ' ' || display_name || ' won=' || milestones_won || ' reward=' || total_reward, ' | ' order by rank) from get_leaderboard((select v from ctx where k='game'));
select 'answers', string_agg(hint_order || ' ' || winner_name || ' photo=' || coalesce(winner_photo_path is not null, false), ' | ') from get_revealed_answers((select v from ctx where k='game'));
select 'D sees others subs (0)', count(*) from submissions where user_id <> auth.uid();
-- Xếp hạng chung + chấm sao quản trò
set request.jwt.sub = '00000000-0000-0000-0000-00000000000b'; select 'B rate 5', rate_host((select v from ctx where k='game'), 5);
select 'B re-rate 5', rate_host((select v from ctx where k='game'), 5);
select 'B my rating', get_my_host_rating((select v from ctx where k='game'));
set request.jwt.sub = '00000000-0000-0000-0000-00000000000c'; select 'C rate 4', rate_host((select v from ctx where k='game'), 4);
set request.jwt.sub = '00000000-0000-0000-0000-00000000000d';
select 'player rankings', string_agg(rank || ' ' || display_name || ' joined=' || games_joined || ' won=' || games_won || ' hints=' || hints_solved, ' | ' order by rank, display_name) from get_player_rankings();
set request.jwt.sub = '00000000-0000-0000-0000-00000000000b';
select 'B stats', games_played || ' played ' || games_hosted || ' hosted ' || hints_found || ' found ' || games_won || ' won ' || prizes from get_my_stats();
select 'B history', string_agg(title || ' ' || status || ' ' || role || ' ' || hints_found || '/' || hint_count || ' ' || reward_amount || ' ' || currency, ' | ') from get_my_history();
set request.jwt.sub = '00000000-0000-0000-0000-00000000000a';
select 'host stats', games_played || ' played ' || games_hosted || ' hosted ' || prizes from get_my_stats();
set request.jwt.sub = '00000000-0000-0000-0000-00000000000d';
select 'player rankings top1 + me', string_agg(display_name, ',' order by rank) from get_player_rankings(1);
select 'host rankings', string_agg(display_name || ' avg=' || rating_avg || ' n=' || rating_count || ' created=' || games_created || ' given=' || rewards_given || ' vnd=' || rewards_vnd, ' | ') from get_host_rankings();
\set ON_ERROR_STOP 0
select 'D code_attempts', count(*) from code_attempts;
select 'D host_ratings direct', count(*) from host_ratings;
set request.jwt.sub = '00000000-0000-0000-0000-00000000000a';
select 'host rates self (expect not_game_player)', rate_host((select v from ctx where k='game'), 5);
set request.jwt.sub = '00000000-0000-0000-0000-00000000000d';
select 'D rate 9 (expect invalid_stars)', rate_host((select v from ctx where k='game'), 9);
select 'D cohost (expect not_game_host)', set_participant_role((select v from ctx where k='game'), '00000000-0000-0000-0000-00000000000d', 'cohost');
\set ON_ERROR_STOP 1
select 'token', register_device_token('tok123');
select 'delete account', delete_my_account();
reset role; select 'D gone', count(*) from profiles where id = '00000000-0000-0000-0000-00000000000d';
select 'events', string_agg(type, ',' order by id) from game_events;
set role authenticated; set request.jwt.sub = '00000000-0000-0000-0000-00000000000a';
-- Ít nhất 1 hint (host đã rảnh vì game chính xong): game rỗng không hẹn giờ được, không xóa được hint cuối, xóa cả game thì được
with x as (insert into games (host_id, title) values (auth.uid(), 'Rỗng') returning id) insert into ctx select 'empty', id from x;
\set ON_ERROR_STOP 0
select 'schedule empty (expect game_has_no_hints)', schedule_game((select v from ctx where k='empty'), now() + interval '1 day');
\set ON_ERROR_STOP 1
\set ON_ERROR_STOP 0
select 'hint without title (expect hint_title_required)', create_hint((select v from ctx where k='empty'), 1, 'EMPTY-000', 21, 105, 0, '   ');
\set ON_ERROR_STOP 1
insert into ctx values ('e1', create_hint((select v from ctx where k='empty'), 1, 'EMPTY-111', 21, 105, 0, 'E1'));
insert into ctx values ('e2', create_hint((select v from ctx where k='empty'), 2, 'EMPTY-222', 21, 105, 0, 'E2'));
delete from hints where id = (select v from ctx where k='e2');
\set ON_ERROR_STOP 0
delete from hints where id = (select v from ctx where k='e1');
delete from hints where game_id = (select v from ctx where k='empty');
\set ON_ERROR_STOP 1
select 'hints left after blocked deletes (1)', count(*) from hints where game_id = (select v from ctx where k='empty');
delete from games where id = (select v from ctx where k='empty');
select 'empty game deleted with its hint (0)', count(*) from hints where game_id = (select v from ctx where k='empty');
-- Giải hiện vật (20261103001800): giải tổng là hiện vật thì tiền = 0 và không giới hạn thưởng mốc bằng tiền
with x as (insert into games (host_id, title, grand_prize, grand_prize_item) values (auth.uid(), 'Quà', 500000, '  Xe đạp  ') returning id) insert into ctx select 'gift', id from x;
select 'gift grand (0.00 Xe đạp)', grand_prize || ' ' || grand_prize_item from games where id = (select v from ctx where k='gift');
insert into ctx values ('g1', create_hint((select v from ctx where k='gift'), 1, 'GIFT-111', 21, 105, 2000000, 'G1'));
insert into ctx values ('g2', create_hint((select v from ctx where k='gift'), 2, 'GIFT-222', 21, 105, 300000, 'G2', null, 'Áo thun'));
select 'gift hints (2000000.00 - | 0.00 Áo thun)', string_agg(prize || ' ' || coalesce(prize_item, '-'), ' | ' order by hint_order) from hints where game_id = (select v from ctx where k='gift');
\set ON_ERROR_STOP 0
update games set grand_prize_item = null, grand_prize = 100000 where id = (select v from ctx where k='gift'); -- expect grand_prize_below_hint
\set ON_ERROR_STOP 1
\set ON_ERROR_STOP 0
update games set grand_prize_item = '' where id = (select v from ctx where k='gift'); -- '' = tiền 0 → expect grand_prize_below_hint
\set ON_ERROR_STOP 1
-- Chơi hết: B giải cả 2 hint → thưởng mốc tiền, thưởng mốc hiện vật, giải tổng hiện vật
select join_code as gjc from games where id = (select v from ctx where k='gift') \gset
set request.jwt.sub = '00000000-0000-0000-0000-00000000000b'; select 'B join gift', join_game(:'gjc') is not null;
select 'B current hint prize_item (-)', coalesce(prize_item, '-') from get_current_hint((select v from ctx where k='gift'));
set request.jwt.sub = '00000000-0000-0000-0000-00000000000a'; select 'start gift', start_game((select v from ctx where k='gift'));
set request.jwt.sub = '00000000-0000-0000-0000-00000000000b';
select 'B redeem g1', redeem_code((select v from ctx where k='g1'), 'GIFT-111')->>'ok';
select 'B attach g1', attach_photo((select id from submissions where status='reserved'), (select v from ctx where k='gift') || '/00000000-0000-0000-0000-00000000000b/g1.jpg');
set request.jwt.sub = '00000000-0000-0000-0000-00000000000a';
select 'approve g1', review_submission((select id from submissions where status='pending'), true);
set request.jwt.sub = '00000000-0000-0000-0000-00000000000b';
select 'B current hint g2 item (Áo thun)', prize_item from get_current_hint((select v from ctx where k='gift'));
select 'B redeem g2', redeem_code((select v from ctx where k='g2'), 'GIFT-222')->>'ok';
select 'B attach g2', attach_photo((select id from submissions where status='reserved'), (select v from ctx where k='gift') || '/00000000-0000-0000-0000-00000000000b/g2.jpg');
set request.jwt.sub = '00000000-0000-0000-0000-00000000000a';
select 'approve g2', review_submission((select id from submissions where status='pending'), true);
select 'gift rewards', string_agg(kind || ':' || amount || ' ' || coalesce(item, '-'), ', ' order by created_at, kind) from rewards where game_id = (select v from ctx where k='gift');
set request.jwt.sub = '00000000-0000-0000-0000-00000000000b';
select 'B stats items_won (2)', items_won || ' items, prizes ' || prizes from get_my_stats();
select 'B history gift', reward_amount || ' ' || coalesce(reward_items, '-') from get_my_history() where title = 'Quà';
-- Thống kê đếm game đã bắt đầu (20261103002000): game hủy giữa chừng vẫn tính, hủy trước khi chạy thì không
set request.jwt.sub = '00000000-0000-0000-0000-00000000000a';
select 'host hosted before (2)', games_hosted from get_my_stats();
with x as (insert into games (host_id, title) values (auth.uid(), 'Hủy giữa chừng') returning id) insert into ctx select 'mid', id from x;
select 'mid hint', create_hint((select v from ctx where k='mid'), 1, 'MIDWAY-1', 21, 105, 0, 'M1') is not null;
select 'start mid', start_game((select v from ctx where k='mid'));
select 'cancel mid', cancel_game((select v from ctx where k='mid'));
with x as (insert into games (host_id, title) values (auth.uid(), 'Hủy trước') returning id) insert into ctx select 'pre', id from x;
select 'cancel pre', cancel_game((select v from ctx where k='pre'));
select 'host hosted after (3: mid counts, pre not)', games_hosted from get_my_stats();
-- Game mở cho mọi người (20261103002100): vào không cần mã; game riêng tư không mở được
with x as (insert into games (host_id, title, is_public, area_lat, area_lng, join_open)
           values (auth.uid(), 'Mở', true, 21.03, 105.85, true) returning id) insert into ctx select 'open', id from x;
select 'open hint', create_hint((select v from ctx where k='open'), 1, 'OPEN-111', 21, 105, 0, 'O1') is not null;
select 'schedule open', schedule_game((select v from ctx where k='open'), now() + interval '1 day');
update games set is_public = false where id = (select v from ctx where k='open');
select 'private forces join_open false', join_open from games where id = (select v from ctx where k='open');
set request.jwt.sub = '00000000-0000-0000-0000-00000000000c';
\set ON_ERROR_STOP 0
select 'C join private (expect game_not_open)', join_open_game((select v from ctx where k='open'));
\set ON_ERROR_STOP 1
set request.jwt.sub = '00000000-0000-0000-0000-00000000000a';
update games set is_public = true, join_open = true where id = (select v from ctx where k='open');
set request.jwt.sub = '00000000-0000-0000-0000-00000000000c';
select 'C sees join_open on globe', join_open from get_globe_games() where id = (select v from ctx where k='open');
select 'C join open (no code)', join_open_game((select v from ctx where k='open')) = (select v from ctx where k='open');
select 'C joined again (idempotent)', join_open_game((select v from ctx where k='open')) is not null;
select 'C role', role from game_participants where game_id = (select v from ctx where k='open') and user_id = auth.uid();
set request.jwt.sub = '00000000-0000-0000-0000-00000000000a';
select 'cancel open', cancel_game((select v from ctx where k='open'));
set request.jwt.sub = '00000000-0000-0000-0000-00000000000b';
\set ON_ERROR_STOP 0
select 'B join cancelled open game (expect game_closed)', join_open_game((select v from ctx where k='open'));
\set ON_ERROR_STOP 1
-- Dọn: không để game này lẫn vào số liệu Globe của globe.sql
reset role; delete from games where id = (select v from ctx where k='open'); set role authenticated;
set request.jwt.sub = '00000000-0000-0000-0000-00000000000a';
set request.jwt.sub = '00000000-0000-0000-0000-00000000000a';
reset role;
