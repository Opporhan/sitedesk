import { createHmac } from "node:crypto";
import { createAdminClient } from "@/lib/supabase/admin";

// Davetsiz hesap açma (telefon uygulaması çağırır; uygulama ücretsiz, kullanıcı kararı 12.10.2026): ad, telefon, şifre.
// Hesap açmak tek başına hiçbir sitenin bilgisini göstermez: kişi ya kendi sitesini açar (yöneticisi olur) ya da site koduyla
// katılma isteği gönderir ve sitenin yöneticisi onaylar. Gizli anahtar sadece burada (sunucuda) kullanılır.
export async function POST(request: Request) {
  const body = (await request.json().catch(() => null)) as { fullName?: string; phone?: string; password?: string } | null;
  const fullName = String(body?.fullName ?? "").trim().replace(/\s+/g, " ");
  const phone = String(body?.phone ?? "");
  const password = String(body?.password ?? "");
  if (fullName.length < 3 || fullName.length > 100) return Response.json({ error: "Adınızı ve soyadınızı yazın." }, { status: 400 });
  if (!/^905\d{9}$/.test(phone)) return Response.json({ error: "Cep telefonu numaranızı 0532 123 45 67 gibi yazın." }, { status: 400 });
  if (password.length < 8 || password.length > 72) return Response.json({ error: "Şifre en az 8 karakter olmalı." }, { status: 400 });

  // Sahte hesap yağmuruna karşı: aynı internet adresinden saatte en fazla 20 hesap. Adres saklanmaz; gizli anahtarla
  // özeti (HMAC) 1 gün tutulur. IPv6'da bir bağlantının elinde bütün bir /64 blok olduğu için ilk 4 grup sayılır.
  const admin = createAdminClient();
  const ip = (request.headers.get("x-real-ip") ?? request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "bilinmiyor").replace(/^::ffff:/i, "");
  const ipKey = ip.includes(":") ? expandIpv6(ip).slice(0, 4).join(":") : ip;
  const ipHash = createHmac("sha256", process.env.SUPABASE_SECRET_KEY!).update(`kayit:${ipKey}`).digest("hex");
  const { data: allowed, error: limitError } = await admin.rpc("allow_signup", { p_ip_hash: ipHash });
  if (limitError) {
    console.error("Kayıt sınırı denetlenemedi", limitError.code);
    return Response.json({ error: "Hesap açılamadı. Lütfen tekrar deneyin." }, { status: 500 });
  }
  if (!allowed) return Response.json({ error: "Çok fazla deneme yapıldı. Lütfen bir saat sonra tekrar deneyin." }, { status: 429 });

  const { error } = await admin.auth.admin.createUser({
    email: `tel-${phone}@sitedesk.invalid`,
    password,
    email_confirm: true,
    user_metadata: { full_name: fullName, phone },
  });
  if (error) {
    if (error.code === "email_exists" || error.status === 422) return Response.json({ error: "Bu numarayla hesabınız zaten var. Giriş yapın." }, { status: 409 });
    if (error.code === "weak_password") return Response.json({ error: "Daha güçlü bir şifre seçin (en az 8 karakter)." }, { status: 400 });
    console.error("Kayıt açılamadı", error.code);
    return Response.json({ error: "Hesap açılamadı. Lütfen tekrar deneyin." }, { status: 500 });
  }
  return Response.json({ ok: true });
}

// "2a02:e0::1" → ["2a02","00e0","0000",…] (8 grup); "::" kısaltması açılır
function expandIpv6(ip: string): string[] {
  const [head, tail = ""] = ip.split("%")[0].split("::");
  const a = head ? head.split(":") : [];
  const b = ip.includes("::") && tail ? tail.split(":") : [];
  const groups = ip.includes("::") ? [...a, ...Array(Math.max(0, 8 - a.length - b.length)).fill("0"), ...b] : a;
  return groups.map((g) => g.toLowerCase().padStart(4, "0"));
}
