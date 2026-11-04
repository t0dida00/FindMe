#!/usr/bin/env python3
"""Kiểm tra tĩnh hợp đồng app iOS ↔ SQL (không cần mạng, không cần DB).

1. Mọi `db.rpc("x")` trong ios/FindMe phải là hàm `public.x` trong supabase/migrations.
2. Mọi `db.from("t")` phải là bảng `public.t`.
3. Mọi `raise exception '<code>'` trong migrations phải có trong AppError.knownCodes và message(code:).
4. Mọi migration phải được liệt kê trong supabase/tests/run.sh.

Dùng: python3 -I supabase/tests/check_contract.py   (exit 1 nếu có lỗi)
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
MIG_DIR = ROOT / "supabase" / "migrations"
SWIFT = list((ROOT / "ios" / "FindMe").rglob("*.swift"))
APP_ERROR = ROOT / "ios" / "FindMe" / "Core" / "AppError.swift"
RUN_SH = ROOT / "supabase" / "tests" / "run.sh"


def main():
    sql = "\n".join(re.sub(r"--[^\n]*", "", f.read_text()) for f in sorted(MIG_DIR.glob("*.sql")))
    swift = "\n".join(f.read_text() for f in SWIFT)
    problems = []

    fns = set(re.findall(r"create (?:or replace )?function public\.(\w+)", sql, re.I))
    for name in sorted(set(re.findall(r'\.rpc\(\s*"(\w+)"', swift))):
        if name not in fns:
            problems.append(f"app gọi RPC '{name}' nhưng migrations không có hàm public.{name}")

    tables = set(re.findall(r"create table (?:if not exists )?public\.(\w+)", sql, re.I))
    # storage.from("bucket") là bucket Storage, không phải bảng.
    for name in sorted(set(re.findall(r'(?<!storage)\.from\(\s*"(\w+)"', swift))):
        if name not in tables:
            problems.append(f"app đọc/ghi bảng '{name}' nhưng migrations không có bảng public.{name}")

    err = APP_ERROR.read_text()
    block = re.search(r"static let knownCodes\s*=\s*\[(.*?)\]", err, re.S)
    known = set(re.findall(r'"([a-z_]+)"', block.group(1))) if block else set()
    cases = set(re.findall(r'case "([a-z_]+)"', err))
    for code in sorted(set(re.findall(r"raise exception '([a-z_]+)'", sql))):
        if code not in known:
            problems.append(f"mã lỗi SQL '{code}' thiếu trong AppError.knownCodes")
        if code not in cases:
            problems.append(f"mã lỗi SQL '{code}' thiếu câu báo trong AppError.message(code:)")

    run_sh = RUN_SH.read_text()
    for f in sorted(MIG_DIR.glob("*.sql")):
        if f.name not in run_sh:
            problems.append(f"migration {f.name} chưa được liệt kê trong supabase/tests/run.sh")

    if problems:
        print(f"HỢP ĐỒNG APP ↔ SQL: {len(problems)} lỗi")
        print("\n".join("  - " + p for p in problems))
        return 1
    print("OK: hợp đồng app ↔ SQL khớp (RPC, bảng, mã lỗi, run.sh).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
