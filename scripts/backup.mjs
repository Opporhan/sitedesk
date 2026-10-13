// Veritabanı yedeği (sadece bu bilgisayarda çalışır, sadece okur)
//   npm run yedek              → bütün tabloları ve kullanıcı hesaplarını iCloud Drive > SiteDesk Yedekler/<tarih>/ içine JSON olarak yazar
//   node scripts/backup.mjs --gerekirse → sadece bugün pazartesiyse (ve bugün alınmadıysa) ya da son yedek 7 günden
//                                eskiyse alır; Mac'teki zamanlanmış görev bunu her gün ve açılışta çalıştırır
// Tablo yapısı supabase/migrations/ içinde; geri yükleme = migration'lar + bu dosyalar.
import { appendFileSync, cpSync, existsSync, mkdirSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const key = process.env.SUPABASE_SECRET_KEY;
const root = join(homedir(), "Library/Mobile Documents/com~apple~CloudDocs/SiteDesk Yedekler");
const PAGE = 1000;
// Tablo değil, hesaplanan görünümler (şu an yok; eklenirse buraya yazılır, yedeğe alınmaz)
const COMPUTED = new Set([]);
// Dosya depoları (her biri "SiteDesk Yedekler/<depo>/" klasöründe birikir)
const BUCKETS = ["kayitlar", "profil"]; // arıza/talep fotoğraf-videoları ve profil resimleri

const stamp = new Intl.DateTimeFormat("sv-SE", {
  timeZone: "Europe/Istanbul", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit",
}).format(new Date()).replace(" ", "_").replace(":", "-");
const log = (line) => {
  mkdirSync(root, { recursive: true });
  appendFileSync(join(root, "yedek-gunlugu.txt"), `${stamp}  ${line}\n`);
  console.log(line);
};

async function get(path, headers = {}) {
  const res = await fetch(`${url}${path}`, { headers: { apikey: key, Authorization: `Bearer ${key}`, ...headers } });
  if (!res.ok) throw new Error(`${path}: ${res.status} ${await res.text()}`);
  return res;
}

// Depodaki bütün dosyaların yolları (klasörlerin içine iner)
async function listFiles(bucket, prefix) {
  const names = [];
  for (let offset = 0; ; offset += PAGE) {
    const res = await fetch(`${url}/storage/v1/object/list/${bucket}`, {
      method: "POST",
      headers: { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      body: JSON.stringify({ prefix, limit: PAGE, offset }),
    });
    if (!res.ok) throw new Error(`depo listesi: ${res.status} ${await res.text()}`);
    const page = await res.json();
    for (const item of page) {
      const path = prefix ? `${prefix}/${item.name}` : item.name;
      if (item.id === null) names.push(...(await listFiles(bucket, path))); // klasör
      else names.push(path);
    }
    if (page.length < PAGE) return names;
  }
}

// Son başarılı yedeğin günü (klasör adı "2026-10-05_10-00", içinde BILGI.txt varsa başarılıdır)
function lastBackupDay() {
  if (!existsSync(root)) return null;
  return readdirSync(root).filter((d) => /^\d{4}-\d{2}-\d{2}_/.test(d) && existsSync(join(root, d, "BILGI.txt"))).sort().pop()?.slice(0, 10) ?? null;
}

if (process.argv.includes("--gerekirse")) {
  const today = stamp.slice(0, 10);
  const last = lastBackupDay();
  const age = last ? (Date.parse(today) - Date.parse(last)) / 86_400_000 : Infinity;
  const monday = new Date(`${today}T12:00:00Z`).getUTCDay() === 1;
  if (!((monday && last !== today) || age >= 7)) process.exit(0);
}

try {
  if (!url || !key) throw new Error("NEXT_PUBLIC_SUPABASE_URL veya SUPABASE_SECRET_KEY .env.local içinde yok.");
  const spec = await (await get("/rest/v1/")).json();
  const tables = Object.keys(spec.definitions ?? {}).filter((t) => !COMPUTED.has(t)).sort();
  if (!tables.length) throw new Error("Tablo listesi okunamadı.");
  const dir = join(root, stamp);
  mkdirSync(dir, { recursive: true });

  const counts = [];
  for (const table of tables) {
    const rows = [];
    for (let from = 0; ; from += PAGE) {
      const res = await get(`/rest/v1/${table}?select=*`, { Range: `${from}-${from + PAGE - 1}`, Prefer: "count=exact" });
      const page = await res.json();
      rows.push(...page);
      const total = Number(res.headers.get("content-range")?.split("/")[1]);
      if (page.length < PAGE || rows.length >= total) {
        if (Number.isFinite(total) && rows.length !== total) throw new Error(`${table}: ${total} satırdan ${rows.length} okundu`);
        break;
      }
    }
    writeFileSync(join(dir, `${table}.json`), JSON.stringify(rows, null, 1));
    counts.push(`${table}: ${rows.length}`);
  }

  // Giriş hesapları (şifreler Supabase'de kalır, yedeğe girmez)
  const users = [];
  for (let page = 1; ; page++) {
    const { users: batch = [] } = await (await get(`/auth/v1/admin/users?page=${page}&per_page=${PAGE}`)).json();
    users.push(...batch.map((u) => ({ id: u.id, email: u.email, user_metadata: u.user_metadata, created_at: u.created_at })));
    if (batch.length < PAGE) break;
  }
  writeFileSync(join(dir, "auth_users.json"), JSON.stringify(users, null, 1));
  counts.push(`auth_users: ${users.length}`);

  // Dosyalar (arıza fotoğraf/videoları, profil resimleri) değişmez; depo adındaki ortak klasöre sadece yeniler indirilir
  for (const bucket of BUCKETS) {
    const files = await listFiles(bucket, "");
    let fresh = 0;
    for (const name of files) {
      const target = join(root, bucket, name);
      if (existsSync(target)) continue;
      const res = await get(`/storage/v1/object/${bucket}/${name.split("/").map(encodeURIComponent).join("/")}`);
      mkdirSync(dirname(target), { recursive: true });
      writeFileSync(target, Buffer.from(await res.arrayBuffer()));
      fresh++;
    }
    // Depodan silinen dosyalar (süresi dolan videolar, hesabı silinenin profil resmi) yedekten de silinir
    const keep = new Set(files);
    const walk = (d, rel = "") => existsSync(d) ? readdirSync(d, { withFileTypes: true }).flatMap((e) => e.isDirectory() ? walk(join(d, e.name), rel + e.name + "/") : [rel + e.name]) : [];
    let removed = 0;
    for (const name of walk(join(root, bucket))) if (!keep.has(name)) { rmSync(join(root, bucket, name)); removed++; }
    counts.push(`${bucket} deposu: ${files.length} dosya (yeni indirilen: ${fresh}, depodan silindiği için yedekten silinen: ${removed}) → SiteDesk Yedekler/${bucket}/`);
  }

  // Tablo yapısı (migration dosyaları) da yedeğin içinde dursun: yedek tek başına geri kurulabilsin
  const migrations = join(dirname(fileURLToPath(import.meta.url)), "../supabase/migrations");
  cpSync(migrations, join(dir, "migrations"), { recursive: true });
  counts.push(`migration dosyası: ${readdirSync(migrations).length} → migrations/`);

  writeFileSync(
    join(dir, "BILGI.txt"),
    `SiteDesk yedeği — ${stamp}\nHer tablo ayrı JSON dosyasında. Tablo yapısı bu klasördeki migrations/ içinde.\nGeri kurma denemesi: proje klasöründe scripts/restore-test.mjs (başındaki açıklamaya bakın).\nYedekte OLMAYANLAR: giriş şifreleri (herkes "Şifremi unuttum" ile yeniler), .env.local içindeki anahtarlar.\n\n${counts.join("\n")}\n`
  );
  log(`TAMAM  ${tables.length} tablo yedeklendi → ${stamp}`);
} catch (error) {
  log(`HATA   ${error.message}`);
  // Mac'te bildirim: yedek alınamadı (ayrıntı yedek-gunlugu.txt'de)
  spawnSync("osascript", ["-e", 'display notification "Ayrıntı: iCloud Drive > SiteDesk Yedekler > yedek-gunlugu.txt" with title "SiteDesk yedeği alınamadı"']);
  process.exit(1);
}
