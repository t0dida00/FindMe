-- =====================================================================
--  Find Me! — hint bắt buộc có tiêu đề (chạy sau 20261103001100_globe_recent_finished.sql)
--
--  1. Ràng buộc hints_title_required: tiêu đề không rỗng. NOT VALID nên các hint cũ chưa có tiêu đề
--     vẫn giữ nguyên, nhưng mọi insert/update từ nay phải có tiêu đề (cả khi quản trò sửa trực tiếp
--     bảng hints qua RLS).
--  2. create_hint báo lỗi rõ ràng 'hint_title_required' thay vì lỗi vi phạm ràng buộc.
--     Mô tả vẫn không bắt buộc. Chữ ký hàm giữ nguyên nên create or replace là đủ.
-- =====================================================================

-- 1 ------------------------------------------------------------------
alter table public.hints
  add constraint hints_title_required check (char_length(trim(title)) > 0) not valid;

-- 2 ------------------------------------------------------------------
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
  return v_id;
end $$;

notify pgrst, 'reload schema';
