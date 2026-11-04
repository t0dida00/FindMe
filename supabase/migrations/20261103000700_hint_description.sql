-- =====================================================================
--  Find Me! — mô tả cho hint (chạy sau 20261103000600_player_limit.sql)
--
--  1. hints.description: mô tả ngắn, không bắt buộc (tối đa 500 ký tự), cạnh tiêu đề.
--     Quản trò đặt khi tạo (create_hint, thêm tham số p_description) và sửa trực tiếp bảng hints
--     (cùng RLS với title).
--  2. Người chơi thấy mô tả cùng lúc với tiêu đề: get_hint_items() và get_current_hint() trả thêm
--     cột hint_description. Phải drop rồi tạo lại vì đổi kiểu trả về; thân hàm giữ nguyên.
-- =====================================================================

-- 1 ------------------------------------------------------------------
alter table public.hints
  add column description text check (char_length(description) <= 500);

grant update (description) on public.hints to authenticated;

drop function public.create_hint(uuid, int, text, float8, float8, numeric, text);
create function public.create_hint(
  p_game_id uuid, p_hint_order int, p_code text,
  p_answer_lat float8, p_answer_lng float8,
  p_prize numeric default 0, p_title text default null, p_description text default null)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare v_id uuid;
begin
  if not is_game_staff(p_game_id) then raise exception 'not_game_staff'; end if;
  if not game_is_editable(p_game_id) then raise exception 'game_not_editable'; end if;
  if char_length(normalize_code(p_code)) < 6 then raise exception 'code_too_short'; end if;

  insert into hints (game_id, hint_order, title, description, prize, answer_lat, answer_lng, code_hash)
  values (p_game_id, p_hint_order, nullif(trim(p_title), ''), nullif(trim(p_description), ''),
          p_prize, p_answer_lat, p_answer_lng, crypt(normalize_code(p_code), gen_salt('bf')))
  returning id into v_id;
  return v_id;
end $$;

-- 2 ------------------------------------------------------------------
drop function public.get_hint_items(uuid);
create function public.get_hint_items(p_game_id uuid)
returns table (hint_id uuid, hint_order int, hint_title text, hint_description text, prize numeric,
               hint_activated_at timestamptz, hint_solved boolean,
               item_id uuid, item_order int, type public.hint_item_type,
               text_content text, image_path text,
               map_center_lat float8, map_center_lng float8, map_radius_m int)
language sql stable security definer set search_path = public as $$
  select h.id, h.hint_order, h.title, h.description, h.prize, h.activated_at, h.revealed_at is not null,
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

drop function public.get_current_hint(uuid);
create function public.get_current_hint(p_game_id uuid)
returns table (hint_id uuid, hint_order int, hint_title text, hint_description text, prize numeric,
               activated_at timestamptz, hint_count int)
language sql stable security definer set search_path = public as $$
  select h.id, h.hint_order, h.title, h.description, h.prize, h.activated_at,
         (select count(*)::int from hints where game_id = g.id)
    from games g
    join hints h on h.game_id = g.id and h.hint_order = g.current_hint_order
   where g.id = p_game_id and is_participant(p_game_id);
$$;

-- Supabase tự cấp quyền mặc định cho hàm mới (cả anon): thu hồi rồi chỉ cấp cho authenticated.
revoke all on function public.create_hint(uuid, int, text, float8, float8, numeric, text, text),
                       public.get_hint_items(uuid), public.get_current_hint(uuid)
  from public, anon;
grant execute on function public.create_hint(uuid, int, text, float8, float8, numeric, text, text),
                          public.get_hint_items(uuid), public.get_current_hint(uuid)
  to authenticated;

notify pgrst, 'reload schema';
