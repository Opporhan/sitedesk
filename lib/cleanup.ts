import "server-only";
import { createAdminClient } from "@/lib/supabase/admin";

// Günlük temizlik: tamamlanmış kayıtların videoları (sitenin saklama süresi dolunca, varsayılan 6 ay)
// ve hiçbir kayda/profile bağlanmamış 1 günden eski dosyalar (yarım kalan yüklemeler, eski profil resimleri) depodan silinir.
// Hangi dosyanın silineceğine veritabanı karar verir (files_to_purge); kayıt satırı kalır, videoda "silindi" işaretlenir.
const MAX_PER_RUN = 500;

export async function runCleanup(): Promise<{ deleted: number; videos: number }> {
  const admin = createAdminClient();
  const { data, error } = await admin.rpc("files_to_purge");
  if (error) throw new Error(`Silinecek dosyalar okunamadı: ${error.message}`);
  const files = ((data ?? []) as { bucket: string; path: string; reason: string }[]).slice(0, MAX_PER_RUN);

  let deleted = 0;
  for (const bucket of new Set(files.map((f) => f.bucket))) {
    const paths = files.filter((f) => f.bucket === bucket).map((f) => f.path);
    for (let i = 0; i < paths.length; i += 100) {
      const { data: removed, error: e } = await admin.storage.from(bucket).remove(paths.slice(i, i + 100));
      if (e) throw new Error(`${bucket} deposundan silinemedi: ${e.message}`);
      deleted += removed?.length ?? 0;
    }
  }

  const videos = files.filter((f) => f.reason === "video").map((f) => f.path);
  let marked = 0;
  if (videos.length) {
    const { data: n, error: e } = await admin.rpc("mark_media_deleted", { p_paths: videos });
    if (e) throw new Error(`Videolar işaretlenemedi: ${e.message}`);
    marked = n as number;
  }
  return { deleted, videos: marked };
}
