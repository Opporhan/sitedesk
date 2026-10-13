// Uygulamanın verdiği kayıt kimliği (tekrar gönderimde ikinci kayıt açılmasın diye)
export const uuid = () =>
  "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    return (c === "x" ? r : (r & 0x3) | 0x8).toString(16);
  });

// "14:05" (Türkiye saati)
export const formatTime = (iso: string) => new Intl.DateTimeFormat("tr-TR", { hour: "2-digit", minute: "2-digit", timeZone: "Europe/Istanbul" }).format(new Date(iso));

// Türkiye saatiyle bugün mü?
export const isTodayTR = (iso: string) => {
  const f = new Intl.DateTimeFormat("tr-TR", { day: "2-digit", month: "2-digit", year: "numeric", timeZone: "Europe/Istanbul" });
  return f.format(new Date(iso)) === f.format(new Date());
};
