-- Find Me!: luật "1 người, 1 cuộc săn" + seed demo mới (10 cuộc săn quanh TP.HCM). Dán vào Supabase SQL Editor rồi bấm Run.
begin;
-- =====================================================================
--  Find Me! — 1 người, 1 cuộc săn (chạy sau 20261103000400_globe.sql)
--
--  Mỗi người chỉ được ở trong MỘT cuộc săn chưa kết thúc (draft, scheduled, live), dù với
--  vai trò quản trò, co-host hay người chơi. Cuộc săn completed / cancelled không tính.
--
--  Chặn tại một chỗ duy nhất: trigger BEFORE INSERT trên game_participants. Mọi đường vào
--  đều đi qua đây:
--    - tạo game → trigger games_add_host chèn dòng 'host' → bị chặn → cả lệnh tạo game rollback;
--    - join_game() → chèn dòng 'player' → bị chặn;
--    - vào lại chính cuộc săn mình đang ở thì không bị chặn.
--  Khóa advisory theo user để hai lệnh join/tạo chạy đồng thời không cùng lọt qua.
--  Không kiểm tra lại dữ liệu cũ: chỉ áp dụng cho lượt tham gia mới.
-- =====================================================================

create or replace function public.enforce_one_active_hunt()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_other uuid;
begin
  -- Cuộc săn đích đã kết thúc thì không cần kiểm tra
  if not exists (select 1 from games where id = new.game_id
                  and status in ('draft', 'scheduled', 'live')) then
    return new;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('one_active_hunt:' || new.user_id::text, 0));
  select gp.game_id into v_other
    from game_participants gp join games g on g.id = gp.game_id
   where gp.user_id = new.user_id and gp.game_id <> new.game_id
     and g.status in ('draft', 'scheduled', 'live')
   limit 1;
  if v_other is not null then raise exception 'already_in_active_game'; end if;
  return new;
end $$;

create trigger game_participants_one_active_hunt
  before insert on public.game_participants
  for each row execute function public.enforce_one_active_hunt();

-- Cuộc săn chưa kết thúc của mình (0..1 dòng), để app biết vì sao bị chặn.
create or replace function public.get_my_active_game()
returns table (game_id uuid, title text, status public.game_status, role public.participant_role)
language sql stable security definer set search_path = public as $$
  select g.id, g.title, g.status, gp.role
    from game_participants gp join games g on g.id = gp.game_id
   where gp.user_id = auth.uid() and g.status in ('draft', 'scheduled', 'live')
   order by g.created_at desc
   limit 1;
$$;

revoke all on function public.enforce_one_active_hunt(), public.get_my_active_game()
  from public, anon, authenticated;
grant execute on function public.get_my_active_game() to authenticated;

-- =====================================================================
--  Find Me! — dữ liệu demo: 10 cuộc săn công khai ngẫu nhiên quanh TP. Hồ Chí Minh
--
--  Chỉ dùng cho môi trường dev/staging. `supabase db reset` tự nạp file này (config.toml →
--  [db.seed]). Muốn nạp tay: psql "$DATABASE_URL" -f supabase/seed.sql
--  Chạy lại được: dữ liệu demo cũ (user id bắt đầu bằng de000000-) bị xóa trước.
--
--  - 10 quản trò + 40 người chơi demo (không đăng nhập được: không có email/identity).
--  - Tuân thủ luật "1 người, 1 cuộc săn" (20261103000500_one_active_hunt.sql): mỗi quản trò
--    tổ chức đúng 1 cuộc săn; người chơi ở các cuộc săn chưa kết thúc không trùng nhau
--    (cuộc săn đã kết thúc thì được trùng, coi như lịch sử).
--  - 4 cuộc săn đang diễn ra, 3 sắp diễn ra, 3 đã kết thúc. Khu vực = quận thật + lệch ngẫu
--    nhiên ~1 km. Mỗi cuộc săn có 3–5 hint, đáp án lệch ngẫu nhiên quanh khu vực.
--  - Hint đã giải có submission approved + rewards; game đã kết thúc có giải tổng và lượt
--    chấm sao, để tab Xếp hạng và Globe có dữ liệu.
--  - Mã proof của hint k ở game i là DEMO<i>X<k> (vd. DEMO3X2), để thử nhập mã.
-- =====================================================================

-- Xóa game demo trước (submissions.reviewed_by không cascade nên xóa user trước sẽ lỗi khóa ngoại)
delete from public.games where host_id::text like 'de000000-%';
delete from auth.users where id::text like 'de000000-%';

insert into auth.users (id, raw_user_meta_data)
select ('de000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
       jsonb_build_object('display_name', name)
  from unnest(array[
         'Quản trò Sài Gòn', 'Minh Thư Hunts', 'Đội Khám Phá Q1', 'Rùa Vàng Studio', 'Phố Cổ Team',
         'Hẻm Xinh Club', 'Sông Sài Gòn Crew', 'Mê Cung Q10', 'Cà Phê Bí Ẩn', 'Chợ Hoa Hunts'])
       with ordinality as t(name, n);

-- 40 người chơi: họ × tên ghép cố định
insert into auth.users (id, raw_user_meta_data)
select ('de000000-0000-0000-0000-' || lpad((10 + n)::text, 12, '0'))::uuid,
       jsonb_build_object('display_name',
         (array['Nguyễn','Trần','Lê','Phạm','Hoàng','Vũ','Đặng','Bùi'])[1 + (n - 1) % 8] || ' ' ||
         (array['Lan Anh','Quốc Bảo','Thảo Vy','Hoàng Nam','Ngọc Hân','Tuấn Kiệt','Bảo Trâm','Đức Huy',
                'Mai Phương','Gia Hưng','Khánh Linh','Trọng Nhân','Minh Khôi','Thu Hà','Phúc An',
                'Hải Yến','Quang Huy','Diệu Linh','Văn Toàn','Kim Ngân'])[1 + (n - 1) % 20])
  from generate_series(1, 40) n;

do $$
declare
  hosts   uuid[] := array(select ('de000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid
                            from generate_series(1, 10) n);
  players uuid[] := array(select ('de000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid
                            from generate_series(11, 50) n);
  areas   text[] := array['Quận 1', 'Quận 3', 'Chợ Lớn, Quận 5', 'Bình Thạnh', 'Phú Nhuận',
                          'Thảo Điền, Thủ Đức', 'Phú Mỹ Hưng, Quận 7', 'Gò Vấp', 'Tân Bình', 'Quận 10'];
  lats    float8[] := array[10.7756, 10.7830, 10.7540, 10.8106, 10.7990, 10.8030, 10.7290, 10.8380, 10.8010, 10.7730];
  lngs    float8[] := array[106.7019, 106.6870, 106.6630, 106.7091, 106.6800, 106.7350, 106.7180, 106.6650, 106.6520, 106.6680];
  titles  text[] := array['Bí ẩn phố đi bộ Nguyễn Huệ', 'Dấu chân Hồ Con Rùa', 'Kho báu Chợ Lớn',
                          'Săn đèn lồng ven sông Sài Gòn', 'Hẻm nhỏ Phú Nhuận', 'Thảo Điền lúc hoàng hôn',
                          'Mật mã Phú Mỹ Hưng', 'Truy tìm quán cà phê bí mật', 'Sân bay cũ Tân Sơn Nhất',
                          'Huyền thoại chợ hoa Hồ Thị Kỷ'];
  i int; k int; n_hints int; n_solved int; g_id uuid; h_id uuid; s_id uuid; winner uuid;
  g_players uuid[]; v_grand numeric; t0 timestamptz; st timestamptz;
begin
  for i in 1..10 loop
    v_grand := (2 + floor(random() * 19)) * 500000;          -- 1–10 triệu
    insert into games (host_id, title, description, grand_prize, currency, is_public,
                       area_lat, area_lng, area_name, created_at)
    values (hosts[i], titles[i],
            'Game demo quanh ' || areas[i] || '. Xin mã tham gia từ quản trò.',
            v_grand, 'VND', true,
            lats[i] + (random() - 0.5) * 0.02, lngs[i] + (random() - 0.5) * 0.02, areas[i],
            now() - make_interval(days => 20 + i))
    returning id into g_id;
    -- Game đã kết thúc: đặt trạng thái trước khi thêm người chơi, để luật "1 người, 1 cuộc săn"
    -- không tính game này (người chơi của nó đang ở cuộc săn khác).
    if i >= 8 then update games set status = 'completed' where id = g_id; end if;

    -- Cuộc săn chưa kết thúc (1–7): mỗi game dùng riêng 5 ô người chơi (i-1)*5+1 .. i*5, lấy 3–5 người,
    -- nên không ai ở 2 cuộc săn chưa kết thúc. Đã kết thúc (8–10): 3–10 người bất kỳ.
    if i <= 7 then
      g_players := players[(i - 1) * 5 + 1 : (i - 1) * 5 + 3 + floor(random() * 3)::int];
    else
      g_players := array(select p from unnest(players) p order by random() limit 3 + floor(random() * 8)::int);
    end if;
    insert into game_participants (game_id, user_id, role, joined_at)
    select g_id, p, 'player', now() - make_interval(days => 15 + i) from unnest(g_players) p;

    n_hints := 3 + floor(random() * 3)::int;
    for k in 1..n_hints loop
      insert into hints (game_id, hint_order, title, prize, answer_lat, answer_lng, code_hash)
      values (g_id, k, 'Chặng ' || k, (1 + floor(random() * 4)) * 100000,
              lats[i] + (random() - 0.5) * 0.016, lngs[i] + (random() - 0.5) * 0.016,
              extensions.crypt(normalize_code('DEMO' || i || 'X' || k), extensions.gen_salt('bf')))
      returning id into h_id;
      insert into hint_items (hint_id, item_order, type, text_content)
      values (h_id, 1, 'text', 'Gợi ý demo cho chặng ' || k || ' của "' || titles[i] || '".');
    end loop;

    if i between 5 and 7 then
      -- Sắp diễn ra: 1–7 ngày nữa
      update games set status = 'scheduled',
             starts_at = date_trunc('hour', now()) + make_interval(days => i - 4, hours => 9)
       where id = g_id;
      continue;
    end if;

    -- Đang diễn ra (1–4): giải được một phần; đã kết thúc (8–10): giải hết
    n_solved := case when i <= 4 then floor(random() * n_hints)::int else n_hints end;
    st := case when i <= 4 then now() - make_interval(mins => 30 + floor(random() * 150)::int)
               else now() - make_interval(days => i * 2) end;
    t0 := st;
    for k in 1..n_solved loop
      select id into h_id from hints where game_id = g_id and hint_order = k;
      winner := g_players[1 + floor(random() * array_length(g_players, 1))::int];
      insert into submissions (game_id, hint_id, user_id, status, reserved_at, upload_deadline,
                               uploaded_at, reviewed_at, reviewed_by)
      values (g_id, h_id, winner, 'approved', t0 + interval '20 min', t0 + interval '21 min',
              t0 + interval '20 min 30 s', t0 + interval '25 min', hosts[i])
      returning id into s_id;
      update hints set activated_at = t0, revealed_at = t0 + interval '25 min', winner_submission_id = s_id
       where id = h_id;
      insert into rewards (game_id, hint_id, kind, winner_id, amount, currency, created_at)
      select g_id, h_id, 'milestone', winner, h.prize, 'VND', t0 + interval '25 min' from hints h where h.id = h_id;
      if k = n_hints then
        insert into rewards (game_id, hint_id, kind, winner_id, amount, currency, created_at)
        values (g_id, h_id, 'grand', winner, v_grand, 'VND',
                t0 + interval '25 min');
      end if;
      t0 := t0 + interval '25 min';
    end loop;

    if i <= 4 then
      update hints set activated_at = t0 where game_id = g_id and hint_order = n_solved + 1;
      update games set status = 'live', started_at = st, current_hint_order = n_solved + 1 where id = g_id;
    else
      update games set status = 'completed', started_at = st, ended_at = t0 where id = g_id;
      insert into host_ratings (game_id, rater_id, stars)
      select g_id, p, 3 + floor(random() * 3)::int
        from unnest(g_players) p order by random() limit 1 + floor(random() * 3)::int;
    end if;
  end loop;
end $$;

notify pgrst, 'reload schema';
commit;
select title, status, area_name, (select count(*) from public.game_participants p where p.game_id = g.id and p.role = 'player') as players from public.games g where is_public order by status, title;
