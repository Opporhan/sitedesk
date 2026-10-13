// Biçimlendirme (Türkçe)
export const formatBytes = (b: number) => (b < 1024 * 1024 ? `${Math.round(b / 1024)} KB` : `${(b / 1024 / 1024).toFixed(1).replace(".", ",")} MB`);

// Türkiye saatiyle bugünün tarihi: "2026-10-13" (gece 00:00–03:00 arası UTC'ye göre bir gün geri yazılmasın)
export function todayTR(): string {
  const parts = new Intl.DateTimeFormat("en-US", { timeZone: "Europe/Istanbul", year: "numeric", month: "2-digit", day: "2-digit" }).formatToParts(new Date());
  const get = (t: string) => parts.find((p) => p.type === t)?.value ?? "";
  return `${get("year")}-${get("month")}-${get("day")}`;
}
// Türkiye saatiyle bu ayın 1'i 00:00 (Türkiye UTC+3, yaz saati yok)
export const monthStartTR = () => new Date(`${todayTR().slice(0, 7)}-01T00:00:00+03:00`).toISOString();
