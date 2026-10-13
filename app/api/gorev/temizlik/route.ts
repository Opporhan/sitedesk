import { isCron } from "@/lib/cron-auth";
import { runCleanup } from "@/lib/cleanup";

export const maxDuration = 60;

// Günlük temizlik (vercel.json → crons). Sadece CRON_SECRET ile.
export async function GET(request: Request) {
  if (!isCron(request)) return new Response("Yetkisiz", { status: 401 });
  try {
    return Response.json({ ok: true, ...(await runCleanup()) });
  } catch (error) {
    console.error("Temizlik yapılamadı", error);
    return Response.json({ ok: false, error: error instanceof Error ? error.message : "hata" }, { status: 500 });
  }
}
