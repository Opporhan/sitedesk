import { Linking } from "react-native";
import { NETWORK_ERROR, supabase, WEB_URL } from "@/lib/supabase";

// Şifresini unutan kişiye yöneticinin WhatsApp'tan gönderdiği şifre yenileme kodu (24 saat, tek kullanımlık; SMS yok)
export async function sendPasswordReset(siteId: string, siteName: string, phone: string): Promise<string | null> {
  const { data, error } = await supabase.rpc("create_password_reset", { p_site_id: siteId, p_phone: phone });
  if (error) {
    if (error.message.includes("fetch")) return NETWORK_ERROR;
    if (error.code === "42501") return error.message.includes("başka sitelerde") ? "Bu kişi başka sitelerde de kayıtlı; şifresini sistem yöneticisi yenileyebilir." : "Bu kişinin şifresini yenileme yetkiniz yok.";
    if (error.code === "22023") return error.message.includes("hesabı yok") ? "Bu kişinin uygulama hesabı yok; şifre yerine davet gönderin." : "Bu kişi bu sitede kayıtlı değil.";
    return "Şifre kodu oluşturulamadı. Lütfen tekrar deneyin.";
  }
  const row = (data as { code: string; token: string; full_name: string }[])[0];
  const text = [
    `Merhaba ${row.full_name},`,
    "",
    "SiteDesk şifrenizi yenilemek için bağlantıya dokunun ya da uygulamada “Davet veya Şifre Kodum Var” deyip kodu yazın.",
    "",
    `Bağlantı: ${WEB_URL}/davet/${row.token}`,
    `Kod: ${row.code}`,
    "",
    "Kod 24 saat geçerlidir. Bu isteği siz yapmadıysanız dikkate almayın.",
    "",
    `${siteName} Yönetimi`,
  ].join("\n");
  Linking.openURL(`https://wa.me/${phone}?text=${encodeURIComponent(text)}`).catch(() => {});
  return null;
}
