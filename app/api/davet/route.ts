import { createAdminClient } from "@/lib/supabase/admin";

// Davetle yeni hesap açma (telefon uygulaması çağırır). Gizli anahtar sadece burada (sunucuda) kullanılır.
// Hesap açılır ama davet BURADA kabul edilmez: uygulama yeni hesapla giriş yapıp kendi oturumuyla kabul eder (veritabanı tekrar kontrol eder).
export async function POST(request: Request) {
  const body = (await request.json().catch(() => null)) as { key?: string; phone?: string; password?: string } | null;
  const key = String(body?.key ?? "").trim();
  const phone = String(body?.phone ?? "");
  const password = String(body?.password ?? "");
  if (!key || !/^90\d{10}$/.test(phone)) return Response.json({ error: "Davet kodu veya telefon hatalı." }, { status: 400 });
  if (password.length < 8 || password.length > 72) return Response.json({ error: "Şifre en az 8 karakter olmalı." }, { status: 400 });

  const admin = createAdminClient();
  const { data: invite } = await admin
    .from("invites")
    .select("full_name, phone, used_at, cancelled_at, expires_at")
    .neq("role", "sifre")
    .or(`code.eq.${key.toUpperCase().replace(/[^A-Z0-9]/g, "")},token.eq.${key.replace(/[^a-f0-9]/g, "")}`)
    .maybeSingle();
  if (!invite || invite.used_at || invite.cancelled_at || new Date(invite.expires_at) <= new Date())
    return Response.json({ error: "Davet geçersiz veya süresi dolmuş." }, { status: 400 });
  if (invite.phone !== phone) return Response.json({ error: "Bu davet başka bir telefon numarası için." }, { status: 403 });

  const { error } = await admin.auth.admin.createUser({
    email: `tel-${phone}@sitedesk.invalid`,
    password,
    email_confirm: true,
    user_metadata: { full_name: invite.full_name, phone },
  });
  if (error) {
    if (error.code === "email_exists" || error.status === 422) return Response.json({ error: "Bu numarayla hesabınız zaten var. Şifrenizle devam edin." }, { status: 409 });
    if (error.code === "weak_password") return Response.json({ error: "Daha güçlü bir şifre seçin (en az 8 karakter)." }, { status: 400 });
    console.error("Davet hesabı açılamadı", error.code);
    return Response.json({ error: "Hesap açılamadı. Lütfen tekrar deneyin." }, { status: 500 });
  }
  return Response.json({ ok: true });
}
