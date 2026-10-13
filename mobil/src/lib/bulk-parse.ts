import { normalizePhone } from "@/lib/phone";

// Toplu davet listesini okur: Excel'den kopyalanan satırlar (sütunlar sekmeyle ayrılır) ya da ";" / "," ile ayrılmış metin.
// Her satırda daire (A-1, A1, "A Blok 1"), ad soyad, telefon ve isteğe bağlı malik/kiracı aranır; sütun sırası önemli değil.
export type BulkUnit = { id: string; block: string; no: string };
export type BulkRow = {
  line: number;
  raw: string;
  unitId?: string;
  unitLabel?: string;
  name?: string;
  phone?: string;
  relation: "malik" | "kiraci";
  error?: string;
};

const upper = (s: string) => s.toLocaleUpperCase("tr-TR");
// "A Blok 12", "a-12", "A12", "Villa A12" → "A12"
export const unitKey = (s: string) =>
  upper(s)
    .replace(/BLOĞU|BLOK|DAİRE|DAIRE|VİLLA|VILLA|NUMARA|NO\b|NO:/g, "")
    .replace(/[^0-9A-ZÇĞİÖŞÜ]/g, "");

// Türkçe harfleri sadeleştirerek karşılaştırır: "kiraci", "KİRACI", "Kiracı" aynı
const fold = (s: string) => upper(s).replace(/İ/g, "I").replace(/Ş/g, "S").replace(/Ğ/g, "G").replace(/Ü/g, "U").replace(/Ö/g, "O").replace(/Ç/g, "C").replace(/\s+/g, " ").trim();
function relationOf(cell: string): "malik" | "kiraci" | null {
  const u = fold(cell);
  if (u === "K" || u.includes("KIRACI")) return "kiraci";
  if (u === "M" || u.includes("MALIK") || u.includes("MAL SAHIBI") || u.includes("EV SAHIBI")) return "malik";
  return null;
}

const looksLikePhone = (cell: string) => (cell.match(/\d/g) ?? []).length >= 10 && !/[A-Za-zÇĞİÖŞÜçğıöşü]/.test(cell);
const looksLikeName = (cell: string) => /[A-Za-zÇĞİÖŞÜçğıöşü]{2,}/.test(cell);

export function parseBulk(text: string, units: BulkUnit[], unitWord = "Daire"): BulkRow[] {
  const byKey = new Map<string, BulkUnit>();
  for (const u of units) byKey.set(unitKey(`${u.block}${u.no}`), u);

  const rows: BulkRow[] = [];
  const seen = new Set<string>();
  text.split(/\r?\n/).forEach((rawLine, i) => {
    const raw = rawLine.trim();
    if (!raw) return;
    const split = (raw.includes("\t") ? raw.split("\t") : raw.includes(";") ? raw.split(";") : raw.includes(",") ? raw.split(",") : [raw]).map((c) => c.trim()).filter(Boolean);
    // Birbirine yapışmış hücreler (PDF'te sık olur: "A Blok 2 Ayşe Kaya 0532 000 00 00") parçalara ayrılır
    const cells = split.length > 1 ? split.flatMap((c) => (isMixed(c, byKey) ? splitLoose(c) : [c])) : split;
    const row: BulkRow = { line: i + 1, raw, relation: "malik" };
    const nameParts: string[] = [];

    for (const cell of cells.length > 1 ? cells : splitLoose(raw)) {
      if (!row.phone && looksLikePhone(cell)) {
        const p = normalizePhone(cell);
        if (p) row.phone = p;
        else row.error = `Telefon anlaşılamadı: ${cell}`;
        continue;
      }
      const rel = relationOf(cell);
      if (rel && cell.length <= 12) {
        row.relation = rel;
        continue;
      }
      const unit = !row.unitId ? byKey.get(unitKey(cell)) : undefined;
      if (unit && unitKey(cell).length <= 8) {
        row.unitId = unit.id;
        row.unitLabel = `${unit.block}-${unit.no}`;
        continue;
      }
      if (looksLikeName(cell)) nameParts.push(cell);
    }
    row.name = nameParts.join(" ").replace(/\s+/g, " ").trim() || undefined;

    // Başlık ya da başlık satırı (ör. "Daire  Ad Soyad  Telefon", "Çam Evleri Sakin Listesi") sessizce atlanır
    if (!row.phone && !row.unitId && (/TELEFON|AD SOYAD|DAİRE|DAIRE|VİLLA/.test(upper(raw)) || !/\d/.test(raw))) return;
    if (!row.error) {
      if (!row.unitId) row.error = `${unitWord} bulunamadı (ör. A-1 yazın)`;
      else if (!row.phone) row.error = "Telefon yok ya da hatalı";
      else if (!row.name || row.name.length < 3) row.error = "Ad soyad eksik";
    }
    const key = `${row.unitId}|${row.phone}`;
    if (!row.error && seen.has(key)) row.error = "Listede tekrar ediyor";
    seen.add(key);
    rows.push(row);
  });
  return rows;
}

const UNIT_PREFIX = /^([A-Za-zÇĞİÖŞÜçğıöşü]{1,3}\s*(?:blok\s*)?-?\s*\d+[A-Za-z]?)\s+(.*)$/i;
// Hücre tek başına bir bilgi değil de birkaç bilginin yapışmış hali mi? (telefon + yazı ya da daire + yazı)
function isMixed(cell: string, byKey: Map<string, BulkUnit>): boolean {
  const hasLetters = /[A-Za-zÇĞİÖŞÜçğıöşü]/.test(cell);
  if (hasLetters && (cell.match(/\d/g) ?? []).length >= 10) return true;
  const m = cell.match(UNIT_PREFIX);
  return !!m && byKey.has(unitKey(m[1])) && /[A-Za-zÇĞİÖŞÜçğıöşü]{2,}/.test(m[2]);
}

// Ayraç yoksa ("A-1 Ayşe Kaya 0532 123 45 67 kiracı"): sondaki rakamlar telefon, baştaki ilk kelime(ler) daire, kalanı ad
function splitLoose(line: string): string[] {
  const phone = line.match(/(\+?\d[\d\s()-]{8,}\d)\s*(malik|kiracı|kiraci|mal sahibi)?\s*$/i);
  let rest = line;
  const out: string[] = [];
  if (phone) {
    out.push(phone[1]);
    if (phone[2]) out.push(phone[2]);
    rest = line.slice(0, phone.index).trim();
  }
  const m = rest.match(UNIT_PREFIX);
  if (m) out.push(m[1], m[2]);
  else out.push(rest);
  return out;
}
