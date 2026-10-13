// Ek demo siteleri (kullanıcı isteği 08.10.2026): demo yöneticisi birden çok siteyi yönetsin, "Sitelerim" ekranı denensin.
// Kullanım (önce demo-mobil.mjs): node --env-file=.env.local scripts/demo-siteler.mjs
// • "Demo Villa Sitesi" (villa, A ve B blok × 5 villa) ve "Demo Rezidans" (apartman, A–F 6 blok × 8 daire); ikisi de is_demo.
// • Demo yöneticisi (0500 000 01 01) ikisine de yönetici olarak bağlanır; demo danışma (0500 000 01 02) Demo Rezidans'ta da
//   danışmadır (5'ten fazla bloklu sitede danışma ekranı denensin). Örnek arıza/talep, kargo ve ziyaretçi eklenir.
// Tekrar çalıştırılabilir: site varsa yeniden kurmaz. Gerçek sitelere dokunmaz.
import { createClient } from "@supabase/supabase-js";
import { randomUUID } from "node:crypto";

const admin = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL, process.env.SUPABASE_SECRET_KEY, { auth: { persistSession: false } });
const must = (r, what) => {
  if (r.error) throw new Error(`${what}: ${r.error.message}`);
  return r.data;
};
const ago = (h) => new Date(Date.now() - h * 3600 * 1000).toISOString();

const managerId = must(await admin.rpc("find_user_id_by_email", { p_email: "tel-905000000101@sitedesk.invalid" }), "yönetici arama");
const deskId = must(await admin.rpc("find_user_id_by_email", { p_email: "tel-905000000102@sitedesk.invalid" }), "danışma arama");
if (!managerId) throw new Error("Demo yöneticisi yok; önce scripts/demo-mobil.mjs çalıştırın.");

const SITES = [
  {
    name: "Demo Villa Sitesi",
    type: "villa",
    blocks: { A: 5, B: 5 },
    tickets: [
      { unit: "A-2", kind: "ariza", title: "Havuz pompası çalışmıyor", urgent: true, status: "alindi", h: 2 },
      { unit: "B-4", kind: "ariza", title: "Bahçe sulaması bozuk", urgent: false, status: "yapiliyor", h: 30 },
      { unit: "A-5", kind: "talep", title: "Çatı oluğu temizliği", urgent: false, status: "alindi", h: 50 },
      { unit: "B-1", kind: "sikayet", title: "Gece gürültü", urgent: false, status: "tamamlandi", h: 120 },
    ],
    packages: ["A-1", "B-3"],
    visitors: [{ unit: "A-3", name: "Peyzaj firması", plate: "35PYZ34" }],
  },
  {
    name: "Demo Rezidans",
    type: "apartman",
    blocks: { A: 8, B: 8, C: 8, D: 8, E: 8, F: 8 },
    desk: true,
    tickets: [
      { unit: "C-6", kind: "ariza", title: "Asansör 4. katta kaldı", urgent: true, status: "inceleniyor", h: 1 },
      { unit: "A-3", kind: "ariza", title: "Mutfak lavabosu tıkalı", urgent: false, status: "alindi", h: 5 },
      { unit: "B-7", kind: "ariza", title: "Koridor lambası yanmıyor", urgent: false, status: "alindi", h: 20 },
      { unit: "A-8", kind: "oneri", title: "Otoparka bisiklet yeri", urgent: false, status: "inceleniyor", h: 70 },
      { unit: "C-2", kind: "talep", title: "Kapı kartı yenileme", urgent: false, status: "tamamlandi", h: 96 },
    ],
    packages: ["A-1", "A-4", "B-2", "C-8"],
    visitors: [
      { unit: "B-5", name: "Selin Aydın", plate: null },
      { unit: "C-1", name: "Kombi servisi", plate: "34SRV77" },
    ],
  },
];

for (const def of SITES) {
  let site = must(await admin.from("sites").select("id").eq("name", def.name).eq("is_demo", true).maybeSingle(), "site");
  const fresh = !site;
  if (!site) site = must(await admin.from("sites").insert({ name: def.name, type: def.type, is_demo: true }).select("id").single(), "site ekleme");
  const units = {};
  for (const [b, count] of Object.entries(def.blocks)) {
    let block = must(await admin.from("blocks").select("id").eq("site_id", site.id).eq("name", b).maybeSingle(), "blok");
    if (!block) block = must(await admin.from("blocks").insert({ site_id: site.id, name: b }).select("id").single(), "blok ekleme");
    for (let n = 1; n <= count; n++) {
      let unit = must(await admin.from("units").select("id").eq("block_id", block.id).eq("no", String(n)).maybeSingle(), "birim");
      if (!unit) unit = must(await admin.from("units").insert({ site_id: site.id, block_id: block.id, no: String(n), type: def.type === "villa" ? "villa" : "daire" }).select("id").single(), "birim ekleme");
      units[`${b}-${n}`] = unit.id;
    }
  }
  const m = must(await admin.from("memberships").select("id").eq("user_id", managerId).eq("site_id", site.id).eq("role", "yonetici").is("ended_on", null).maybeSingle(), "üyelik");
  if (!m) must(await admin.from("memberships").insert({ user_id: managerId, site_id: site.id, role: "yonetici" }), "üyelik ekleme");
  if (def.desk && deskId) {
    const d = must(await admin.from("memberships").select("id").eq("user_id", deskId).eq("site_id", site.id).eq("role", "danisma").is("ended_on", null).maybeSingle(), "danışma üyeliği");
    if (!d) must(await admin.from("memberships").insert({ user_id: deskId, site_id: site.id, role: "danisma" }), "danışma üyeliği ekleme");
  }

  if (fresh) {
    for (const t of def.tickets) {
      must(
        await admin.from("tickets").insert({
          site_id: site.id, unit_id: units[t.unit], client_id: randomUUID(), kind: t.kind, location: "daire", title: t.title, urgent: t.urgent,
          status: t.status, created_by_role: "yonetici", created_at: ago(t.h), updated_at: ago(t.h), closed_at: t.status === "tamamlandi" ? ago(t.h - 24) : null,
        }),
        "kayıt ekleme"
      );
    }
    for (const u of def.packages) must(await admin.from("packages").insert({ site_id: site.id, unit_id: units[u], client_id: randomUUID(), received_at: ago(3) }), "kargo ekleme");
    for (const v of def.visitors) must(await admin.from("visitors").insert({ site_id: site.id, unit_id: units[v.unit], client_id: randomUUID(), visitor_name: v.name, plate: v.plate, arrived_at: ago(1) }), "ziyaretçi ekleme");
  }
  console.log(`${def.name}: ${Object.keys(units).length} birim, yönetici bağlı${fresh ? ", örnek kayıtlar eklendi" : " (zaten vardı)"}`);
}
