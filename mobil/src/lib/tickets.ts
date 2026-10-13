// Kayıt (arıza / talep / şikâyet) türleri ve Türkçe adları — veritabanı: public.tickets
export type TicketKind = "ariza" | "talep" | "sikayet";
export type TicketStatus = "alindi" | "inceleniyor" | "yapiliyor" | "tamamlandi";
export type TicketLocation = "daire" | "ortak";

export type Ticket = {
  id: string;
  site_id: string;
  unit_id: string;
  kind: TicketKind;
  location: TicketLocation;
  title: string;
  description: string | null;
  urgent: boolean;
  status: TicketStatus;
  resolution: "cozuldu" | "devam" | null;
  created_by_role: "sakin" | "danisma" | "yonetici";
  created_at: string;
  updated_at: string;
  closed_at: string | null;
};

export type TicketEvent = {
  id: string;
  kind: "not" | "durum" | "sonuc";
  body: string | null;
  status: string | null;
  author_name: string | null;
  author_role: "sakin" | "danisma" | "yonetici";
  created_at: string;
};

export type TicketMedia = { id: string; kind: "foto" | "video"; path: string; deleted_at: string | null };

export const KIND_LABEL: Record<TicketKind, string> = { ariza: "Arıza", talep: "Talep", sikayet: "Şikâyet" };
export const LOCATION_LABEL: Record<TicketLocation, string> = { daire: "Dairem", ortak: "Ortak alan" };
export const STATUS_LABEL: Record<TicketStatus, string> = { alindi: "Yeni", inceleniyor: "İnceleniyor", yapiliyor: "Yapılıyor", tamamlandi: "Tamamlandı" };
export const STATUS_ORDER: TicketStatus[] = ["alindi", "inceleniyor", "yapiliyor", "tamamlandi"];
export const ROLE_LABEL = { sakin: "Sakin", danisma: "Danışma", yonetici: "Yönetim" } as const;

export const TICKET_COLUMNS = "id, site_id, unit_id, kind, location, title, description, urgent, status, resolution, created_by_role, created_at, updated_at, closed_at";

// "06.10.2026 14:05" (Türkiye saati)
export function formatDateTime(iso: string): string {
  return new Intl.DateTimeFormat("tr-TR", { day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "Europe/Istanbul" }).format(new Date(iso));
}

// Durum rozetinin rengi: Yeni (mavi), süren (turuncu), tamamlandı (yeşil)
export const statusTone = (t: Pick<Ticket, "status">) => (t.status === "tamamlandi" ? "basari" : t.status === "alindi" ? "bilgi" : "bekliyor") as "basari" | "bilgi" | "bekliyor";
