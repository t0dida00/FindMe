// Edge Function "push": gửi APNs cho các sự kiện trong game_events.
// Gắn bằng Database Webhook: Dashboard → Database → Webhooks → INSERT on public.game_events
// → HTTP POST tới /functions/v1/push, header  x-webhook-secret: <PUSH_WEBHOOK_SECRET>.
//
// Secrets cần đặt (supabase secrets set ...):
//   PUSH_WEBHOOK_SECRET, APNS_KEY (nội dung file .p8), APNS_KEY_ID, APNS_TEAM_ID,
//   APNS_BUNDLE_ID (vd. com.findme.app), APNS_PRODUCTION ("true" cho App Store/TestFlight)
import { createClient } from "npm:@supabase/supabase-js@2.49.4";

type GameEvent = {
  id: number;
  game_id: string;
  type: string;
  payload: Record<string, unknown>;
  created_at: string;
};

// Nội dung push được bản địa hóa trên máy người nhận: server chỉ gửi `loc-key` + `loc-args`,
// iOS tra key trong Localizable.xcstrings của app theo ngôn ngữ của máy (vi/en).
// Thêm key mới: thêm cả bản vi và en vào ios/FindMe/Resources/Localizable.xcstrings (key "push.*").
// `title` là tên cuộc săn (nội dung người dùng, không dịch) trừ khi có `titleKey`.
type Message = {
  to: "all" | "staff" | "players" | { user: string };
  title?: string;
  titleKey?: string;
  key: string;
  args?: string[];
};

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);

function messagesFor(e: GameEvent, gameTitle: string): Message[] {
  const p = e.payload;
  const order = String(p.hint_order ?? "");
  switch (e.type) {
    case "game_started":
      return [{ to: "players", title: gameTitle, key: "push.game_started" }];
    case "hint_activated":
      return Number(p.hint_order) > 1
        ? [{ to: "players", title: gameTitle, key: "push.hint_activated", args: [order] }]
        : [];
    case "hint_item_revealed":
      return [{ to: "players", title: gameTitle, key: "push.hint_item_revealed", args: [order] }];
    case "hint_solved":
      return [
        { to: { user: String(p.winner_id) }, titleKey: "push.proof_approved.title", key: "push.proof_approved", args: [order] },
        p.winner_name
          ? { to: "all", title: gameTitle, key: "push.hint_solved", args: [String(p.winner_name), order] }
          : { to: "all", title: gameTitle, key: "push.hint_solved_anonymous", args: [order] },
      ];
    case "proof_denied":
      return [p.reason
        ? { to: { user: String(p.user_id) }, titleKey: "push.proof_denied.title", key: "push.proof_denied_reason", args: [String(p.reason)] }
        : { to: { user: String(p.user_id) }, titleKey: "push.proof_denied.title", key: "push.proof_denied" }];
    case "proof_awaiting_review":
      return [{ to: "staff", title: gameTitle, key: "push.proof_awaiting_review" }];
    case "proof_review_reminder":
      return [{ to: "staff", title: gameTitle, key: "push.proof_review_reminder", args: [String(p.minutes ?? "")] }];
    case "game_completed":
      return [{ to: "all", title: gameTitle, key: "push.game_completed" }];
    case "game_cancelled":
      return [{ to: "all", title: gameTitle, key: "push.game_cancelled" }];
    default:
      return [];
  }
}

function apsAlert(msg: Message) {
  return {
    ...(msg.titleKey ? { "title-loc-key": msg.titleKey } : { title: msg.title }),
    "loc-key": msg.key,
    ...(msg.args?.length ? { "loc-args": msg.args } : {}),
  };
}

async function recipients(gameId: string, to: Message["to"]): Promise<string[]> {
  if (typeof to === "object") return [to.user];
  let q = supabase.from("game_participants").select("user_id").eq("game_id", gameId);
  if (to === "staff") q = q.in("role", ["host", "cohost"]);
  if (to === "players") q = q.eq("role", "player");
  const { data, error } = await q;
  if (error) throw error;
  return (data ?? []).map((r) => r.user_id as string);
}

// ---- APNs (token-based, ES256 JWT, cache 50 phút) --------------------------
let cachedJwt: { token: string; at: number } | null = null;

function b64url(data: ArrayBuffer | Uint8Array | string): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : new Uint8Array(data);
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function apnsJwt(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedJwt && now - cachedJwt.at < 50 * 60) return cachedJwt.token;
  const pem = Deno.env.get("APNS_KEY")!.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const header = b64url(JSON.stringify({ alg: "ES256", kid: Deno.env.get("APNS_KEY_ID") }));
  const claims = b64url(JSON.stringify({ iss: Deno.env.get("APNS_TEAM_ID"), iat: now }));
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(`${header}.${claims}`));
  cachedJwt = { token: `${header}.${claims}.${b64url(sig)}`, at: now };
  return cachedJwt.token;
}

async function sendApns(token: string, msg: Message, e: GameEvent): Promise<"ok" | "gone" | "error"> {
  const host = Deno.env.get("APNS_PRODUCTION") === "true" ? "api.push.apple.com" : "api.sandbox.push.apple.com";
  const res = await fetch(`https://${host}/3/device/${token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${await apnsJwt()}`,
      "apns-topic": Deno.env.get("APNS_BUNDLE_ID")!,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "apns-collapse-id": `${e.game_id}:${e.type}`.slice(0, 64),
    },
    body: JSON.stringify({
      aps: { alert: apsAlert(msg), sound: "default" },
      game_id: e.game_id,
      event: e.type,
    }),
  });
  if (res.ok) return "ok";
  // 410 Unregistered / 400 BadDeviceToken → xóa token
  if (res.status === 410 || (res.status === 400 && (await res.text()).includes("BadDeviceToken"))) return "gone";
  console.error("apns", res.status, await res.text().catch(() => ""));
  return "error";
}

Deno.serve(async (req) => {
  if (req.headers.get("x-webhook-secret") !== Deno.env.get("PUSH_WEBHOOK_SECRET")) {
    return new Response("unauthorized", { status: 401 });
  }
  const body = await req.json();
  const e: GameEvent | undefined = body.record;
  if (!e || body.type !== "INSERT") return new Response("ignored");

  const { data: game } = await supabase.from("games").select("title").eq("id", e.game_id).single();
  const msgs = messagesFor(e, game?.title ?? "Find Me!");
  if (msgs.length === 0) return new Response("no-op");

  let sent = 0;
  for (const msg of msgs) {
    let users = await recipients(e.game_id, msg.to);
    // Người thắng đã nhận tin riêng → không gửi thêm tin chung
    if (e.type === "hint_solved" && msg.to === "all") users = users.filter((u) => u !== e.payload.winner_id);
    if (users.length === 0) continue;
    const { data: tokens } = await supabase.from("device_tokens").select("token").in("user_id", users).eq("platform", "ios");
    const results = await Promise.all((tokens ?? []).map((t) => sendApns(t.token, msg, e).then((r) => [t.token, r] as const)));
    const gone = results.filter(([, r]) => r === "gone").map(([t]) => t);
    if (gone.length) await supabase.from("device_tokens").delete().in("token", gone);
    sent += results.filter(([, r]) => r === "ok").length;
  }
  return Response.json({ sent });
});
