import "server-only";
import { strFromU8, unzipSync } from "fflate";

// Sakin listesi dosyasını (Excel .xlsx ya da CSV) satır satır düz metne çevirir; hücreler sekmeyle ayrılır.
// Uygulamadaki okuyucu (mobil/src/lib/bulk-parse.ts) bu metni yapıştırılmış Excel gibi okur. Dosya hiçbir yerde saklanmaz.

const decodeXml = (s: string) =>
  s.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n))).replace(/&amp;/g, "&");

// "AB12" → 27 (sütun sırası, 0'dan)
function columnIndex(ref: string): number {
  const letters = ref.replace(/\d+/g, "");
  let n = 0;
  for (const ch of letters) n = n * 26 + (ch.charCodeAt(0) - 64);
  return n - 1;
}

// Hücrenin içindeki bütün <t> metinleri (zengin biçimli yazılar birden çok parça olabilir)
const textRuns = (xml: string) => [...xml.matchAll(/<t(?:\s[^>]*)?>([\s\S]*?)<\/t>/g)].map((m) => decodeXml(m[1])).join("");

export function xlsxToText(file: Uint8Array): string {
  // Açılmış hali çok büyük dosya ("zip bombası") okunmaz: sadece gereken XML'ler, toplam en fazla 50 MB
  let total = 0;
  const files = unzipSync(file, {
    filter: (f) => {
      if (!(f.name.startsWith("xl/") && f.name.endsWith(".xml"))) return false;
      total += f.originalSize;
      if (total > 50 * 1024 * 1024) throw new Error("Excel dosyası çok büyük");
      return true;
    },
  });
  const read = (name: string) => (files[name] ? strFromU8(files[name]) : "");

  const shared = [...read("xl/sharedStrings.xml").matchAll(/<si>([\s\S]*?)<\/si>/g)].map((m) => textRuns(m[1]));

  // İlk sayfa: workbook'taki ilk <sheet>'in dosyası (yoksa sheet1.xml)
  const firstRid = read("xl/workbook.xml").match(/<sheet\b[^>]*r:id="([^"]+)"/)?.[1];
  const target = firstRid ? read("xl/_rels/workbook.xml.rels").match(new RegExp(`Id="${firstRid}"[^>]*Target="([^"]+)"`))?.[1] ?? read("xl/_rels/workbook.xml.rels").match(new RegExp(`Target="([^"]+)"[^>]*Id="${firstRid}"`))?.[1] : null;
  const sheetName = target ? `xl/${target.replace(/^\/?xl\//, "").replace(/^\//, "")}` : "xl/worksheets/sheet1.xml";
  const sheet = read(sheetName) || read("xl/worksheets/sheet1.xml");
  if (!sheet) throw new Error("Excel dosyasında sayfa bulunamadı");

  const lines: string[] = [];
  for (const row of sheet.matchAll(/<row\b[^>]*>([\s\S]*?)<\/row>/g)) {
    const cells: string[] = [];
    for (const c of row[1].matchAll(/<c\b([^>]*?)(?:\/>|>([\s\S]*?)<\/c>)/g)) {
      const attrs = c[1];
      const inner = c[2] ?? "";
      const ref = attrs.match(/\br="([A-Z]+)\d+"/)?.[1];
      const type = attrs.match(/\bt="([^"]+)"/)?.[1];
      const v = inner.match(/<v>([\s\S]*?)<\/v>/)?.[1];
      let value = "";
      if (type === "s" && v !== undefined) value = shared[Number(v)] ?? "";
      else if (type === "inlineStr") value = textRuns(inner);
      else if (v !== undefined) value = decodeXml(v);
      // Telefon sayı olarak saklanmışsa bilimsel gösterim ("9.05321E+11") düz rakama çevrilir
      if (/^\d+(\.\d+)?E\+\d+$/i.test(value)) value = BigInt(Math.round(Number(value))).toString();
      const index = ref ? columnIndex(ref) : cells.length;
      cells[index] = value.replace(/[\t\r\n]+/g, " ").trim();
    }
    const line = Array.from(cells, (x) => x ?? "").join("\t").replace(/\t+$/, "");
    if (line.trim()) lines.push(line);
  }
  return lines.join("\n");
}

// CSV: UTF-8 değilse Türkçe Windows kodlaması (Excel'in "CSV olarak kaydet"i çoğu zaman böyle kaydeder)
export function csvToText(file: Uint8Array): string {
  let text: string;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(file);
  } catch {
    text = new TextDecoder("windows-1254").decode(file);
  }
  return text.replace(/^﻿/, "").replace(/\r\n?/g, "\n");
}

// PDF: sayfadaki yazı parçaları satırlara (aynı yükseklik) toplanır, soldan sağa dizilir; aralarında belirgin boşluk varsa
// ayrı sütun sayılır (sekme). Taranmış (resim) PDF'te yazı olmadığı için boş döner.
export async function pdfToText(file: Uint8Array): Promise<string> {
  const { extractTextItems } = await import("unpdf");
  const { items } = await extractTextItems(file);
  const lines: string[] = [];
  for (const page of items) {
    const rows: { y: number; parts: { x: number; end: number; str: string; size: number }[] }[] = [];
    for (const it of page) {
      if (!it.str.trim()) continue;
      const tolerance = Math.max(2, it.fontSize * 0.4);
      let row = rows.find((r) => Math.abs(r.y - it.y) <= tolerance);
      if (!row) rows.push((row = { y: it.y, parts: [] }));
      row.parts.push({ x: it.x, end: it.x + it.width, str: it.str, size: it.fontSize || 10 });
    }
    rows.sort((a, b) => b.y - a.y); // PDF'te y aşağıdan yukarı artar: üst satır önce
    for (const r of rows) {
      r.parts.sort((a, b) => a.x - b.x);
      let line = "";
      let prevEnd: number | null = null;
      for (const p of r.parts) {
        if (prevEnd !== null) line += p.x - prevEnd > p.size * 0.5 ? "\t" : p.x - prevEnd > p.size * 0.1 ? " " : "";
        line += p.str.trim();
        prevEnd = p.end;
      }
      if (line.trim()) lines.push(line.trim());
    }
  }
  return lines.join("\n");
}
