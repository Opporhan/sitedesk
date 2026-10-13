// Veritabanı aracı (Supabase erişim anahtarıyla, sadece bu bilgisayarda çalışır)
//   npm run db:migrate            → uygulanmamış migration dosyalarını sırayla uygular
//   npm run db:test [dosya]       → testleri (veya tek testi) çalıştırır, sonucu yazar
//   npm run db:run <dosya.sql>    → tek bir SQL dosyasını çalıştırır
import { readFileSync, readdirSync } from "node:fs";
import { basename, join } from "node:path";

const token = process.env.SUPABASE_ACCESS_TOKEN;
const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
if (!token || !url) {
  console.error("SUPABASE_ACCESS_TOKEN veya NEXT_PUBLIC_SUPABASE_URL .env.local içinde yok.");
  process.exit(1);
}
const ref = new URL(url).hostname.split(".")[0];

async function query(sql) {
  const res = await fetch(`https://api.supabase.com/v1/projects/${ref}/database/query`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({ query: sql }),
  });
  const text = await res.text();
  if (res.status === 401) throw new Error("Erişim anahtarı geçersiz veya süresi dolmuş. Supabase'den yenisini oluşturun.");
  if (!res.ok) {
    let message = text;
    try { message = JSON.parse(text).message ?? text; } catch {}
    const error = new Error(message);
    error.sqlFailed = true;
    throw error;
  }
  return JSON.parse(text);
}

const [, , command, arg] = process.argv;

if (command === "migrate") {
  await query(`
    create schema if not exists ops;
    create table if not exists ops.applied_migrations (name text primary key, applied_at timestamptz not null default now());
    revoke all on schema ops from public, anon, authenticated;`);
  const applied = new Set((await query("select name from ops.applied_migrations")).map((r) => r.name));
  const dir = "supabase/migrations";
  const pending = readdirSync(dir).filter((f) => f.endsWith(".sql") && !applied.has(f)).sort();
  if (pending.length === 0) console.log("Uygulanacak yeni veritabanı değişikliği yok.");
  for (const file of pending) {
    const sql = readFileSync(join(dir, file), "utf8");
    try {
      // Dosya ve kaydı tek işlemde: yarıda hata olursa hiçbir şey uygulanmaz
      await query(`begin;\n${sql}\n;insert into ops.applied_migrations (name) values ('${file.replace(/'/g, "''")}');\ncommit;`);
      console.log(`✓ Uygulandı: ${file}`);
    } catch (e) {
      console.error(`✗ Hata: ${file}\n  ${e.message}`);
      process.exit(1);
    }
  }
} else if (command === "mark-applied") {
  // Elle (SQL Editor'de) uygulanmış dosyaları kayda geçirir
  await query(`
    create schema if not exists ops;
    create table if not exists ops.applied_migrations (name text primary key, applied_at timestamptz not null default now());
    revoke all on schema ops from public, anon, authenticated;`);
  const files = readdirSync("supabase/migrations").filter((f) => f.endsWith(".sql")).sort();
  const values = files.map((f) => `('${f.replace(/'/g, "''")}')`).join(",");
  await query(`insert into ops.applied_migrations (name) values ${values} on conflict do nothing`);
  console.log(`${files.length} dosya "uygulandı" olarak kaydedildi.`);
} else if (command === "test") {
  const dir = "supabase/tests";
  const files = arg ? [arg] : readdirSync(dir).filter((f) => f.endsWith(".sql")).sort().map((f) => join(dir, f));
  let failed = 0;
  for (const file of files) {
    try {
      await query(readFileSync(file, "utf8"));
      console.log(`? ${basename(file)}: sonuç mesajı gelmedi`);
      failed++;
    } catch (e) {
      const match = e.message.match(/SONUÇ: (\d+) test geçti, (\d+) test kaldı\.([\s\S]*)/);
      if (!match) {
        console.log(`✗ ${basename(file)}: ${e.message}`);
        failed++;
      } else {
        const ok = match[2] === "0";
        if (!ok) failed++;
        console.log(`${ok ? "✓" : "✗"} ${basename(file)}: ${match[1]} geçti, ${match[2]} kaldı${ok ? "" : match[3]}`);
      }
    }
  }
  process.exit(failed ? 1 : 0);
} else if (command === "run" && arg) {
  try {
    console.log(JSON.stringify(await query(readFileSync(arg, "utf8")), null, 2));
  } catch (e) {
    console.error(e.message);
    process.exit(1);
  }
} else {
  console.log("Kullanım: npm run db:migrate | npm run db:test [dosya] | npm run db:run <dosya.sql>");
}
