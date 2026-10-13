import type { Metadata } from "next";
import Link from "next/link";
import { CONTACT_URL, LEGAL } from "@/lib/legal";
import { Doc, DraftBanner, List, P, Section } from "@/components/doc";

export const metadata: Metadata = {
  title: "Gizlilik Politikası · SiteDesk",
  description: "SiteDesk uygulamasında hangi kişisel verilerin, neden ve ne kadar süre tutulduğu (KVKK aydınlatma metni).",
  robots: LEGAL.reviewed ? undefined : { index: false },
};

// Gizlilik politikası ve KVKK aydınlatma metni (TASLAK — hukukçu incelemesi bekliyor). Mağazalar bu sayfanın adresini ister.
export default function PrivacyPage() {
  return (
    <Doc title="Gizlilik Politikası ve KVKK Aydınlatma Metni" lead={`Son güncelleme: ${LEGAL.updated}`}>
      {!LEGAL.reviewed && <DraftBanner />}

      <Section title="1. Kısaca">
        <List
          items={[
            "SiteDesk; site sakinleri, danışma görevlileri ve site yönetimi arasında arıza/talep, kargo ve ziyaretçi takibi için kullanılan bir telefon uygulamasıdır.",
            "Sadece bu işler için gereken bilgileri tutarız. Reklam göstermeyiz, sizi takip etmeyiz, bilgilerinizi satmayız.",
            "Uygulama ücretsizdir. Hesabınızı site yönetiminizin davetiyle ya da kendiniz açarsınız; bir sitenin bilgilerini görebilmeniz için o sitenin yönetiminin sizi davet etmesi ya da katılma isteğinizi onaylaması gerekir.",
            "Hesabınızı istediğiniz zaman uygulamadan ya da bu sitedeki hesap silme sayfasından silebilirsiniz.",
          ]}
        />
      </Section>

      <Section title="2. Veri sorumlusu kim?">
        <P>
          Sitenizdeki sakin, daire/villa, arıza, kargo ve ziyaretçi bilgilerinin <strong>veri sorumlusu sitenizin yönetimidir</strong>; bu bilgileri hangi amaçla tuttuğuna yönetim karar
          verir. SiteDesk (ücretsiz, açık kaynak bir proje) bu bilgileri yönetim adına ve onun talimatıyla işleyen{" "}
          <strong>veri işleyendir</strong>. Uygulama hesabınızın kendisi (giriş bilgileri) için SiteDesk veri sorumlusudur.
        </P>
        <P>
          İletişim: <a href={CONTACT_URL} className="font-medium text-primary underline underline-offset-4">GitHub üzerinden</a> (kişisel bilgilerinizi oraya yazmayın).
        </P>
      </Section>

      <Section title="3. Hangi bilgileri tutuyoruz?">
        <List
          items={[
            <><strong>Hesap:</strong> adınız soyadınız ve cep telefonu numaranız. Şifreniz şifrelenmiş olarak saklanır; biz dahil kimse göremez. Telefon numaranız SMS ile doğrulanmaz; site yönetimi katılma isteğini onaylamadan önce sizi arayarak doğrulayabilir.</>,
            <><strong>Profil resmi</strong> (isteğe bağlı): yüklerseniz, sadece sitenizin görevlileri ve aynı dairedeki kişiler görür.</>,
            <><strong>Daire/villa bilgisi:</strong> blok ve numara, malik ya da kiracı olduğunuz, taşınma tarihi.</>,
            <><strong>Arıza, talep ve şikâyet kayıtları:</strong> başlık, açıklama, eklediğiniz fotoğraf ya da video, yazışmalar, durum geçmişi ve kimin yazdığı.</>,
            <><strong>Kargo kayıtları:</strong> hangi daireye geldiği, geliş ve teslim zamanı, teslim alan kişinin adı.</>,
            <><strong>Ziyaretçi kayıtları:</strong> ziyaretçinin adı, isteğe bağlı araç plakası, gittiği daire, giriş ve çıkış saati.</>,
            <><strong>Katılma isteği:</strong> site koduyla katılmak isterseniz adınız, telefonunuz, seçtiğiniz daire/villa ve malik/kiracı bilgisi; sitenin yönetimi görür ve onaylar ya da reddeder.</>,
            <><strong>Sakin listesi dosyası:</strong> yönetim sakinleri toplu davet etmek için Excel, CSV ya da PDF dosyası yüklerse dosya sadece okunur ve hemen silinir (en geç 1 saat içinde).</>,
            <><strong>Hesap açma denemesi:</strong> sahte hesap açılmasını önlemek için bağlandığınız internet adresinin geri çözülemeyen özeti 1 gün tutulur; adresin kendisi saklanmaz.</>,
            <><strong>Bildirim kimliği:</strong> telefonunuza bildirim gönderebilmek için telefonunuzun bildirim adresi (izin verirseniz).</>,
            <><strong>İşlem geçmişi:</strong> güvenlik için kimin, ne zaman, hangi kaydı (blok, daire, sakin, görevli, davet, arıza kaydı) eklediği ya da değiştirdiği. Kargo ve ziyaretçi işlemleri bu geçmişe yazılmaz.</>,
          ]}
        />
        <P>
          <strong>Tutmadıklarımız:</strong> konumunuz, rehberiniz, reklam kimliğiniz, kart veya banka bilgileriniz. Parmak izi ve yüz tanıma telefonunuzda kalır, bize hiç gelmez.
        </P>
      </Section>

      <Section title="4. Neden tutuyoruz? (amaç ve hukuki sebep)">
        <List
          items={[
            "Arıza ve taleplerinizin yönetime iletilmesi, takibi ve size haber verilmesi.",
            "Danışmaya gelen kargonun kaydı ve size haber verilmesi.",
            "Siteye giren ziyaretçilerin kaydı (site güvenliği).",
            "Hesabınıza güvenli giriş, şifre yenileme ve hesabın korunması.",
          ]}
        />
        <P>
          Hukuki sebepler (KVKK m.5/2): hizmetin sunulması için gerekli olması (c), site yönetiminin ve sakinlerin güvenliği için meşru menfaat (f) ve yönetimin kanuni
          yükümlülükleri (ç).
        </P>
      </Section>

      <Section title="5. Kimler görebilir?">
        <List
          items={[
            "Sakin: sadece kendi dairesinin/villasının kayıtlarını, kargolarını ve ziyaretçilerini görür. Komşularının bilgilerini göremez.",
            "Danışma görevlisi: sitenin kargo, ziyaretçi ve arıza kayıtlarını; sakinlerin adını ve telefonunu (aramak için) görür.",
            "Site yönetimi: kendi sitesinin arıza, talep ve şikâyet kayıtlarını ve tamir, servis gibi iş için yapılan girişleri görür. Kargoları ve sakinlerin misafirlerini sadece danışma ve ilgili evin sakini görür.",
            "Daireye yeni taşınan kişi, kendisinden önce oturanların açtığı arıza ve talep kayıtlarını, kargolarını ve ziyaretçilerini göremez.",
            "Başka bir sitenin kullanıcıları sizin sitenizin hiçbir bilgisini göremez. Bu kural uygulamada değil, veritabanında uygulanır.",
            "SiteDesk'in sistem yöneticisi, destek ve güvenlik için bütün sitelerin arıza kayıtlarını ve kişi listelerini görebilir; kargoları ve sakinlerin misafirlerini göremez.",
          ]}
        />
      </Section>

      <Section title="6. Bilgiler nerede saklanıyor, kimlere aktarılıyor?">
        <P>Bilgileriniz sadece hizmeti sunmak için kullandığımız altyapı sağlayıcılarına aktarılır:</P>
        <List
          items={[
            <><strong>Supabase</strong>: veritabanı ve dosyalar (sunucu: Avrupa Birliği, Almanya/Frankfurt).</>,
            <><strong>Vercel</strong>: web sitesi ve sunucu işlemleri (sunucu: Avrupa Birliği, Almanya/Frankfurt) ile günlük şifreli yedekler (Vercel Blob deposu).</>,
            <><strong>Expo, Google (Firebase) ve Apple</strong>: telefon bildirimlerinin iletilmesi (ABD). Bildirimde sadece kısa başlık ve daire/villa etiketi bulunur.</>,
          ]}
        />
        <P>
          Bu sağlayıcıların bir kısmı yurt dışındadır; aktarım bu hizmeti sunmak için yapılır. Davet ve şifre yenileme mesajları site yönetiminin
          kendi WhatsApp hesabından gönderilir; SiteDesk WhatsApp&apos;a bilgi göndermez.
        </P>
      </Section>

      <Section title="7. Ne kadar süre saklıyoruz?">
        <List
          items={[
            "Ziyaretçi kayıtları: 1 yıl sonra kendiliğinden silinir.",
            "İşlem geçmişi: 1 yıl sonra kendiliğinden silinir.",
            "Hesap açma denemesi (internet adresinin özeti): 1 gün sonra silinir. Yüklenen sakin listesi dosyası: okunur okunmaz silinir.",
            "Videolar: kayıt tamamlandıktan sonra site yönetiminin belirlediği süre (varsayılan 6 ay) dolunca silinir, yedeklerden de kaldırılır.",
            "Yedekler: şifreli olarak 14 gün tutulur, sonra silinir.",
            "Hesabınızı silerseniz: giriş bilgileriniz, profiliniz ve profil resminiz silinir. Sitenin kaydı olan arıza/kargo kayıtları ve bu kayıtlardaki yazar adı, site yönetiminin hizmeti sürdüğü sürece kalır.",
            "Site yönetimi hizmeti bırakırsa sitenin bilgileri, yönetimin talimatına göre teslim edilir ve silinir.",
          ]}
        />
      </Section>

      <Section title="8. Güvenlik">
        <List
          items={[
            "Bütün bağlantılar şifrelidir (HTTPS). Yedekler AES-256 ile şifrelenir.",
            "Fotoğraf ve videolar herkese kapalı depoda durur; sadece yetkili kişiye birkaç dakikalık süreli bağlantıyla gösterilir.",
            "Herkes sadece kendi rolünün gerektirdiğini görebilir; bu kurallar düzenli olarak otomatik testlerle denenir.",
            "Uygulamaya parmak izi ya da yüz tanıma kilidi konabilir.",
          ]}
        />
      </Section>

      <Section title="9. Haklarınız (KVKK m.11)">
        <P>
          Bilgilerinizin işlenip işlenmediğini öğrenme, bilgi isteme, düzeltilmesini ya da silinmesini isteme, aktarıldığı kişileri öğrenme, itiraz etme ve zarara uğradıysanız
          giderilmesini isteme haklarınız vardır. Sitenizdeki kayıtlarla ilgili istekleriniz için önce site yönetiminize, hesabınızla ilgili istekleriniz için <a href={CONTACT_URL} className="font-medium text-primary underline underline-offset-4">GitHub üzerinden</a>{" "}
          yazabilirsiniz (kişisel bilgilerinizi herkese açık kayda yazmayın). Başvurular en geç 30 gün içinde cevaplanır.
        </P>
        <P>
          Hesabınızı hemen silmek için: uygulamada <strong>Profil › Hesabımı Sil</strong> ya da{" "}
          <Link href="/hesap-sil" className="font-medium text-primary underline underline-offset-4">
            hesap silme sayfası
          </Link>
          .
        </P>
      </Section>

      <Section title="10. Çocuklar">
        <P>SiteDesk 18 yaşından büyükler için tasarlanmıştır.</P>
      </Section>

      <Section title="11. Değişiklikler">
        <P>Bu metin değişirse güncel hali bu sayfada yayımlanır ve sayfanın başındaki tarih güncellenir.</P>
      </Section>
    </Doc>
  );
}
