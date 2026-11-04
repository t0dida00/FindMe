-- =====================================================================
--  Find Me! — quản trò xem lại được mã proof (chạy sau 20261103001200_hint_title_required.sql)
--
--  hints.code_hash vẫn là bcrypt và vẫn là thứ redeem_code kiểm tra. Mã gốc được lưu thêm trong
--  bảng riêng hint_codes, chỉ staff của game đọc được (RLS); người chơi không đọc được và không
--  ai ghi trực tiếp: chỉ create_hint / set_hint_code ghi vào.
--  Hint tạo trước migration này không có mã gốc: quản trò dùng "Đặt mã mới" để có lại.
-- =====================================================================

create table if not exists public.hint_codes (
  hint_id    uuid primary key references public.hints (id) on delete cascade,
  code       text not null,
  updated_at timestamptz not null default now()
);

alter table public.hint_codes enable row level security;
revoke all on public.hint_codes from anon, authenticated;
grant select on public.hint_codes to authenticated;
drop policy if exists hint_codes_staff_read on public.hint_codes;
create policy hint_codes_staff_read on public.hint_codes for select to authenticated
  using (exists (select 1 from public.hints h where h.id = hint_id and public.is_game_staff(h.game_id)));

create or replace function public.create_hint(
  p_game_id uuid, p_hint_order int, p_code text,
  p_answer_lat float8, p_answer_lng float8,
  p_prize numeric default 0, p_title text default null, p_description text default null)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare v_id uuid;
begin
  if not is_game_staff(p_game_id) then raise exception 'not_game_staff'; end if;
  if not game_is_editable(p_game_id) then raise exception 'game_not_editable'; end if;
  if nullif(trim(p_title), '') is null then raise exception 'hint_title_required'; end if;
  if char_length(normalize_code(p_code)) < 6 then raise exception 'code_too_short'; end if;

  insert into hints (game_id, hint_order, title, description, prize, answer_lat, answer_lng, code_hash)
  values (p_game_id, p_hint_order, trim(p_title), nullif(trim(p_description), ''),
          p_prize, p_answer_lat, p_answer_lng, crypt(normalize_code(p_code), gen_salt('bf')))
  returning id into v_id;
  insert into hint_codes (hint_id, code) values (v_id, trim(p_code));
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
  insert into hint_codes (hint_id, code) values (p_hint_id, trim(p_code))
  on conflict (hint_id) do update set code = excluded.code, updated_at = now();
end $$;

notify pgrst, 'reload schema';
