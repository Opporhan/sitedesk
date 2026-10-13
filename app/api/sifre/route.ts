import { createAdminClient } from "@/lib/supabase/admin";

// Şifre yenileme (telefon uygulaması çağırır): yöneticinin WhatsApp'tan gönderdiği kod + telefon + yeni şifre.
// Kod tek kullanımlık ve 24 saat geçerli; telefon koddaki numarayla aynı olmalı. Gizli anahtar sadece burada (sunucuda).
export async function POST(request: Request) {
  const body = (await request.json().catch(() => null)) as { key?: string; phone?: string; password?: string } | null;
  const key = String(body?.key ?? "").trim();
  const phone = String(body?.phone ?? "");
  const password = String(body?.password ?? "");
  if (!key || !/^90\d{10}$/.test(phone)) return Response.json({ error: "Kod veya telefon hatalı." }, { status: 400 });
  if (password.length < 8 || password.length > 72) return Response.json({ error: "Şifre en az 8 karakter olmalı." }, { status: 400 });

  const admin = createAdminClient();
  const { data: reset } = await admin
    .from("invites")
    .select("id, phone, used_at, cancelled_at, expires_at")
    .eq("role", "sifre")
    .or(`code.eq.${key.toUpperCase().replace(/[^A-Z0-9]/g, "")},token.eq.${key.replace(/[^a-f0-9]/g, "")}`)
    .maybeSingle();
  if (!reset || reset.used_at || reset.cancelled_at || new Date(reset.expires_at) <= new Date())
    return Response.json({ error: "Kod geçersiz veya süresi dolmuş. Yönetiminizden yeni kod isteyin." }, { status: 400 });
  if (reset.phone !== phone) return Response.json({ error: "Bu kod başka bir telefon numarası için." }, { status: 403 });

  const { data: userId } = await admin.rpc("find_user_id_by_email", { p_email: `tel-${phone}@sitedesk.invalid` });
  if (!userId) return Response.json({ error: "Bu numarayla hesap bulunamadı." }, { status: 404 });
  // Önce kod kullanıldı sayılır (aynı kod iki kez çalışmasın), sonra şifre yazılır
  const { data: claimed } = await admin.from("invites").update({ used_at: new Date().toISOString() }).eq("id", reset.id).is("used_at", null).select("id");
  if (!claimed?.length) return Response.json({ error: "Bu kod kullanılmış." }, { status: 400 });
  const { error } = await admin.auth.admin.updateUserById(userId as string, { password });
  if (error) {
    await admin.from("invites").update({ used_at: null }).eq("id", reset.id); // kod yeniden denenebilsin
    if (error.code === "weak_password") return Response.json({ error: "Daha güçlü bir şifre seçin (en az 8 karakter)." }, { status: 400 });
    console.error("Şifre yenilenemedi", error.code);
    return Response.json({ error: "Şifre yenilenemedi. Lütfen tekrar deneyin." }, { status: 500 });
  }
  await admin.from("invites").update({ used_by: userId as string }).eq("id", reset.id);
  // Diğer telefonlardaki oturumlar kapanır, kişiye "şifreniz yenilendi" bildirimi gider
  const { error: closeError } = await admin.rpc("password_changed", { p_user: userId as string });
  if (closeError) console.error("Oturumlar kapatılamadı", closeError.code);
  return Response.json({ ok: true });
}
