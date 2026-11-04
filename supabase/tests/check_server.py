#!/usr/bin/env python3
"""So server Supabase thật với supabase/migrations: báo cột / hàm RPC mà server còn thiếu.

Chỉ ĐỌC, chỉ dùng anon key trong ios/Config/Secrets.xcconfig. Không cần quyền admin vì dựa vào mã lỗi:
  - GET  /rest/v1/<table>?select=<col>&limit=0 : 42703 = cột không tồn tại; 42501/200 = có.
  - POST /rest/v1/rpc/<fn> với đủ tên tham số (giá trị null): PGRST202 = không có hàm với chữ ký đó;
    42501 (anon bị thu hồi quyền) hoặc lỗi khác = hàm có.
Mỗi mục thiếu kèm tên file migration định nghĩa nó, để biết cần chạy file nào.

Dùng: python3 -I supabase/tests/check_server.py   (exit 1 nếu thiếu, 2 nếu không kết nối được)
"""
import json
import pathlib
import re
import sys
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[2]
MIGRATIONS = sorted((ROOT / "supabase" / "migrations").glob("*.sql"))
SECRETS = ROOT / "ios" / "Config" / "Secrets.xcconfig"
# Hàm nội bộ (trigger, helper) không gọi qua REST: bỏ qua.
SKIP_FN = re.compile(r"^_|^(try_uuid|normalize_code|is_participant|is_game_staff|game_is_editable|hint_is_editable|"
                     r"handle_new_user|add_host_participant|enforce_.*|check_.*|set_updated_at)$")

TYPE = (r"(?:uuid|text|int|integer|smallint|bigint|numeric|boolean|bool|timestamptz|timestamp|date|float8|"
        r"double|real|char|varchar|jsonb|json|bytea|public\.\w+)\b")


def secrets():
    vals = {}
    for line in SECRETS.read_text().splitlines():
        m = re.match(r"\s*(SUPABASE_URL|SUPABASE_ANON_KEY)\s*=\s*(.+)", line)
        if m:
            vals[m.group(1)] = m.group(2).replace("$()", "").strip()
    return vals["SUPABASE_URL"].rstrip("/"), vals["SUPABASE_ANON_KEY"]


def parse_migrations():
    """{(table, col): file} và {fn: (params, file)} theo định nghĩa CUỐI CÙNG của mỗi hàm."""
    cols, fns, dropped_cols = {}, {}, set()
    for f in MIGRATIONS:
        sql = re.sub(r"--[^\n]*", "", f.read_text())
        for m in re.finditer(r"create table (?:if not exists )?public\.(\w+)\s*\((.*?)\n\);", sql, re.S):
            table, body = m.group(1), m.group(2)
            for line in body.splitlines():
                # Chỉ dòng "tên kiểu ...": bỏ dòng nối tiếp (default …, or …) và ràng buộc bảng.
                w = re.match(r"\s*([a-z_][a-z0-9_]*)\s+" + TYPE, line)
                if w and w.group(1) not in ("primary", "unique", "check", "constraint", "foreign", "exclude"):
                    cols.setdefault((table, w.group(1)), f.name)
        for m in re.finditer(r"alter table (?:only )?public\.(\w+)\s+add column (?:if not exists )?(\w+)", sql):
            cols.setdefault((m.group(1), m.group(2)), f.name)
        for m in re.finditer(r"alter table (?:only )?public\.(\w+)\s+drop column (?:if exists )?(\w+)", sql):
            dropped_cols.add((m.group(1), m.group(2)))
        for m in re.finditer(r"create (?:or replace )?function public\.(\w+)\s*\((.*?)\)\s*returns\s+(\w+)",
                             sql, re.S | re.I):
            name, args = m.group(1), m.group(2)
            if m.group(3).lower() == "trigger":  # hàm trigger không gọi qua REST
                continue
            params = re.findall(r"(?:^|,)\s*(?:in\s+)?(p_\w+)", args)
            fns[name] = (params, f.name)
    for k in dropped_cols:
        cols.pop(k, None)
    return cols, {k: v for k, v in fns.items() if not SKIP_FN.match(k)}


def request(url, key, data=None):
    req = urllib.request.Request(url, data=None if data is None else json.dumps(data).encode(),
                                 headers={"apikey": key, "Content-Type": "application/json"},
                                 method="GET" if data is None else "POST")
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return r.status, {}
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read() or b"{}")
        except ValueError:
            return e.code, {}


def main():
    if not SECRETS.exists():
        print("SKIP: không có ios/Config/Secrets.xcconfig")
        return 0
    url, key = secrets()
    cols, fns = parse_migrations()
    missing = []
    try:
        for (table, col), file in sorted(cols.items()):
            status, body = request(f"{url}/rest/v1/{table}?select={col}&limit=0", key)
            if body.get("code") in ("42703", "PGRST204", "42P01", "PGRST205"):
                missing.append(f"cột   {table}.{col:<28} ({file})")
        for name, (params, file) in sorted(fns.items()):
            status, body = request(f"{url}/rest/v1/rpc/{name}", key, {p: None for p in params})
            if body.get("code") == "PGRST202":
                missing.append(f"hàm   {name}({', '.join(params)})  ({file})")
    except urllib.error.URLError as e:
        print(f"KHÔNG KẾT NỐI ĐƯỢC server: {e}")
        return 2
    print(f"Đã kiểm tra {len(cols)} cột, {len(fns)} hàm RPC trên {url}")
    if missing:
        print(f"SERVER THIẾU {len(missing)} mục (chạy các migration tương ứng, theo thứ tự tên file):")
        print("\n".join("  " + m for m in missing))
        return 1
    print("OK: server khớp với supabase/migrations.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
