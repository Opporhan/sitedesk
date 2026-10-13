import "server-only";

// Zamanlanmış adresler dışarıdan çağrılamaz: Vercel zamanlayıcısı CRON_SECRET'i "Authorization: Bearer …" olarak gönderir.
// Anahtar tanımlı değilse hiç kimse çağıramaz ("Bearer undefined" kabul edilmez).
export function isCron(request: Request): boolean {
  const secret = process.env.CRON_SECRET;
  return !!secret && secret.length >= 16 && request.headers.get("authorization") === `Bearer ${secret}`;
}
