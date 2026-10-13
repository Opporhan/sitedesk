import type { Metadata } from "next";
import Link from "next/link";
import { blank, LEGAL } from "@/lib/legal";
import { Doc, List, Note, P, Section } from "@/components/doc";

export const metadata: Metadata = {
  title: "Destek · SiteDesk",
  description: "SiteDesk uygulaması için sık sorulan sorular, şifre yenileme, hesap silme ve iletişim.",
};

const FAQ: { q: string; a: React.ReactNode }[] = [
  {
    q: "Uygulamaya nasıl girerim?",
    a: "Üç yol var. Sakinseniz: uygulamada “Siteme Katıl (Sakin)” deyin, yönetiminizin paylaştığı 6 haneli site kodunu yazıp dairenizi seçin; yönetim onaylayınca girersiniz. Size davet geldiyse: bağlantıya dokunun ya da “Davet veya Şifre Kodum Var” deyip 8 haneli kodu yazın; onay beklemeden girersiniz. Yöneticiyseniz ve siteniz uygulamada yoksa: “Sitemi Ekle (Yönetici)” ile kendiniz kurun. Sonraki girişlerde telefon numaranız ve şifrenizle girersiniz.",
  },
  {
    q: "Şifremi unuttum.",
    a: "Site yönetiminizden şifre yenileme kodu isteyin. WhatsApp'tan gelen bağlantıya dokunun ya da uygulamada “Davet veya Şifre Kodum Var” deyip kodu yazın, yeni şifrenizi belirleyin. Kod 24 saat geçerlidir. Şifre yenilenince diğer telefonlardaki oturumlarınız kapanır. (SMS gönderilmez.)",
  },
  {
    q: "Davet kodu “süresi dolmuş” diyor.",
    a: "Tek kişilik davetler 7 gün, listeden toplu gönderilen davetler 30 gün, şifre yenileme kodları 24 saat geçerlidir ve bir kez kullanılır. Yönetiminizden yeni kod isteyin.",
  },
  {
    q: "Telefon numaram değişti.",
    a: "Telefon numaranız giriş bilginizdir. Site yönetiminiz yeni numaranıza davet gönderir; eski hesabınızı uygulamadan ya da bu sitedeki hesap silme sayfasından silebilirsiniz.",
  },
  {
    q: "Taşındım; kayıtlarım ne olacak?",
    a: "Site yönetimi taşındığınızı işaretleyince eski dairenizin/villanızın kayıtlarını artık göremezsiniz. Kayıtlar sitenin kaydı olarak kalır.",
  },
  {
    q: "Bildirim gelmiyor.",
    a: "Telefonunuzun Ayarlar › Bildirimler bölümünde SiteDesk'in açık olduğundan emin olun. Uygulamadan çıkış yapıp yeniden girince bildirim izni tekrar kontrol edilir.",
  },
  {
    q: "Parmak izi / yüz tanıma kilidini nasıl kapatırım?",
    a: "Uygulamada Profil › Güvenlik bölümündeki düğmeyle. Kilit açıkken uygulama 5 dakikadan uzun arka planda kalırsa kimliğiniz yeniden sorulur.",
  },
  {
    q: "Fotoğraf ve videolarımı kim görüyor?",
    a: "Sadece sitenizin yönetimi, danışma görevlisi ve aynı dairedeki/villadaki kişiler. Videolar, kayıt tamamlandıktan sonra (varsayılan) 6 ay içinde silinir.",
  },
];

// Destek: sık sorulanlar, hesap silme ve iletişim. Mağazalar "destek adresi" olarak bu sayfayı ister.
export default function SupportPage() {
  return (
    <Doc title="Destek" lead="SiteDesk hakkında sık sorulan sorular, hesap silme ve iletişim.">
      <Note>
        Sitenizle ilgili işler (arıza, kargo, ziyaretçi, davet, şifre yenileme) için önce <strong>site yönetiminize</strong> başvurun. Uygulamayla ilgili sorunlar için bize yazabilirsiniz.
      </Note>

      <Section title="Sık sorulan sorular">
        <div className="flex flex-col gap-3">
          {FAQ.map((f) => (
            <details key={f.q} className="group rounded-xl border border-border bg-card p-4">
              <summary className="cursor-pointer list-none font-medium marker:hidden">
                <span className="flex items-center justify-between gap-4">
                  {f.q}
                  <span aria-hidden className="text-muted-foreground transition-transform group-open:rotate-45">
                    +
                  </span>
                </span>
              </summary>
              <p className="mt-3 leading-relaxed text-muted-foreground">{f.a}</p>
            </details>
          ))}
        </div>
      </Section>

      <Section title="Hesabımı nasıl silerim?" id="hesap-silme">
        <List
          items={[
            <>Uygulamada: <strong>Profil › Hesabımı Sil</strong>.</>,
            <>
              Uygulama telefonunuzda yoksa:{" "}
              <Link href="/hesap-sil" className="font-medium text-primary underline underline-offset-4">
                hesap silme sayfası
              </Link>{" "}
              (telefon numaranız ve şifrenizle).
            </>,
            <>Şifrenizi de hatırlamıyorsanız telefon numaranızla birlikte {blank(LEGAL.email, "e-posta adresi")} adresine yazın; kimliğinizi doğruladıktan sonra en geç 30 gün içinde sileriz.</>,
          ]}
        />
        <P>
          Silinenler ve kalanlar için{" "}
          <Link href="/gizlilik" className="font-medium text-primary underline underline-offset-4">
            gizlilik politikasına
          </Link>{" "}
          bakın.
        </P>
      </Section>

      <Section title="İletişim">
        <P>
          E-posta: {blank(LEGAL.email, "e-posta adresi")}
          <br />
          {blank(LEGAL.owner, "geliştirici adı / ticari unvan")} · {blank(LEGAL.city, "il")}
        </P>
      </Section>
    </Doc>
  );
}
