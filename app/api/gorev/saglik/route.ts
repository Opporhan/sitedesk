import { isCron } from "@/lib/cron-auth";
import { runHealthCheck } from "@/lib/health";

export const maxDuration = 60;

// Günlük sağlık kontrolü (vercel.json → crons). Sadece CRON_SECRET ile.
export async function GET(request: Request) {
  if (!isCron(request)) return new Response("Yetkisiz", { status: 401 });
  return Response.json(await runHealthCheck());
}
