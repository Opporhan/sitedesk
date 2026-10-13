import { isCron } from "@/lib/cron-auth";
import { runCloudBackup } from "@/lib/cloud-backup";

export const maxDuration = 60;

// Günlük bulut yedeği: Vercel zamanlayıcısı her gün çağırır (vercel.json → crons). Sadece CRON_SECRET ile.
export async function GET(request: Request) {
  if (!isCron(request)) return new Response("Yetkisiz", { status: 401 });
  try {
    return Response.json({ ok: true, ...(await runCloudBackup()) });
  } catch (error) {
    console.error("Bulut yedeği alınamadı", error);
    // Ayrıntı sadece sunucu kaydında; sabahki sağlık kontrolü "yedek alınmadı" diye bildirir
    return Response.json({ ok: false, error: error instanceof Error ? error.message : "hata" }, { status: 500 });
  }
}
