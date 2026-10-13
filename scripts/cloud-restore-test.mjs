// Bulut yedeği denemesi: Vercel'deki günlük ŞİFRELİ yedeğin en sonuncusunu (veya verilen günü) indirir, çözer ve
// her tablonun satır sayısını canlıdakiyle karşılaştırır; bir dosyanın da çözülebildiğini dener. Canlıya DOKUNMAZ (sadece okur).
// Gerekenler (.env.local): BLOB_READ_WRITE_TOKEN, BACKUP_KEY, NEXT_PUBLIC_SUPABASE_URL, SUPABASE_SECRET_KEY
//   node --env-file=.env.local scripts/cloud-restore-test.mjs [gün: 2026-10-07]
import { createDecipheriv } from "node:crypto";
import { gunzipSync } from "node:zlib";
import { get, list } from "@vercel/blob";

const key = Buffer.from(process.env.BACKUP_KEY ?? "", "base64");
if (key.length !== 32 || !process.env.BLOB_READ_WRITE_TOKEN) {
  console.error("BACKUP_KEY veya BLOB_READ_WRITE_TOKEN .env.local içinde yok.");
  process.exit(1);
}
// lib/backup-crypto.ts ile aynı biçim: "SDB1" + IV(12) + etiket(16) + AES-256-GCM(gzip)
function decrypt(file) {
  if (file.subarray(0, 4).toString() !== "SDB1") throw new Error("Bu bir SiteDesk yedek dosyası değil");
  const d = createDecipheriv("aes-256-gcm", key, file.subarray(4, 16));
  d.setAuthTag(file.subarray(16, 32));
  return gunzipSync(Buffer.concat([d.update(file.subarray(32)), d.final()]));
}
const download = async (pathname) => Buffer.from(await new Response((await get(pathname, { access: "private", useCache: false })).stream).arrayBuffer());

const { blobs } = await list({ prefix: "yedek/", limit: 1000 });
const days = blobs.filter((b) => /^yedek\/\d{4}-\d{2}-\d{2}\.sdb$/.test(b.pathname)).sort((a, b) => a.pathname.localeCompare(b.pathname));
const chosen = process.argv[2] ? days.find((b) => b.pathname === `yedek/${process.argv[2]}.sdb`) : days.at(-1);
if (!chosen) {
  console.error("Yedek bulunamadı. Depodaki günler:", days.map((b) => b.pathname.slice(6, 16)).join(", ") || "yok");
  process.exit(1);
}
const raw = await download(chosen.pathname);
const plain = raw.subarray(0, 200).toString("utf8").includes('"tables"');
const data = JSON.parse(decrypt(raw).toString("utf8"));
console.log(`İndirilen: ${chosen.pathname} · ${raw.length} bayt · şifreli: ${plain ? "HAYIR (!)" : "evet"} · alındığı an: ${data.taken_at}`);
console.log(`İçinde: ${Object.keys(data.tables).length} tablo, ${data.auth_users.length} giriş hesabı, ${Object.keys(data.migrations).length} migration dosyası.`);

let diff = 0;
for (const [table, rows] of Object.entries(data.tables)) {
  const res = await fetch(`${process.env.NEXT_PUBLIC_SUPABASE_URL}/rest/v1/${table}?select=*`, {
    method: "HEAD",
    headers: { apikey: process.env.SUPABASE_SECRET_KEY, Authorization: `Bearer ${process.env.SUPABASE_SECRET_KEY}`, Prefer: "count=exact" },
  });
  const live = Number(res.headers.get("content-range")?.split("/")[1]);
  if (live !== rows.length) diff++;
  console.log(`  ${live === rows.length ? "=" : "≠"} ${table}: yedekte ${rows.length}, canlıda ${live}`);
}

const files = (await list({ prefix: "dosyalar/", limit: 1000 })).blobs.filter((b) => /^dosyalar\/(kayitlar|profil)\//.test(b.pathname));
if (files[0]) console.log(`Dosya denemesi: ${files[0].pathname} çözüldü (${decrypt(await download(files[0].pathname)).length} bayt). Toplam ${files.length} dosya.`);
console.log(diff ? `${diff} tabloda fark var (yedekten sonra yeni kayıt girildiyse normaldir).` : "Bütün tablolar canlıyla aynı.");
if (plain) process.exitCode = 1;
