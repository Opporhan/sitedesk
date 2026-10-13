import { createAdminClient } from "@/lib/supabase/admin";

// Kullanıcının kendi hesabını silmesi (mağaza şartı). Uygulama oturum anahtarını gönderir; kimlik sunucuda doğrulanır.
// Silinince: giriş hesabı, profil, profil resmi ve yönetici/danışma üyelikleri gider; sakin kayıtlarındaki hesap bağlantısı boşalır.
export async function POST(request: Request) {
  const token = request.headers.get("authorization")?.replace(/^Bearer\s+/i, "") ?? "";
  if (!token) return Response.json({ error: "Oturum bulunamadı. Yeniden giriş yapın." }, { status: 401 });
  const admin = createAdminClient();
  const { data, error } = await admin.auth.getUser(token);
  if (error || !data.user) return Response.json({ error: "Oturum bulunamadı. Yeniden giriş yapın." }, { status: 401 });

  // Sistem yöneticisi hesabı yanlışlıkla silinip sistem sahipsiz kalmasın
  const { count } = await admin.from("platform_admins").select("user_id", { count: "exact", head: true }).eq("user_id", data.user.id);
  if (count) return Response.json({ error: "Sistem yöneticisi hesabı uygulamadan silinemez." }, { status: 403 });

  // Profil resmi dosyaları da silinir (kişisel veri depoda kalmasın)
  const { data: files } = await admin.storage.from("profil").list(data.user.id, { limit: 100 });
  if (files?.length) await admin.storage.from("profil").remove(files.map((f) => `${data.user.id}/${f.name}`));

  const { error: delError } = await admin.auth.admin.deleteUser(data.user.id);
  if (delError) {
    console.error("Hesap silinemedi", delError.code);
    return Response.json({ error: "Hesap silinemedi. Lütfen tekrar deneyin." }, { status: 500 });
  }
  return Response.json({ ok: true });
}
