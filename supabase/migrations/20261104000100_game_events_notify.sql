-- =====================================================================
--  Find Me! — báo sự kiện game qua LISTEN/NOTIFY cho server Go (chạy sau 20261103002200_open_join_closed.sql)
--
--  Mỗi dòng mới trong game_events gửi pg_notify('game_events', '{"id":…,"game_id":"…"}').
--  Server Go (FindMe-Go, giai đoạn 3) LISTEN kênh này và đẩy sự kiện xuống app qua SSE, thay cho
--  Supabase Realtime. Payload chỉ có id + game_id (giới hạn 8000 byte của NOTIFY); server tự đọc dòng.
--  Không ảnh hưởng Supabase Realtime: cả hai cùng chạy được trong lúc chuyển đổi.
-- =====================================================================

create or replace function public._notify_game_event()
returns trigger language plpgsql set search_path = public as $$
begin
  perform pg_notify('game_events', json_build_object('id', new.id, 'game_id', new.game_id)::text);
  return null;
end $$;

drop trigger if exists game_events_notify on public.game_events;
create trigger game_events_notify after insert on public.game_events
  for each row execute function public._notify_game_event();
