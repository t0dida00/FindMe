-- =====================================================================
--  Find Me! — hàng đợi push bền vững cho server Go (chạy sau 20261104000100_game_events_notify.sql)
--
--  Mỗi game_event có thể sinh push được ghi một dòng vào push_outbox (trigger). Server Go (giai đoạn 4)
--  nhận việc bằng `for update skip locked`, gửi APNs rồi đặt sent_at; lỗi thì thử lại sau (attempts,
--  next_attempt_at). Chỉ service role đọc/ghi được (RLS bật, không có policy, không grant).
--  Trong lúc Edge Function `push` (webhook) còn chạy, bảng chỉ đầy dần: worker Go bỏ qua sự kiện cũ
--  hơn vài phút khi được bật, nên không gửi lại push cũ.
-- =====================================================================

create table if not exists public.push_outbox (
  event_id        bigint primary key references public.game_events (id) on delete cascade,
  created_at      timestamptz not null default now(),
  attempts        int not null default 0,
  next_attempt_at timestamptz not null default now(),
  sent_at         timestamptz,
  skipped         boolean not null default false,
  last_error      text
);
create index if not exists push_outbox_pending on public.push_outbox (next_attempt_at)
  where sent_at is null and not skipped;
alter table public.push_outbox enable row level security;
revoke all on public.push_outbox from public, anon, authenticated;

create or replace function public._enqueue_push()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.type in ('game_started', 'hint_activated', 'hint_item_revealed', 'hint_solved', 'proof_denied',
                  'proof_awaiting_review', 'proof_review_reminder', 'game_completed', 'game_cancelled') then
    insert into push_outbox (event_id) values (new.id) on conflict do nothing;
  end if;
  return null;
end $$;

drop trigger if exists game_events_push on public.game_events;
create trigger game_events_push after insert on public.game_events
  for each row execute function public._enqueue_push();
