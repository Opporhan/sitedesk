// Demo sitesi ve deneme hesapları (telefon uygulaması; mağaza inceleme ekibi de bunları kullanır).
// Kullanım: node --env-file=.env.local scripts/demo-mobil.mjs
// • "Demo Sitesi" (is_demo): A ve B blok, her birinde 6 daire. Gerçek sitelere dokunmaz.
// • Üç hesap: yönetici, danışma, sakin (A-1). Telefonlar uydurma ve kimseye mesaj gitmez.
// • Şifreler kodda YAZMAZ: .env.local'daki DEMO_*_SIFRE kullanılır; yoksa rastgele üretilip .env.local'a yazılır.
// Tekrar çalıştırılabilir: site/hesap varsa yeniden kurmaz, şifreleri .env.local'daki değerlere döndürür.
import { createClient } from "@supabase/supabase-js";
import { randomInt } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";

const admin = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL, process.env.SUPABASE_SECRET_KEY, { auth: { persistSession: false } });
const must = (r, what) => {
  if (r.error) throw new Error(`${what}: ${r.error.message}`);
  return r.data;
};

// Okunması kolay rastgele şifre (karışan harfler yok): ör. "kmt7-rhu4-pz2b"
const ALPHABET = "abcdefghjkmnpqrstuvwxyz23456789";
const randomPassword = () => Array.from({ length: 3 }, () => Array.from({ length: 4 }, () => ALPHABET[randomInt(ALPHABET.length)]).join("")).join("-");
const passwordFor = (key) => process.env[`DEMO_${key}_SIFRE`] || randomPassword();

const ACCOUNTS = [
  { key: "YONETICI", phone: "905000000101", name: "Demo Yönetici", role: "yonetici" },
  { key: "DANISMA", phone: "905000000102", name: "Demo Danışma", role: "danisma" },
  { key: "SAKIN", phone: "905000000103", name: "Demo Sakin", role: "sakin" },
].map((a) => ({ ...a, password: passwordFor(a.key) }));

// Site, bloklar, daireler
let site = must(await admin.from("sites").select("id").eq("name", "Demo Sitesi").eq("is_demo", true).maybeSingle(), "site");
if (!site) site = must(await admin.from("sites").insert({ name: "Demo Sitesi", type: "apartman", is_demo: true }).select("id").single(), "site ekleme");
const units = {};
for (const b of ["A", "B"]) {
  let block = must(await admin.from("blocks").select("id").eq("site_id", site.id).eq("name", b).maybeSingle(), "blok");
  if (!block) block = must(await admin.from("blocks").insert({ site_id: site.id, name: b }).select("id").single(), "blok ekleme");
  for (let n = 1; n <= 6; n++) {
    let unit = must(await admin.from("units").select("id").eq("block_id", block.id).eq("no", String(n)).maybeSingle(), "daire");
    if (!unit) unit = must(await admin.from("units").insert({ site_id: site.id, block_id: block.id, no: String(n), type: "daire" }).select("id").single(), "daire ekleme");
    units[`${b}-${n}`] = unit.id;
  }
}

// Hesaplar
const env = {};
for (const a of ACCOUNTS) {
  const email = `tel-${a.phone}@sitedesk.invalid`;
  const pw = a.password;
  const existing = must(await admin.rpc("find_user_id_by_email", { p_email: email }), "hesap arama");
  let userId = existing;
  if (userId) must(await admin.auth.admin.updateUserById(userId, { password: pw }), "şifre yenileme");
  else userId = must(await admin.auth.admin.createUser({ email, password: pw, email_confirm: true, user_metadata: { full_name: a.name, phone: a.phone } }), "hesap açma").user.id;

  if (a.role === "sakin") {
    let res = must(await admin.from("residents").select("id").eq("site_id", site.id).eq("phone", a.phone).maybeSingle(), "sakin");
    if (!res) res = must(await admin.from("residents").insert({ site_id: site.id, full_name: a.name, phone: a.phone, user_id: userId }).select("id").single(), "sakin ekleme");
    const link = must(await admin.from("unit_residents").select("id").eq("resident_id", res.id).eq("unit_id", units["A-1"]).is("ended_on", null).maybeSingle(), "bağlantı");
    if (!link) must(await admin.from("unit_residents").insert({ site_id: site.id, unit_id: units["A-1"], resident_id: res.id, relation: "malik" }), "bağlantı ekleme");
  } else {
    const m = must(await admin.from("memberships").select("id").eq("user_id", userId).eq("site_id", site.id).eq("role", a.role).is("ended_on", null).maybeSingle(), "üyelik");
    if (!m) must(await admin.from("memberships").insert({ user_id: userId, site_id: site.id, role: a.role }), "üyelik ekleme");
  }
  env[`DEMO_${a.key}_TEL`] = a.phone;
  env[`DEMO_${a.key}_SIFRE`] = pw;
}

// Şifreler sadece .env.local'a (git'e girmez); ekrana yazılmaz
let file = readFileSync(".env.local", "utf8");
for (const [k, v] of Object.entries(env)) {
  const line = `${k}=${v}`;
  file = new RegExp(`^${k}=.*$`, "m").test(file) ? file.replace(new RegExp(`^${k}=.*$`, "m"), () => line) : `${file.trimEnd()}\n${line}\n`;
}
writeFileSync(".env.local", file);
console.log(`Demo Sitesi hazır: 2 blok, ${Object.keys(units).length} daire, 3 hesap (şifreler .env.local içinde: DEMO_*_SIFRE).`);
