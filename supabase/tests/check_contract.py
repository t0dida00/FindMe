#!/usr/bin/env python3
"""Kiểm tra tĩnh hợp đồng app iOS ↔ server Go (không cần mạng, không cần DB).

1. Mọi lời gọi `GoAPI` trong ios/FindMe (method + "/v1/…") phải khớp một route của server
   (server/internal/interfaces/httpapi).
2. App không còn gọi dữ liệu Supabase trực tiếp: không `.rpc(`, `.from(`, `storage.from(`, `.channel(`
   (Supabase chỉ dùng để đăng nhập).
3. Mọi mã lỗi luật chơi server trả (`shared.Rule("x")`, mã trong RedeemResult) phải có trong
   AppError.knownCodes và message(code:) (hoặc goMessage cho mã mức HTTP).
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
SERVER = ROOT / "server" / "internal"

# Mã lỗi mức HTTP / nhập liệu: app báo chung qua goMessage (theo mã hoặc theo HTTP status).
GENERIC = {"not_found", "forbidden", "invalid_argument", "invalid_join_code", "timeout", "canceled",
           "rate_limited", "too_many_streams", "payload_too_large", "internal", "unavailable"}


def server_routes():
    routes = []
    for f in (SERVER / "interfaces" / "httpapi").glob("*.go"):
        if f.name.endswith("_test.go"):
            continue
        text = f.read_text()
        # group prefixes: x := y.Group("/games") → routes under it
        for m in re.finditer(r'(\w+)\.(GET|POST)\("([^"]*)"', text):
            routes.append((m.group(1), m.group(2), m.group(3)))
        for m in re.finditer(r'(\w+)\.Handle\(http\.Method(\w+), "([^"]*)"', text):
            routes.append((m.group(1), m.group(2).upper(), m.group(3)))
    prefix = {"games": "/v1/games", "me": "/v1/me", "g": "/v1", "authed": "/v1", "public": ""}
    out = set()
    for grp, method, path in routes:
        if method == "PATCH" or method == "PUT" or method == "DELETE" or method in ("GET", "POST"):
            base = prefix.get(grp, "/v1")
            out.add((method, (base + path).rstrip("/") or "/"))
    out.add(("GET", "/v1/games/{id}/stream"))
    return out


def norm(path):
    out, i = "", 0
    while i < len(path):  # Swift \(…) (parentheses may nest) → {}
        if path.startswith("\\(", i):
            depth, i = 1, i + 2
            while i < len(path) and depth:
                depth += {"(": 1, ")": -1}.get(path[i], 0)
                i += 1
            out += "{}"
        else:
            out += path[i]
            i += 1
    return re.sub(r"\{[^}/]*\}", "{}", out)


def main():
    swift = "\n".join(f.read_text() for f in SWIFT)
    problems = []

    routes = {(m, norm(p)) for m, p in server_routes()}
    calls = set()
    for m in re.finditer(r'GoAPI\.(get|getOptional)\(\s*"(/v1[^"]*)"', swift):
        calls.add(("GET", norm(m.group(2))))
    for m in re.finditer(r'GoAPI\.(?:write|send|request)\(\s*"(\w+)",\s*"(/v1[^"]*)"', swift):
        calls.add((m.group(1), norm(m.group(2))))
    for m in re.finditer(r'let path = "(/v1[^"]*)"', swift):  # stream
        calls.add(("GET", norm(m.group(1))))
    for method, path in sorted(calls):
        if (method, path) not in routes:
            problems.append(f"app gọi {method} {path} nhưng server không có route này")

    for pat, what in [(r"\.rpc\(", "RPC Supabase"), (r'(?<!storage)\bdb\.from\(|\.from\("\w+"\)\.select', "bảng Supabase"),
                      (r"storage\.from\(", "Supabase Storage trực tiếp"), (r"\.channel\(", "Supabase Realtime")]:
        if re.search(pat, swift):
            problems.append(f"app còn gọi {what} (dữ liệu chỉ đi qua server)")

    err = APP_ERROR.read_text()
    block = re.search(r"static let knownCodes\s*=\s*\[(.*?)\]", err, re.S)
    known = set(re.findall(r'"([a-z_]+)"', block.group(1))) if block else set()
    cases = set(re.findall(r'case "([a-z_]+)"', err))
    go = "\n".join(f.read_text() for f in SERVER.rglob("*.go") if not f.name.endswith("_test.go"))
    consts = dict(re.findall(r'(Code\w+)\s*=\s*"([a-z_]+)"', go))
    codes = set(re.findall(r'shared\.Rule\("([a-z_]+)"\)', go))
    codes |= {consts[c] for c in re.findall(r"shared\.Rule\(shared\.(Code\w+)\)", go) if c in consts}
    codes |= set(re.findall(r'Error: "([a-z_]+)"', go))  # RedeemResult answers
    codes |= set(re.findall(r'(?:,|\()\s*"([a-z_]+_not_found|not_game_\w+)"\)', go))  # or(err, "…") fallbacks
    for code in sorted(codes - GENERIC):
        if code not in known:
            problems.append(f"mã lỗi server '{code}' thiếu trong AppError.knownCodes")
        if code not in cases:
            problems.append(f"mã lỗi server '{code}' thiếu câu báo trong AppError.message(code:)")

    run_sh = RUN_SH.read_text()
    for f in sorted(MIG_DIR.glob("*.sql")):
        if f.name not in run_sh:
            problems.append(f"migration {f.name} chưa được liệt kê trong supabase/tests/run.sh")

    if problems:
        print(f"HỢP ĐỒNG APP ↔ SERVER: {len(problems)} lỗi")
        print("\n".join("  - " + p for p in problems))
        return 1
    print(f"OK: hợp đồng app ↔ server khớp ({len(calls)} lời gọi API, {len(codes - GENERIC)} mã lỗi, run.sh).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
