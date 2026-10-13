// Telefon: "0532 123 45 67", "5321234567", "+90 532 123 45 67" → "905321234567"; anlaşılmazsa null (sadece Türkiye cep/sabit)
export function normalizePhone(input: string): string | null {
  const digits = input.replace(/\D/g, "");
  if (/^5\d{9}$/.test(digits)) return `90${digits}`;
  if (/^05\d{9}$/.test(digits)) return `9${digits}`;
  if (/^905\d{9}$/.test(digits)) return digits;
  if (/^0\d{10}$/.test(digits)) return `9${digits}`;
  if (/^90\d{10}$/.test(digits)) return digits;
  return null;
}

// "905321234567" → "0532 123 45 67"
export function formatPhone(phone: string): string {
  const d = phone.replace(/^90/, "0");
  return `${d.slice(0, 4)} ${d.slice(4, 7)} ${d.slice(7, 9)} ${d.slice(9, 11)}`;
}

// Giriş: telefon ise iç adrese çevrilir (veritabanındaki public.login_email ile aynı); e-posta (sistem yöneticisi) olduğu gibi kalır
export function loginIdentifier(input: string): { email: string } | { error: string } {
  const value = input.trim();
  if (value.includes("@")) return { email: value.toLowerCase() };
  const phone = normalizePhone(value);
  return phone ? { email: `tel-${phone}@sitedesk.invalid` } : { error: "Telefon numaranızı 0532 123 45 67 gibi yazın." };
}
