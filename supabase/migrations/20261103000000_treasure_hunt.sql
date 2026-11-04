-- =====================================================================
--  Treasure Hunt — Supabase schema
--  Chạy bằng: supabase db push  (hoặc dán vào SQL Editor)
--  Trước khi chạy: bật extension pg_cron (Dashboard → Database → Extensions)
--
--  Luật game đã chốt:
--   1. Mỗi hint có một tờ giấy proof đặt tại địa điểm, trên đó có MÃ dùng một lần.
--   2. Người chơi nhập đúng mã → mã bị GIỮ cho người đó (người khác nhập sẽ nhận
--      "code_in_use") → có upload_window_seconds (mặc định 60s) để tải ảnh tờ giấy.
--   3. Quản trò duyệt ảnh. Không xử lý trong auto_approve_minutes (mặc định 15')
--      → tự approve.
--   4. Approve → mã vô hiệu vĩnh viễn, thông báo người tìm ra, ghim vị trí do quản
--      trò đặt lên bản đồ, mở hint tiếp theo (hoặc kết thúc game + giải tổng).
--   5. Deny, hoặc quá 60s không tải ảnh → mã được mở lại cho người khác.
--   6. Nhập sai: không giới hạn tổng số lần, nhưng mỗi 3 lần sai liên tiếp
--      → khóa nhập mã 10 phút.
--   7. Một người được thắng nhiều mốc.
--   8. Hint gồm nhiều khối text / image / map, mỗi khối có thể hẹn giờ mở.
--   9. Ảnh proof tự xóa sau proof_retention_days (mặc định 7) ngày kể từ khi
--      game kết thúc (Edge Function purge-proofs).
--  Không dùng GPS của người chơi.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------
-- 1. Kiểu enum
-- ---------------------------------------------------------------------
create type public.game_status       as enum ('draft', 'scheduled', 'live', 'completed', 'cancelled');
create type public.participant_role  as enum ('host', 'cohost', 'player');
create type public.hint_item_type    as enum ('text', 'image', 'map');
create type public.submission_status as enum ('reserved', 'pending', 'approved', 'denied', 'expired');
create type public.reward_kind       as enum ('milestone', 'grand');
create type public.payout_status     as enum ('unpaid', 'paid');

-- ---------------------------------------------------------------------
-- 2. Bảng
-- ---------------------------------------------------------------------
create table public.profiles (
  id            uuid primary key references auth.users (id) on delete cascade,
  display_name  text not null default 'Player' check (char_length(display_name) between 1 and 40),
  avatar_path   text,
  created_at    timestamptz not null default now()
);

create table public.games (
  id                      uuid primary key default gen_random_uuid(),
  host_id                 uuid not null references public.profiles (id) on delete cascade,
  title                   text not null check (char_length(title) between 1 and 120),
  description             text,
  status                  public.game_status not null default 'draft',
  join_code               text not null unique
                            default upper(substr(md5(gen_random_uuid()::text), 1, 6)),
  grand_prize             numeric(12,2) not null default 0 check (grand_prize >= 0),
  currency                char(3) not null default 'EUR',
  current_hint_order      int,
  -- Cài đặt
  auto_approve_enabled    boolean not null default true,
  auto_approve_minutes    int not null default 15 check (auto_approve_minutes between 1 and 1440),
  upload_window_seconds   int not null default 60 check (upload_window_seconds between 15 and 600),
  code_fails_before_lock  int not null default 3  check (code_fails_before_lock between 1 and 20),
  code_lock_minutes       int not null default 10 check (code_lock_minutes between 1 and 120),
  public_winner_photos    boolean not null default true,
  proof_retention_days    int not null default 7  check (proof_retention_days between 1 and 365),
  -- Thời gian
  starts_at               timestamptz,
  started_at              timestamptz,
  ended_at                timestamptz,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);

create table public.game_participants (
  game_id    uuid not null references public.games (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  role       public.participant_role not null default 'player',
  joined_at  timestamptz not null default now(),
  primary key (game_id, user_id)
);
create index on public.game_participants (user_id);

create table public.hints (
  id                    uuid primary key default gen_random_uuid(),
  game_id               uuid not null references public.games (id) on delete cascade,
  hint_order            int  not null check (hint_order > 0),
  title                 text,
  prize                 numeric(12,2) not null default 0 check (prize >= 0),
  -- Vị trí do quản trò đặt: ghim lên bản đồ sau khi hint được giải
  -- (không bao giờ gửi cho người chơi trước đó)
  answer_lat            double precision not null check (answer_lat between -90 and 90),
  answer_lng            double precision not null check (answer_lng between -180 and 180),
  code_hash             text not null,              -- bcrypt, đặt qua create_hint / set_hint_code
  activated_at          timestamptz,
  revealed_at           timestamptz,                -- lúc approve = lúc mã vô hiệu
  winner_submission_id  uuid,
  created_at            timestamptz not null default now(),
  unique (game_id, hint_order)
);

create table public.hint_items (
  id                    uuid primary key default gen_random_uuid(),
  hint_id               uuid not null references public.hints (id) on delete cascade,
  item_order            int  not null default 1,
  type                  public.hint_item_type not null,
  text_content          text,
  image_path            text,                       -- storage: hint-media/{game_id}/...
  map_center_lat        double precision,           -- tâm vùng gợi ý (đã dịch lệch)
  map_center_lng        double precision,
  map_radius_m          int check (map_radius_m between 20 and 50000),
  reveal_after_minutes  int check (reveal_after_minutes >= 0),  -- null = mở ngay
  reveal_announced_at   timestamptz,
  created_at            timestamptz not null default now(),
  constraint hint_item_payload check (
       (type = 'text'  and text_content is not null)
    or (type = 'image' and image_path   is not null)
    or (type = 'map'   and map_radius_m is not null)
  )
);
create index on public.hint_items (hint_id, item_order);

create table public.submissions (
  id               uuid primary key default gen_random_uuid(),
  game_id          uuid not null references public.games (id) on delete cascade,
  hint_id          uuid not null references public.hints (id) on delete cascade,
  user_id          uuid not null references public.profiles (id) on delete cascade,
  status           public.submission_status not null default 'reserved',
  reserved_at      timestamptz not null default now(),   -- lúc nhập đúng mã
  upload_deadline  timestamptz not null,
  photo_path       text,                                 -- storage: proofs/{game_id}/{user_id}/...
  uploaded_at      timestamptz,
  photo_purged_at  timestamptz,                          -- ảnh đã xóa khỏi Storage
  auto_approve_at  timestamptz,
  reviewed_by      uuid references public.profiles (id),
  reviewed_at      timestamptz,
  auto_approved    boolean not null default false,
  deny_reason      text
);
create index on public.submissions (game_id, user_id);
create index on public.submissions (auto_approve_at) where status = 'pending';
create index on public.submissions (upload_deadline) where status = 'reserved';
-- Mã dùng một lần: mỗi hint chỉ có tối đa 1 proof đang mở
create unique index submissions_one_open_per_hint
  on public.submissions (hint_id) where status in ('reserved', 'pending');
-- và tối đa 1 proof được approve
create unique index submissions_one_winner_per_hint
  on public.submissions (hint_id) where status = 'approved';

alter table public.hints
  add constraint hints_winner_fk foreign key (winner_submission_id)
  references public.submissions (id) on delete set null;

create table public.code_attempts (
  id          bigint generated always as identity primary key,
  hint_id     uuid not null references public.hints (id) on delete cascade,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  success     boolean not null,
  created_at  timestamptz not null default now()
);
create index on public.code_attempts (hint_id, user_id, created_at);

create table public.rewards (
  id             uuid primary key default gen_random_uuid(),
  game_id        uuid not null references public.games (id) on delete cascade,
  hint_id        uuid not null references public.hints (id) on delete cascade,
  kind           public.reward_kind not null,
  winner_id      uuid not null references public.profiles (id) on delete cascade,
  amount         numeric(12,2) not null default 0,
  currency       char(3) not null,
  payout_status  public.payout_status not null default 'unpaid',
  created_at     timestamptz not null default now(),
  unique (hint_id, kind)
);
create index on public.rewards (game_id, winner_id);

-- Dòng thời gian + kênh realtime (app subscribe bảng này)
create table public.game_events (
  id          bigint generated always as identity primary key,
  game_id     uuid not null references public.games (id) on delete cascade,
  type        text not null,
  payload     jsonb not null default '{}',
  created_at  timestamptz not null default now()
);
create index on public.game_events (game_id, id);

-- ---------------------------------------------------------------------
-- 3. Hàm tiện ích
-- ---------------------------------------------------------------------
-- Bỏ khoảng trắng và dấu câu, không phân biệt hoa thường: "Hoa-Sen 27" = "HOASEN27"
create or replace function public.normalize_code(p text)
returns text language sql immutable as $$
  select upper(regexp_replace(coalesce(p, ''), '[^[:alnum:]]', '', 'g'));
$$;

-- Tâm vùng gợi ý dịch lệch ngẫu nhiên, vị trí thật vẫn nằm trong vòng tròn
create or replace function public.random_map_center(p_lat float8, p_lng float8, p_radius_m int,
                                                    out lat float8, out lng float8)
language plpgsql volatile as $$
declare
  d     float8 := p_radius_m * 0.8 * sqrt(random());
  theta float8 := 2 * pi() * random();
begin
  lat := p_lat + (d * cos(theta)) / 111320.0;
  lng := p_lng + (d * sin(theta)) / (111320.0 * cos(radians(p_lat)));
end $$;

create or replace function public.is_participant(p_game_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from game_participants
                 where game_id = p_game_id and user_id = auth.uid());
$$;

create or replace function public.is_game_staff(p_game_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from game_participants
                 where game_id = p_game_id and user_id = auth.uid()
                   and role in ('host', 'cohost'));
$$;

create or replace function public.game_is_editable(p_game_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from games where id = p_game_id and status in ('draft', 'scheduled'));
$$;

create or replace function public._emit(p_game_id uuid, p_type text, p_payload jsonb default '{}')
returns void language sql security definer set search_path = public as $$
  insert into game_events (game_id, type, payload) values (p_game_id, p_type, p_payload);
$$;

-- ---------------------------------------------------------------------
-- 4. Trigger
-- ---------------------------------------------------------------------
-- Tạo profile khi đăng ký
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, display_name)
  values (new.id, coalesce(nullif(new.raw_user_meta_data ->> 'display_name', ''), 'Player'))
  on conflict (id) do nothing;
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Người tạo game tự động là host
create or replace function public.add_host_participant()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into game_participants (game_id, user_id, role) values (new.id, new.host_id, 'host');
  return new;
end $$;

create trigger games_add_host
  after insert on public.games
  for each row execute function public.add_host_participant();

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end $$;

create trigger games_touch before update on public.games
  for each row execute function public.touch_updated_at();

-- Khối map chưa có tâm → tự sinh tâm dịch lệch từ vị trí của hint
create or replace function public.fill_map_center()
returns trigger language plpgsql security definer set search_path = public as $$
declare h record; c record;
begin
  if new.type = 'map' and (new.map_center_lat is null or new.map_center_lng is null) then
    select answer_lat, answer_lng into h from hints where id = new.hint_id;
    select * into c from random_map_center(h.answer_lat, h.answer_lng, new.map_radius_m);
    new.map_center_lat := c.lat;
    new.map_center_lng := c.lng;
  end if;
  return new;
end $$;

create trigger hint_items_fill_map before insert or update of map_radius_m on public.hint_items
  for each row execute function public.fill_map_center();

-- ---------------------------------------------------------------------
-- 5. Hàm cho quản trò
-- ---------------------------------------------------------------------
create or replace function public.create_hint(
  p_game_id uuid, p_hint_order int, p_code text,
  p_answer_lat float8, p_answer_lng float8,
  p_prize numeric default 0, p_title text default null)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare v_id uuid;
begin
  if not is_game_staff(p_game_id) then raise exception 'not_game_staff'; end if;
  if not game_is_editable(p_game_id) then raise exception 'game_not_editable'; end if;
  if char_length(normalize_code(p_code)) < 6 then raise exception 'code_too_short'; end if;

  insert into hints (game_id, hint_order, title, prize, answer_lat, answer_lng, code_hash)
  values (p_game_id, p_hint_order, p_title, p_prize, p_answer_lat, p_answer_lng,
          crypt(normalize_code(p_code), gen_salt('bf')))
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.set_hint_code(p_hint_id uuid, p_code text)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare v_game uuid;
begin
  select game_id into v_game from hints where id = p_hint_id;
  if not is_game_staff(v_game) then raise exception 'not_game_staff'; end if;
  if not game_is_editable(v_game) then raise exception 'game_not_editable'; end if;
  if char_length(normalize_code(p_code)) < 6 then raise exception 'code_too_short'; end if;
  update hints set code_hash = crypt(normalize_code(p_code), gen_salt('bf')) where id = p_hint_id;
end $$;

-- Gợi ý mã ngẫu nhiên 8 ký tự dễ đọc (bỏ 0/O, 1/I/L) để in lên tờ giấy proof
create or replace function public.generate_hint_code()
returns text language sql volatile as $$
  select string_agg(substr('ABCDEFGHJKMNPQRSTUVWXYZ23456789', 1 + floor(random() * 31)::int, 1), '')
    from generate_series(1, 8);
$$;

create or replace function public.schedule_game(p_game_id uuid, p_starts_at timestamptz)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_game_staff(p_game_id) then raise exception 'not_game_staff'; end if;
  update games set status = 'scheduled', starts_at = p_starts_at
   where id = p_game_id and status in ('draft', 'scheduled');
  if not found then raise exception 'game_not_editable'; end if;
end $$;

create or replace function public.cancel_game(p_game_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_game_staff(p_game_id) then raise exception 'not_game_staff'; end if;
  update games set status = 'cancelled', ended_at = now()
   where id = p_game_id and status in ('draft', 'scheduled', 'live');
  if not found then raise exception 'game_not_cancellable'; end if;
  update submissions set status = 'expired'
   where game_id = p_game_id and status in ('reserved', 'pending');
  perform _emit(p_game_id, 'game_cancelled');
end $$;

create or replace function public._activate_hint(p_game_id uuid, p_hint_order int)
returns void language plpgsql security definer set search_path = public as $$
begin
  update hints set activated_at = now() where game_id = p_game_id and hint_order = p_hint_order;
  update games set current_hint_order = p_hint_order where id = p_game_id;
  perform _emit(p_game_id, 'hint_activated', jsonb_build_object('hint_order', p_hint_order));
end $$;

create or replace function public._start_game(p_game_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_first int;
begin
  perform 1 from games where id = p_game_id and status in ('draft', 'scheduled') for update;
  if not found then raise exception 'game_not_startable'; end if;
  select min(hint_order) into v_first from hints where game_id = p_game_id;
  if v_first is null then raise exception 'game_has_no_hints'; end if;
  update games set status = 'live', started_at = now() where id = p_game_id;
  perform _emit(p_game_id, 'game_started');
  perform _activate_hint(p_game_id, v_first);
end $$;

create or replace function public.start_game(p_game_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_game_staff(p_game_id) then raise exception 'not_game_staff'; end if;
  perform _start_game(p_game_id);
end $$;

-- ---------------------------------------------------------------------
-- 6. Người chơi
-- ---------------------------------------------------------------------
create or replace function public.join_game(p_join_code text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_game uuid;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  select id into v_game from games
   where join_code = upper(trim(p_join_code)) and status in ('draft', 'scheduled', 'live');
  if v_game is null then raise exception 'game_not_found'; end if;
  insert into game_participants (game_id, user_id, role)
  values (v_game, auth.uid(), 'player') on conflict do nothing;
  perform _emit(v_game, 'player_joined', jsonb_build_object('user_id', auth.uid()));
  return v_game;
end $$;

-- Bước 1: nhập mã. Đúng → giữ mã cho người này, chờ ảnh.
-- Trả về jsonb (không raise) để lượt nhập sai vẫn được ghi lại:
--   {ok:true, submission_id, upload_deadline, upload_path_prefix}
--   {ok:false, error:'wrong_code', attempts_before_lock, locked_until?}
--   {ok:false, error:'code_entry_locked', locked_until}
--   {ok:false, error:'code_in_use'}        -- người khác đang giữ mã, chờ duyệt
create or replace function public.redeem_code(p_hint_id uuid, p_code text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  h        hints%rowtype;
  g        games%rowtype;
  v_fails  int;
  v_last   timestamptz;
  v_until  timestamptz;
  v_sub    submissions%rowtype;
begin
  -- Khóa hint: hai người nhập đúng cùng lúc → chỉ một người giữ được mã
  select * into h from hints where id = p_hint_id for update;
  if not found then raise exception 'hint_not_found'; end if;
  select * into g from games where id = h.game_id;

  if not exists (select 1 from game_participants
                 where game_id = g.id and user_id = auth.uid() and role = 'player') then
    raise exception 'not_a_player';
  end if;
  if g.status <> 'live' or g.current_hint_order is distinct from h.hint_order
     or h.revealed_at is not null then
    raise exception 'hint_not_active';
  end if;

  -- Khóa nhập mã: mỗi 3 lần sai liên tiếp (tính từ lần đúng gần nhất) → 10 phút
  select count(*), max(created_at) into v_fails, v_last from code_attempts
   where hint_id = h.id and user_id = auth.uid() and not success
     and created_at > coalesce((select max(created_at) from code_attempts
                                 where hint_id = h.id and user_id = auth.uid() and success),
                               '-infinity');
  if v_fails > 0 and v_fails % g.code_fails_before_lock = 0 then
    v_until := v_last + make_interval(mins => g.code_lock_minutes);
    if v_until > now() then
      return jsonb_build_object('ok', false, 'error', 'code_entry_locked', 'locked_until', v_until);
    end if;
  end if;

  if crypt(normalize_code(p_code), h.code_hash) <> h.code_hash then
    insert into code_attempts (hint_id, user_id, success) values (h.id, auth.uid(), false);
    v_fails := v_fails + 1;
    if v_fails % g.code_fails_before_lock = 0 then
      return jsonb_build_object('ok', false, 'error', 'wrong_code', 'attempts_before_lock', 0,
                                'locked_until', now() + make_interval(mins => g.code_lock_minutes));
    end if;
    return jsonb_build_object('ok', false, 'error', 'wrong_code',
                              'attempts_before_lock', g.code_fails_before_lock - v_fails % g.code_fails_before_lock);
  end if;
  insert into code_attempts (hint_id, user_id, success) values (h.id, auth.uid(), true);

  -- Mã đúng nhưng đang được người khác giữ (chờ ảnh hoặc chờ duyệt)
  if exists (select 1 from submissions where hint_id = h.id and status in ('reserved', 'pending')) then
    return jsonb_build_object('ok', false, 'error', 'code_in_use');
  end if;

  insert into submissions (game_id, hint_id, user_id, upload_deadline)
  values (g.id, h.id, auth.uid(), now() + make_interval(secs => g.upload_window_seconds))
  returning * into v_sub;

  perform _emit(g.id, 'code_claimed', jsonb_build_object('hint_order', h.hint_order,
                                                        'submission_id', v_sub.id));
  return jsonb_build_object('ok', true, 'submission_id', v_sub.id,
                            'upload_deadline', v_sub.upload_deadline,
                            'upload_path_prefix', g.id || '/' || auth.uid() || '/');
end $$;

-- Mở lại mã cho người khác (sau deny / hết hạn)
create or replace function public._release_code(p_game_id uuid, p_hint_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform _emit(p_game_id, 'code_released', jsonb_build_object(
    'hint_order', (select hint_order from hints where id = p_hint_id), 'reason', p_reason));
end $$;

-- Bước 2: ảnh tờ giấy đã tải lên Storage → chờ quản trò duyệt, bắt đầu đếm 15 phút
create or replace function public.attach_photo(p_submission_id uuid, p_photo_path text)
returns void language plpgsql security definer set search_path = public as $$
declare s submissions%rowtype; g games%rowtype;
begin
  select * into s from submissions where id = p_submission_id and user_id = auth.uid() for update;
  if not found then raise exception 'submission_not_found'; end if;
  if s.status <> 'reserved' then raise exception 'submission_not_reserved'; end if;
  if p_photo_path not like s.game_id || '/' || s.user_id || '/%' then
    raise exception 'invalid_photo_path';
  end if;
  if now() > s.upload_deadline then
    update submissions set status = 'expired' where id = s.id;
    perform _release_code(s.game_id, s.hint_id, 'upload_expired');
    return;  -- trạng thái 'expired' cho app biết đã quá hạn
  end if;

  select * into g from games where id = s.game_id;
  update submissions
     set status = 'pending', photo_path = p_photo_path, uploaded_at = now(),
         auto_approve_at = case when g.auto_approve_enabled
                                then now() + make_interval(mins => g.auto_approve_minutes) end
   where id = s.id
  returning * into s;
  perform _emit(s.game_id, 'proof_awaiting_review',
                jsonb_build_object('submission_id', s.id, 'auto_approve_at', s.auto_approve_at));
end $$;

-- ---------------------------------------------------------------------
-- 7. Duyệt proof
-- ---------------------------------------------------------------------
create or replace function public._approve_submission(p_submission_id uuid, p_auto boolean, p_reviewer uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  s      submissions%rowtype;
  g      games%rowtype;
  h      hints%rowtype;
  v_next int;
begin
  select game_id into g.id from submissions where id = p_submission_id;
  if g.id is null then raise exception 'submission_not_found'; end if;

  -- Khóa game: mọi thao tác duyệt của cùng game chạy tuần tự
  select * into g from games where id = g.id for update;
  select * into s from submissions where id = p_submission_id for update;
  select * into h from hints where id = s.hint_id;

  if s.status <> 'pending' then raise exception 'submission_not_pending'; end if;
  if g.status <> 'live' or g.current_hint_order is distinct from h.hint_order
     or h.revealed_at is not null then
    raise exception 'hint_not_active';
  end if;

  update submissions
     set status = 'approved', reviewed_at = now(), reviewed_by = p_reviewer, auto_approved = p_auto
   where id = s.id;

  -- Mã vô hiệu vĩnh viễn: hint đã giải thì redeem_code() từ chối mọi lượt nhập
  update hints set revealed_at = now(), winner_submission_id = s.id where id = h.id;

  insert into rewards (game_id, hint_id, kind, winner_id, amount, currency)
  values (g.id, h.id, 'milestone', s.user_id, h.prize, g.currency);

  perform _emit(g.id, 'hint_solved', jsonb_build_object(
    'hint_order', h.hint_order, 'winner_id', s.user_id,
    'winner_name', (select display_name from profiles where id = s.user_id),
    'auto_approved', p_auto, 'lat', h.answer_lat, 'lng', h.answer_lng));

  select min(hint_order) into v_next from hints where game_id = g.id and hint_order > h.hint_order;
  if v_next is not null then
    perform _activate_hint(g.id, v_next);
  else
    insert into rewards (game_id, hint_id, kind, winner_id, amount, currency)
    values (g.id, h.id, 'grand', s.user_id, g.grand_prize, g.currency);
    update games set status = 'completed', ended_at = now(), current_hint_order = null where id = g.id;
    perform _emit(g.id, 'game_completed', jsonb_build_object('grand_winner_id', s.user_id));
  end if;
end $$;

create or replace function public.review_submission(p_submission_id uuid, p_approve boolean,
                                                    p_reason text default null)
returns void language plpgsql security definer set search_path = public as $$
declare s submissions%rowtype;
begin
  select * into s from submissions where id = p_submission_id;
  if not found then raise exception 'submission_not_found'; end if;
  if not is_game_staff(s.game_id) then raise exception 'not_game_staff'; end if;

  if p_approve then
    perform _approve_submission(p_submission_id, false, auth.uid());
  else
    perform 1 from games where id = s.game_id for update;
    update submissions
       set status = 'denied', deny_reason = p_reason, reviewed_by = auth.uid(), reviewed_at = now()
     where id = p_submission_id and status = 'pending';
    if not found then raise exception 'submission_not_pending'; end if;
    perform _emit(s.game_id, 'proof_denied',
                  jsonb_build_object('submission_id', s.id, 'user_id', s.user_id, 'reason', p_reason));
    perform _release_code(s.game_id, s.hint_id, 'denied');
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 8. Bộ hẹn giờ — pg_cron gọi mỗi phút
-- ---------------------------------------------------------------------
create or replace function public.process_timers()
returns void language plpgsql security definer set search_path = public as $$
declare r record;
begin
  -- a) Bắt đầu game đã lên lịch
  for r in select id from games where status = 'scheduled' and starts_at <= now() loop
    begin perform _start_game(r.id); exception when others then null; end;
  end loop;

  -- b) Giữ mã quá hạn chưa tải ảnh → mở lại mã
  for r in
    update submissions set status = 'expired'
     where status = 'reserved' and upload_deadline < now()
    returning game_id, hint_id
  loop
    perform _release_code(r.game_id, r.hint_id, 'upload_expired');
  end loop;

  -- c) Tự approve sau 15 phút
  for r in
    select s.id from submissions s join games g on g.id = s.game_id
     where s.status = 'pending' and s.auto_approve_at <= now()
       and g.auto_approve_enabled and g.status = 'live'
  loop
    begin perform _approve_submission(r.id, true, null); exception when others then null; end;
  end loop;

  -- d) Thông báo các khối hint vừa mở theo giờ
  for r in
    update hint_items i set reveal_announced_at = now()
      from hints h, games g
     where h.id = i.hint_id and g.id = h.game_id
       and g.status = 'live' and h.activated_at is not null and h.revealed_at is null
       and i.reveal_after_minutes is not null and i.reveal_announced_at is null
       and h.activated_at + make_interval(mins => i.reveal_after_minutes) <= now()
    returning h.game_id, h.hint_order, i.id as item_id, i.type
  loop
    perform _emit(r.game_id, 'hint_item_revealed',
                  jsonb_build_object('hint_order', r.hint_order, 'item_id', r.item_id, 'type', r.type));
  end loop;
end $$;

-- e) Dọn ảnh proof: Edge Function "purge-proofs" (chạy hằng ngày bằng service_role) gọi
--    claim_proofs_to_purge() → xóa các file trong bucket proofs qua Storage API
--    → gọi mark_proofs_purged(paths). Không xóa trực tiếp bảng storage.objects.
create or replace function public.claim_proofs_to_purge(p_limit int default 500)
returns table (submission_id uuid, photo_path text)
language sql stable security definer set search_path = public as $$
  select s.id, s.photo_path
    from submissions s join games g on g.id = s.game_id
   where s.photo_path is not null and s.photo_purged_at is null
     and g.status in ('completed', 'cancelled')
     and g.ended_at < now() - make_interval(days => g.proof_retention_days)
   order by g.ended_at
   limit p_limit;
$$;

create or replace function public.mark_proofs_purged(p_paths text[])
returns int language plpgsql security definer set search_path = public as $$
declare v_count int;
begin
  update submissions set photo_purged_at = now()
   where photo_path = any (p_paths) and photo_purged_at is null;
  get diagnostics v_count = row_count;
  return v_count;
end $$;

-- ---------------------------------------------------------------------
-- 9. Đọc dữ liệu cho người chơi (chỉ trả nội dung đã được phép xem)
-- ---------------------------------------------------------------------
-- Nội dung hint đã mở (hint hiện tại + các hint đã giải)
create or replace function public.get_hint_items(p_game_id uuid)
returns table (hint_id uuid, hint_order int, hint_title text, prize numeric,
               hint_activated_at timestamptz, hint_solved boolean,
               item_id uuid, item_order int, type public.hint_item_type,
               text_content text, image_path text,
               map_center_lat float8, map_center_lng float8, map_radius_m int)
language sql stable security definer set search_path = public as $$
  select h.id, h.hint_order, h.title, h.prize, h.activated_at, h.revealed_at is not null,
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

-- Lúc mở khối tiếp theo của hint hiện tại (để hiện đồng hồ đếm ngược)
create or replace function public.get_next_reveal_at(p_game_id uuid)
returns timestamptz language sql stable security definer set search_path = public as $$
  select min(h.activated_at + make_interval(mins => i.reveal_after_minutes))
    from games g
    join hints h on h.game_id = g.id and h.hint_order = g.current_hint_order
    join hint_items i on i.hint_id = h.id
   where g.id = p_game_id and is_participant(p_game_id)
     and i.reveal_after_minutes is not null
     and h.activated_at + make_interval(mins => i.reveal_after_minutes) > now();
$$;

-- Trạng thái mã của hint hiện tại: 'open' | 'in_review' (có người đang giữ) | 'solved'
create or replace function public.get_current_code_status(p_game_id uuid)
returns text language sql stable security definer set search_path = public as $$
  select case
           when h.revealed_at is not null then 'solved'
           when exists (select 1 from submissions s where s.hint_id = h.id
                          and s.status in ('reserved', 'pending')) then 'in_review'
           else 'open' end
    from games g join hints h on h.game_id = g.id and h.hint_order = g.current_hint_order
   where g.id = p_game_id and is_participant(p_game_id);
$$;

-- Kết quả các hint đã giải + ghim trên bản đồ (vị trí do quản trò đặt)
create or replace function public.get_revealed_answers(p_game_id uuid)
returns table (hint_order int, hint_title text, answer_lat float8, answer_lng float8,
               winner_id uuid, winner_name text, solved_at timestamptz,
               seconds_to_solve int, winner_photo_path text)
language sql stable security definer set search_path = public as $$
  select h.hint_order, h.title, h.answer_lat, h.answer_lng,
         s.user_id, p.display_name, h.revealed_at,
         extract(epoch from (s.reserved_at - h.activated_at))::int,
         case when s.photo_purged_at is null
               and (g.public_winner_photos or is_game_staff(p_game_id)) then s.photo_path end
    from hints h
    join games g       on g.id = h.game_id
    join submissions s on s.id = h.winner_submission_id
    join profiles p    on p.id = s.user_id
   where h.game_id = p_game_id and h.revealed_at is not null and is_participant(p_game_id)
   order by h.hint_order;
$$;

-- Bảng xếp hạng: số mốc thắng → tổng thời gian tìm ra ít nhất
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
  select rank() over (order by coalesce(w.won, 0) desc, w.secs asc nulls last),
         gp.user_id, p.display_name, coalesce(w.won, 0), coalesce(m.total, 0), coalesce(w.secs, 0)
    from game_participants gp
    join profiles p     on p.id = gp.user_id
    left join wins w    on w.user_id = gp.user_id
    left join money m   on m.winner_id = gp.user_id
   where gp.game_id = p_game_id and gp.role = 'player' and is_participant(p_game_id)
   order by 1, p.display_name;
$$;

-- ---------------------------------------------------------------------
-- 10. Row Level Security + quyền
-- ---------------------------------------------------------------------
alter table public.profiles          enable row level security;
alter table public.games             enable row level security;
alter table public.game_participants enable row level security;
alter table public.hints             enable row level security;
alter table public.hint_items        enable row level security;
alter table public.submissions       enable row level security;
alter table public.code_attempts     enable row level security;
alter table public.rewards           enable row level security;
alter table public.game_events       enable row level security;

revoke all on all tables in schema public from anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;

-- profiles
grant select on public.profiles to authenticated;
grant update (display_name, avatar_path) on public.profiles to authenticated;
create policy profiles_read   on public.profiles for select to authenticated using (true);
create policy profiles_update on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- games: status / current_hint_order / thời gian chỉ đổi qua hàm
grant select, delete on public.games to authenticated;
grant insert (title, description, grand_prize, currency, auto_approve_enabled, auto_approve_minutes,
              upload_window_seconds, code_fails_before_lock, code_lock_minutes,
              public_winner_photos, proof_retention_days, host_id)
  on public.games to authenticated;
grant update (title, description, grand_prize, currency, auto_approve_enabled, auto_approve_minutes,
              upload_window_seconds, code_fails_before_lock, code_lock_minutes,
              public_winner_photos, proof_retention_days)
  on public.games to authenticated;
create policy games_read   on public.games for select to authenticated
  using (host_id = auth.uid() or public.is_participant(id));
create policy games_insert on public.games for insert to authenticated
  with check (host_id = auth.uid());
create policy games_update on public.games for update to authenticated
  using (public.is_game_staff(id)) with check (public.is_game_staff(id));
create policy games_delete on public.games for delete to authenticated
  using (host_id = auth.uid() and status = 'draft');

-- game_participants: tham gia qua join_game(); người chơi tự rời, staff mời ra
grant select, delete on public.game_participants to authenticated;
create policy participants_read on public.game_participants for select to authenticated
  using (public.is_participant(game_id));
create policy participants_delete on public.game_participants for delete to authenticated
  using (role <> 'host' and (user_id = auth.uid() or public.is_game_staff(game_id)));

-- hints: người chơi KHÔNG đọc trực tiếp (vị trí + mã hash) — dùng get_hint_items()
grant select, delete on public.hints to authenticated;
grant update (title, prize, answer_lat, answer_lng, hint_order) on public.hints to authenticated;
create policy hints_staff_read on public.hints for select to authenticated
  using (public.is_game_staff(game_id));
create policy hints_staff_update on public.hints for update to authenticated
  using (public.is_game_staff(game_id) and public.game_is_editable(game_id))
  with check (public.is_game_staff(game_id) and public.game_is_editable(game_id));
create policy hints_staff_delete on public.hints for delete to authenticated
  using (public.is_game_staff(game_id) and public.game_is_editable(game_id));

-- hint_items: staff soạn khi game còn draft/scheduled
grant select, insert, update, delete on public.hint_items to authenticated;
create policy hint_items_staff_read on public.hint_items for select to authenticated
  using (exists (select 1 from public.hints h where h.id = hint_id and public.is_game_staff(h.game_id)));
create policy hint_items_staff_write on public.hint_items for all to authenticated
  using (exists (select 1 from public.hints h where h.id = hint_id
                 and public.is_game_staff(h.game_id) and public.game_is_editable(h.game_id)))
  with check (exists (select 1 from public.hints h where h.id = hint_id
                 and public.is_game_staff(h.game_id) and public.game_is_editable(h.game_id)));

-- submissions: chỉ đọc (của mình, hoặc staff xem tất cả); ghi qua hàm
grant select on public.submissions to authenticated;
create policy submissions_read on public.submissions for select to authenticated
  using (user_id = auth.uid() or public.is_game_staff(game_id));

-- rewards: mọi người trong game xem; staff đánh dấu đã trả
grant select on public.rewards to authenticated;
grant update (payout_status) on public.rewards to authenticated;
create policy rewards_read on public.rewards for select to authenticated
  using (public.is_participant(game_id));
create policy rewards_staff_update on public.rewards for update to authenticated
  using (public.is_game_staff(game_id)) with check (public.is_game_staff(game_id));

-- game_events: realtime cho mọi người trong game
grant select on public.game_events to authenticated;
create policy events_read on public.game_events for select to authenticated
  using (public.is_participant(game_id));

-- code_attempts: không ai đọc trực tiếp

-- Hàm public (RPC) cho app
grant execute on function
  public.is_participant(uuid), public.is_game_staff(uuid), public.game_is_editable(uuid),
  public.create_hint(uuid, int, text, float8, float8, numeric, text),
  public.set_hint_code(uuid, text), public.generate_hint_code(),
  public.schedule_game(uuid, timestamptz), public.start_game(uuid), public.cancel_game(uuid),
  public.join_game(text), public.redeem_code(uuid, text), public.attach_photo(uuid, text),
  public.review_submission(uuid, boolean, text),
  public.get_hint_items(uuid), public.get_next_reveal_at(uuid), public.get_current_code_status(uuid),
  public.get_revealed_answers(uuid), public.get_leaderboard(uuid), public.normalize_code(text)
to authenticated;
-- Các hàm _* , process_timers() và hàm dọn ảnh không cấp cho client.

-- ---------------------------------------------------------------------
-- 11. Storage, Realtime, Cron (chỉ chạy khi các thành phần Supabase có mặt)
-- ---------------------------------------------------------------------
-- Ảnh hint chỉ xem được khi khối ảnh đó đã mở
create or replace function public.can_view_hint_image(p_path text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from hint_items i join hints h on h.id = i.hint_id
     where i.image_path = p_path
       and (is_game_staff(h.game_id)
            or (is_participant(h.game_id) and h.activated_at is not null
                and (h.revealed_at is not null or i.reveal_after_minutes is null
                     or h.activated_at + make_interval(mins => i.reveal_after_minutes) <= now()))));
$$;

-- Ảnh proof: chủ ảnh, staff, hoặc mọi người nếu là ảnh thắng và game bật public_winner_photos
create or replace function public.can_view_proof(p_path text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from submissions s join games g on g.id = s.game_id
     where s.photo_path = p_path
       and (s.user_id = auth.uid() or is_game_staff(s.game_id)
            or (s.status = 'approved' and g.public_winner_photos and is_participant(s.game_id))));
$$;
grant execute on function public.can_view_hint_image(text), public.can_view_proof(text) to authenticated;

do $$
begin
  -- Hàm dọn ảnh chỉ dành cho service_role (Edge Function)
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function public.claim_proofs_to_purge(int), public.mark_proofs_purged(text[])
      to service_role;
  end if;

  -- Storage
  if exists (select 1 from information_schema.tables
              where table_schema = 'storage' and table_name = 'buckets') then
    insert into storage.buckets (id, name, public) values
      ('proofs', 'proofs', false), ('hint-media', 'hint-media', false)
    on conflict (id) do nothing;

    -- proofs/{game_id}/{user_id}/{file}
    create policy proofs_upload on storage.objects for insert to authenticated
      with check (bucket_id = 'proofs'
        and (storage.foldername(name))[2] = auth.uid()::text
        and public.is_participant(((storage.foldername(name))[1])::uuid));
    create policy proofs_read on storage.objects for select to authenticated
      using (bucket_id = 'proofs' and (
             (storage.foldername(name))[2] = auth.uid()::text or public.can_view_proof(name)));

    -- hint-media/{game_id}/{file}
    create policy hint_media_write on storage.objects for insert to authenticated
      with check (bucket_id = 'hint-media'
        and public.is_game_staff(((storage.foldername(name))[1])::uuid));
    create policy hint_media_read on storage.objects for select to authenticated
      using (bucket_id = 'hint-media' and public.can_view_hint_image(name));
  end if;

  -- Realtime
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.game_events;
  end if;

  -- Cron: chạy bộ hẹn giờ mỗi phút
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('treasure-hunt-timers', '* * * * *', 'select public.process_timers()');
  end if;
end $$;
