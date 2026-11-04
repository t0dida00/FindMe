-- =====================================================================
--  Find Me! — bổ sung cho MVP (chạy sau 20261103000000_treasure_hunt.sql)
--
--  1. Tiền tệ mặc định VND (thị trường ra mắt: Việt Nam).
--  2. Nhắc quản trò ở phút 5 và 10 sau khi ảnh proof lên (F-24).
--  3. Bảng device_tokens để gửi push APNs (F-24).
--  4. delete_my_account() — App Store bắt buộc (N-11).
--  5. set_participant_role() — thêm/bỏ co-host (F-12).
--  6. get_my_code_state() — app biết còn bao nhiêu lần thử / đang bị khóa đến khi nào
--     sau khi mở lại app (F-20); code_attempts vẫn không ai đọc trực tiếp.
--  7. Vùng bản đồ: tính lại tâm dịch lệch khi đổi bán kính hoặc khi quản trò dời
--     vị trí hint (trước đây tâm cũ có thể không còn chứa vị trí thật).
--  8. join_game chỉ phát 'player_joined' khi thật sự là người mới.
--  9. Policy Storage: tên thư mục không phải uuid → từ chối thay vì lỗi 500.
-- 10. Bucket avatars (F-02).
-- =====================================================================

-- 1 ------------------------------------------------------------------
alter table public.games alter column currency set default 'VND';
alter table public.profiles alter column display_name set default 'Người chơi';

-- Lấy tên từ Google / Apple khi đăng ký
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, display_name)
  values (new.id, left(coalesce(nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''),
                                nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
                                nullif(trim(new.raw_user_meta_data ->> 'name'), ''),
                                'Người chơi'), 40))
  on conflict (id) do nothing;
  return new;
end $$;

-- 2 ------------------------------------------------------------------
alter table public.submissions add column reminders_sent int not null default 0;

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

  -- c) Nhắc quản trò ở phút 5 và 10 (chỉ khi còn thời gian trước mốc tự approve)
  for r in
    update submissions s set reminders_sent = s.reminders_sent + 1
     where s.status = 'pending'
       and ((s.reminders_sent = 0 and s.uploaded_at + interval '5 minutes'  <= now())
         or (s.reminders_sent = 1 and s.uploaded_at + interval '10 minutes' <= now()))
       and (s.auto_approve_at is null or s.auto_approve_at > now())
    returning s.id, s.game_id, s.reminders_sent, s.auto_approve_at
  loop
    perform _emit(r.game_id, 'proof_review_reminder',
                  jsonb_build_object('submission_id', r.id, 'minutes', r.reminders_sent * 5,
                                     'auto_approve_at', r.auto_approve_at));
  end loop;

  -- d) Tự approve
  for r in
    select s.id from submissions s join games g on g.id = s.game_id
     where s.status = 'pending' and s.auto_approve_at <= now()
       and g.auto_approve_enabled and g.status = 'live'
  loop
    begin perform _approve_submission(r.id, true, null); exception when others then null; end;
  end loop;

  -- e) Thông báo các khối hint vừa mở theo giờ
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

-- 3 ------------------------------------------------------------------
create table public.device_tokens (
  token       text primary key,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  platform    text not null default 'ios' check (platform in ('ios', 'android', 'web')),
  updated_at  timestamptz not null default now()
);
create index on public.device_tokens (user_id);
alter table public.device_tokens enable row level security;
grant select, insert, update, delete on public.device_tokens to authenticated;
create policy device_tokens_own on public.device_tokens for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Đăng ký token (token có thể chuyển từ tài khoản cũ sang tài khoản mới trên cùng máy)
create or replace function public.register_device_token(p_token text, p_platform text default 'ios')
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  insert into device_tokens (token, user_id, platform) values (p_token, auth.uid(), p_platform)
  on conflict (token) do update set user_id = excluded.user_id, platform = excluded.platform,
                                    updated_at = now();
end $$;

-- 4 ------------------------------------------------------------------
-- Xóa tài khoản: profile, game do mình làm host, proof… bị xóa theo cascade.
-- Ảnh trong Storage được purge-proofs dọn (đường dẫn không còn được tham chiếu).
create or replace function public.delete_my_account()
returns void language plpgsql security definer set search_path = public, auth as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  delete from auth.users where id = auth.uid();
end $$;

-- 5 ------------------------------------------------------------------
create or replace function public.set_participant_role(p_game_id uuid, p_user_id uuid,
                                                       p_role public.participant_role)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from games where id = p_game_id and host_id = auth.uid()) then
    raise exception 'not_game_host';
  end if;
  if p_role = 'host' then raise exception 'invalid_role'; end if;
  update game_participants set role = p_role
   where game_id = p_game_id and user_id = p_user_id and role <> 'host';
  if not found then raise exception 'participant_not_found'; end if;
end $$;

-- 6 ------------------------------------------------------------------
create or replace function public.get_my_code_state(p_hint_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare g games%rowtype; v_fails int; v_last timestamptz; v_until timestamptz;
begin
  select g2.* into g from games g2 join hints h on h.game_id = g2.id where h.id = p_hint_id;
  if not found or not is_participant(g.id) then raise exception 'hint_not_found'; end if;
  select count(*), max(created_at) into v_fails, v_last from code_attempts
   where hint_id = p_hint_id and user_id = auth.uid() and not success
     and created_at > coalesce((select max(created_at) from code_attempts
                                 where hint_id = p_hint_id and user_id = auth.uid() and success),
                               '-infinity');
  if v_fails > 0 and v_fails % g.code_fails_before_lock = 0 then
    v_until := v_last + make_interval(mins => g.code_lock_minutes);
    if v_until <= now() then v_until := null; end if;
  end if;
  return jsonb_build_object(
    'attempts_before_lock', case when v_until is not null then 0
                                 else g.code_fails_before_lock - v_fails % g.code_fails_before_lock end,
    'locked_until', v_until);
end $$;

-- 7 ------------------------------------------------------------------
create or replace function public.fill_map_center()
returns trigger language plpgsql security definer set search_path = public as $$
declare h record; c record;
begin
  if new.type = 'map' and (new.map_center_lat is null or new.map_center_lng is null
       or (tg_op = 'UPDATE' and new.map_radius_m is distinct from old.map_radius_m)) then
    select answer_lat, answer_lng into h from hints where id = new.hint_id;
    select * into c from random_map_center(h.answer_lat, h.answer_lng, new.map_radius_m);
    new.map_center_lat := c.lat;
    new.map_center_lng := c.lng;
  end if;
  return new;
end $$;

drop trigger hint_items_fill_map on public.hint_items;
create trigger hint_items_fill_map before insert or update on public.hint_items
  for each row execute function public.fill_map_center();

create or replace function public.recenter_maps_on_move()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update hint_items set map_center_lat = null, map_center_lng = null
   where hint_id = new.id and type = 'map';           -- trigger fill_map_center sinh tâm mới
  return new;
end $$;

create trigger hints_recenter_maps after update of answer_lat, answer_lng on public.hints
  for each row when (old.answer_lat is distinct from new.answer_lat
                     or old.answer_lng is distinct from new.answer_lng)
  execute function public.recenter_maps_on_move();

-- 8 ------------------------------------------------------------------
create or replace function public.join_game(p_join_code text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_game uuid; v_new int;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  select id into v_game from games
   where join_code = upper(trim(p_join_code)) and status in ('draft', 'scheduled', 'live');
  if v_game is null then raise exception 'game_not_found'; end if;
  insert into game_participants (game_id, user_id, role)
  values (v_game, auth.uid(), 'player') on conflict do nothing;
  get diagnostics v_new = row_count;
  if v_new > 0 then
    perform _emit(v_game, 'player_joined', jsonb_build_object('user_id', auth.uid()));
  end if;
  return v_game;
end $$;

-- 9 + 10 -------------------------------------------------------------
create or replace function public.try_uuid(p text)
returns uuid language plpgsql immutable as $$
begin return p::uuid; exception when others then return null; end $$;

grant execute on function
  public.register_device_token(text, text), public.delete_my_account(),
  public.set_participant_role(uuid, uuid, public.participant_role),
  public.get_my_code_state(uuid), public.try_uuid(text)
to authenticated;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant select on public.device_tokens, public.game_participants, public.games,
                    public.profiles, public.submissions
      to service_role;
  end if;

  if exists (select 1 from information_schema.tables
              where table_schema = 'storage' and table_name = 'buckets') then
    update storage.buckets set file_size_limit = 2097152, allowed_mime_types = array['image/jpeg']
     where id = 'proofs';
    update storage.buckets set file_size_limit = 5242880,
           allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp']
     where id = 'hint-media';
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('avatars', 'avatars', true, 1048576, array['image/jpeg', 'image/png', 'image/webp'])
    on conflict (id) do nothing;

    drop policy if exists proofs_upload on storage.objects;
    create policy proofs_upload on storage.objects for insert to authenticated
      with check (bucket_id = 'proofs'
        and (storage.foldername(name))[2] = auth.uid()::text
        and public.is_participant(public.try_uuid((storage.foldername(name))[1])));

    drop policy if exists hint_media_write on storage.objects;
    create policy hint_media_write on storage.objects for insert to authenticated
      with check (bucket_id = 'hint-media'
        and public.is_game_staff(public.try_uuid((storage.foldername(name))[1])));
    create policy hint_media_delete on storage.objects for delete to authenticated
      using (bucket_id = 'hint-media'
        and public.is_game_staff(public.try_uuid((storage.foldername(name))[1])));

    create policy avatars_insert on storage.objects for insert to authenticated
      with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
    create policy avatars_update on storage.objects for update to authenticated
      using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
  end if;
end $$;
