import "server-only";
import { createAdminClient } from "@/lib/supabase/admin";
import { lastBackupAt } from "@/lib/cloud-backup";

// Günlük sağlık kontrolü: veritabanı cevap veriyor mu, zamanlanmış işlerde hata/kapalı iş var mı, telefon bildirimleri gidiyor mu,
// son 26 saatte bulut yedeği alındı mı.
// Sorun varsa sistem yöneticilerine telefon bildirimi gider. (Uygulaması silinmiş telefonlar bildirim listesinden çıkarılır.)
const BACKUP_MAX_HOURS = 26;
type Report = { cron_failed: string[]; cron_missing: string[]; push_failed: number; push_tokens_removed: number };

export async function runHealthCheck(): Promise<{ ok: boolean; problems: string[] }> {
  const admin = createAdminClient();
  const problems: string[] = [];

  const { data, error } = await admin.rpc("health_report");
  const report = data as Report | null;
  if (error || !report) problems.push("Veritabanı cevap vermiyor");
  else {
    for (const job of report.cron_failed) problems.push(`Zamanlanmış iş hata verdi: ${job}`);
    for (const job of report.cron_missing) problems.push(`Zamanlanmış iş kapalı veya yok: ${job}`);
    if (report.push_failed > 0) problems.push(`Son 24 saatte ${report.push_failed} bildirim gönderilemedi`);
  }

  try {
    const last = await lastBackupAt();
    const hours = last ? (Date.now() - last.getTime()) / 3_600_000 : Infinity;
    if (hours > BACKUP_MAX_HOURS) problems.push(last ? `Günlük yedek alınmadı (son yedek ${Math.round(hours)} saat önce)` : "Günlük yedek hiç alınmamış");
  } catch {
    problems.push("Yedek deposuna ulaşılamadı");
  }

  const ok = problems.length === 0;
  if (!ok && !error) {
    const { data: admins } = await admin.from("platform_admins").select("user_id");
    await admin.rpc("notify_users", {
      p_users: (admins ?? []).map((a) => a.user_id as string),
      p_title: `SiteDesk kontrol: ${problems.length} sorun`,
      p_body: problems.slice(0, 3).join(" · "),
      p_url: "/",
    });
  }
  return { ok, problems };
}
