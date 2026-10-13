import { createAdminClient } from "@/lib/supabase/admin";
import { csvToText, pdfToText, xlsxToText } from "@/lib/sheet-text";

export const maxDuration = 30;

// Sakin listesi dosyasını okur (telefon uygulaması çağırır): Excel (.xlsx), CSV ya da PDF → satır satır metin.
// Uygulama dosyayı önce kapalı "listeler" deposuna kendi klasörüne yükler (en fazla 10 MB); burada okunur ve HEMEN silinir.
// Sadece giriş yapmış bir yönetici (ya da sistem yöneticisi) kullanabilir.
const MAX_BYTES = 10 * 1024 * 1024;

export async function POST(request: Request) {
  const token = request.headers.get("authorization")?.replace(/^Bearer\s+/i, "") ?? "";
  if (!token) return Response.json({ error: "Oturum bulunamadı. Yeniden giriş yapın." }, { status: 401 });
  const admin = createAdminClient();
  const { data: auth } = await admin.auth.getUser(token);
  if (!auth.user) return Response.json({ error: "Oturum bulunamadı. Yeniden giriş yapın." }, { status: 401 });

  const body = (await request.json().catch(() => null)) as { path?: string; name?: string } | null;
  const path = String(body?.path ?? "");
  const name = String(body?.name ?? "").toLowerCase();
  // Kişi sadece kendi klasöründeki dosyayı okutabilir
  if (!path.startsWith(`${auth.user.id}/`) || path.includes("..")) return Response.json({ error: "Dosya bulunamadı." }, { status: 400 });

  const bucket = admin.storage.from("listeler");
  try {
    const [{ count: managed }, { count: isAdmin }] = await Promise.all([
      admin.from("memberships").select("id", { count: "exact", head: true }).eq("user_id", auth.user.id).eq("role", "yonetici").is("ended_on", null),
      admin.from("platform_admins").select("user_id", { count: "exact", head: true }).eq("user_id", auth.user.id),
    ]);
    if (!managed && !isAdmin) return Response.json({ error: "Bu işlem için yetkiniz yok." }, { status: 403 });

    const { data: blob, error } = await bucket.download(path);
    if (error || !blob) return Response.json({ error: "Dosya bulunamadı. Tekrar seçin." }, { status: 400 });
    const file = new Uint8Array(await blob.arrayBuffer());
    if (file.length > MAX_BYTES) return Response.json({ error: "Dosya çok büyük (en fazla 10 MB)." }, { status: 400 });

    // Türü uzantıya güvenmeden içerikten anla: .xlsx "PK" (zip), PDF "%PDF" ile başlar
    const isZip = file[0] === 0x50 && file[1] === 0x4b;
    const isPdf = file[0] === 0x25 && file[1] === 0x50 && file[2] === 0x44 && file[3] === 0x46;
    if (name.endsWith(".xls") && !isZip) return Response.json({ error: "Eski Excel biçimi (.xls) okunamıyor. Dosyayı Excel'de “.xlsx olarak kaydet” ile kaydedip tekrar seçin." }, { status: 400 });
    if (/\.(docx?|pages|numbers|key|jpe?g|png|heic)$/.test(name)) return Response.json({ error: "Bu dosya türü okunamıyor. Excel (.xlsx), CSV ya da PDF seçin." }, { status: 400 });

    const text = isPdf ? await pdfToText(file) : isZip ? xlsxToText(file) : csvToText(file);
    if (!text.trim())
      return Response.json(
        { error: isPdf ? "Bu PDF'te okunabilir yazı yok (taranmış ya da resim olarak kaydedilmiş olabilir). Excel ya da CSV dosyası seçin." : "Dosyada okunacak satır bulunamadı." },
        { status: 400 }
      );
    return Response.json({ text });
  } catch (error) {
    console.error("Liste okunamadı", error instanceof Error ? error.message : error);
    return Response.json({ error: "Dosya okunamadı. Excel (.xlsx), CSV ya da PDF dosyası seçtiğinizden emin olun." }, { status: 400 });
  } finally {
    // Dosya saklanmaz: okunduktan (ya da hata verdikten) hemen sonra silinir
    await bucket.remove([path]).catch(() => {});
  }
}
