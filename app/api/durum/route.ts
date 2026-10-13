import { createAdminClient } from "@/lib/supabase/admin";

// Dış izleme (UptimeRobot) için herkese açık durum adresi. Hiçbir veri vermez; sadece "ok" ya da "sorun".
// Düzenli çağrılması veritabanını da uyanık tutar (ücretsiz planda 7 gün hareketsiz proje duraklatılır).
export async function GET() {
  const headers = { "Cache-Control": "public, s-maxage=120", "Content-Type": "text/plain; charset=utf-8" };
  const { error } = await createAdminClient().from("sites").select("id", { head: true, count: "exact" });
  return error ? new Response("sorun", { status: 503, headers }) : new Response("ok", { headers });
}
