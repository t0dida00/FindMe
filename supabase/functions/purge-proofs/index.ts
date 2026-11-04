// Edge Function "purge-proofs": xóa ảnh proof sau proof_retention_days ngày kể từ khi game kết thúc.
// Chạy hằng ngày (xem README: pg_cron + pg_net), gọi với header Authorization: Bearer <CRON_SECRET>.
import { createClient } from "npm:@supabase/supabase-js@2.49.4";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);

Deno.serve(async (req) => {
  if (req.headers.get("authorization") !== `Bearer ${Deno.env.get("CRON_SECRET")}`) {
    return new Response("unauthorized", { status: 401 });
  }

  let purged = 0;
  for (let round = 0; round < 20; round++) {
    const { data, error } = await supabase.rpc("claim_proofs_to_purge", { p_limit: 500 });
    if (error) return Response.json({ error: error.message, purged }, { status: 500 });
    const paths = (data ?? []).map((r: { photo_path: string }) => r.photo_path);
    if (paths.length === 0) break;

    // Storage API xóa tối đa 1000 file mỗi lần
    const { error: rmError } = await supabase.storage.from("proofs").remove(paths);
    if (rmError) return Response.json({ error: rmError.message, purged }, { status: 500 });

    const { data: n, error: markError } = await supabase.rpc("mark_proofs_purged", { p_paths: paths });
    if (markError) return Response.json({ error: markError.message, purged }, { status: 500 });
    purged += n ?? 0;
  }
  return Response.json({ purged });
});
