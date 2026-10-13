import "server-only";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { del, list, put } from "@vercel/blob";
import { createAdminClient } from "@/lib/supabase/admin";
import { encryptBackup } from "@/lib/backup-crypto";

// Günlük bulut yedeği (Mac'ten bağımsız): Vercel zamanlayıcısı çağırır, yedek ŞİFRELİ olarak Vercel'in
// herkese kapalı dosya deposuna yazılır. Mac'teki haftalık yedek (scripts/backup.mjs) ikinci kopyadır.
//   yedek/2026-10-07.sdb          → bütün tablolar + giriş hesapları (şifresiz) + migration dosyaları (son 14 gün tutulur)
//   dosyalar/<depo>/<yol>.sdb     → kayıt fotoğraf/videoları ve profil resimleri (bir kez yüklenir;
//                                   depodan silinince — süresi dolan video, silinen hesap — buradan da silinir)
export const KEEP_DAYS = 14;
const PAGE = 1000;
const MAX_NEW_FILES = 40; // bir çalışmada en fazla bu kadar yeni dosya (süre sınırı); kalanı ertesi gün
const MAX_NEW_BYTES = 150 * 1024 * 1024;
const BUCKETS = ["kayitlar", "profil"];
const ACCESS = "private" as const;

const url = () => process.env.NEXT_PUBLIC_SUPABASE_URL!;
const headers = () => ({ apikey: process.env.SUPABASE_SECRET_KEY!, Authorization: `Bearer ${process.env.SUPABASE_SECRET_KEY!}` });
const todayTR = () => new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Istanbul" }).format(new Date());

async function allBlobs(prefix: string) {
  const blobs = [];
  let cursor: string | undefined;
  do {
    const page = await list({ prefix, cursor, limit: 1000 });
    blobs.push(...page.blobs);
    cursor = page.hasMore ? page.cursor : undefined;
  } while (cursor);
  return blobs;
}

// Depodaki bütün dosyalar (klasörlerin içine iner)
async function storageFiles(bucket: string, prefix = ""): Promise<{ name: string; size: number }[]> {
  const admin = createAdminClient();
  const files: { name: string; size: number }[] = [];
  for (let offset = 0; ; offset += PAGE) {
    const { data, error } = await admin.storage.from(bucket).list(prefix, { limit: PAGE, offset });
    if (error) throw new Error(`${bucket} deposu listelenemedi: ${error.message}`);
    for (const item of data ?? []) {
      const path = prefix ? `${prefix}/${item.name}` : item.name;
      if (item.id === null) files.push(...(await storageFiles(bucket, path)));
      else files.push({ name: path, size: Number(item.metadata?.size ?? 0) });
    }
    if ((data ?? []).length < PAGE) return files;
  }
}

export type BackupResult = { file: string; tables: number; rows: number; bytes: number; newFiles: number; pendingFiles: number; removedFiles: number; deleted: number };

export async function runCloudBackup(): Promise<BackupResult> {
  const key = process.env.BACKUP_KEY;
  const admin = createAdminClient();

  // Tablolar (liste veritabanından okunur: yeni tablo eklenince kendiliğinden yedeğe girer)
  const spec = await (await fetch(`${url()}/rest/v1/`, { headers: headers(), cache: "no-store" })).json();
  const names = Object.keys(spec.definitions ?? {}).sort();
  if (!names.length) throw new Error("Tablo listesi okunamadı");
  const tables: Record<string, unknown[]> = {};
  let rows = 0;
  for (const table of names) {
    const all: unknown[] = [];
    for (let from = 0; ; from += PAGE) {
      const res = await fetch(`${url()}/rest/v1/${table}?select=*`, {
        headers: { ...headers(), Range: `${from}-${from + PAGE - 1}`, Prefer: "count=exact" },
        cache: "no-store",
      });
      if (!res.ok) throw new Error(`${table}: ${res.status}`);
      const page = (await res.json()) as unknown[];
      all.push(...page);
      const total = Number(res.headers.get("content-range")?.split("/")[1]);
      if (page.length < PAGE || all.length >= total) {
        if (Number.isFinite(total) && all.length !== total) throw new Error(`${table}: ${total} satırdan ${all.length} okundu`);
        break;
      }
    }
    tables[table] = all;
    rows += all.length;
  }

  // Giriş hesapları (şifreler Supabase'de kalır, yedeğe girmez)
  const users = [];
  for (let page = 1; ; page++) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage: PAGE });
    if (error) throw new Error(`Hesaplar okunamadı: ${error.message}`);
    users.push(...data.users.map((u) => ({ id: u.id, email: u.email, user_metadata: u.user_metadata, created_at: u.created_at })));
    if (data.users.length < PAGE) break;
  }

  // Tablo yapısı: yedek tek başına geri kurulabilsin
  const dir = join(process.cwd(), "supabase/migrations");
  const migrations = Object.fromEntries(readdirSync(dir).filter((f) => f.endsWith(".sql")).sort().map((f) => [f, readFileSync(join(dir, f), "utf8")]));
  if (!Object.keys(migrations).length) throw new Error("Migration dosyaları bulunamadı");

  const day = todayTR();
  const payload = Buffer.from(JSON.stringify({ version: 2, taken_at: new Date().toISOString(), day, tables, auth_users: users, migrations }));
  const encrypted = encryptBackup(payload, key);
  const file = `yedek/${day}.sdb`;
  await put(file, encrypted, { access: ACCESS, addRandomSuffix: false, allowOverwrite: true, contentType: "application/octet-stream" });

  // Dosyalar: sadece yeniler yüklenir; depodan silinenler buradan da silinir
  let newFiles = 0;
  let newBytes = 0;
  let pendingFiles = 0;
  let removedFiles = 0;
  for (const bucket of BUCKETS) {
    const have = await allBlobs(`dosyalar/${bucket}/`);
    const haveNames = new Set(have.map((b) => b.pathname));
    const current = await storageFiles(bucket);
    const wanted = new Set(current.map((f) => `dosyalar/${bucket}/${f.name}.sdb`));
    const gone = have.filter((b) => !wanted.has(b.pathname));
    if (gone.length) await del(gone.map((b) => b.url));
    removedFiles += gone.length;
    for (const f of current) {
      const target = `dosyalar/${bucket}/${f.name}.sdb`;
      if (haveNames.has(target)) continue;
      if (newFiles >= MAX_NEW_FILES || newBytes + f.size > MAX_NEW_BYTES) {
        pendingFiles++;
        continue;
      }
      const { data, error } = await admin.storage.from(bucket).download(f.name);
      if (error || !data) throw new Error(`${bucket}/${f.name} indirilemedi`);
      await put(target, encryptBackup(Buffer.from(await data.arrayBuffer()), key), { access: ACCESS, addRandomSuffix: false, allowOverwrite: true, contentType: "application/octet-stream" });
      newFiles++;
      newBytes += f.size;
    }
  }

  // Son 14 günün yedeği tutulur
  const cutoff = new Date(Date.parse(`${day}T00:00:00Z`) - KEEP_DAYS * 86_400_000).toISOString().slice(0, 10);
  const old = (await allBlobs("yedek/")).filter((b) => /^yedek\/\d{4}-\d{2}-\d{2}\.sdb$/.test(b.pathname) && b.pathname.slice(6, 16) < cutoff);
  if (old.length) await del(old.map((b) => b.url));

  return { file, tables: names.length, rows, bytes: encrypted.length, newFiles, pendingFiles, removedFiles, deleted: old.length };
}

// En son yedeğin ne zaman alındığı (sağlık kontrolü için)
export async function lastBackupAt(): Promise<Date | null> {
  const blobs = (await allBlobs("yedek/")).filter((b) => /^yedek\/\d{4}-\d{2}-\d{2}\.sdb$/.test(b.pathname));
  if (!blobs.length) return null;
  return new Date(Math.max(...blobs.map((b) => new Date(b.uploadedAt).getTime())));
}
