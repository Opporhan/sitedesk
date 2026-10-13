import type { Metadata } from "next";
import { blank, LEGAL, WEB } from "@/lib/legal";
import { Doc, List, Note, P, Section } from "@/components/doc";

// SADECE SİZİN İÇİN (arama motorlarına kapalı, menüde bağlantısı yok): mağazalara girilecek metinler ve cevaplar.
// Şifre ya da gizli bilgi İÇERMEZ; inceleme hesaplarının şifreleri mağaza panelindeki gizli alana yazılır.
export const metadata: Metadata = { title: "Mağaza Bilgileri · SiteDesk", robots: { index: false, follow: false } };

const PLAY_NAME = "SiteDesk: Site ve Danışma";
const PLAY_SHORT = "Sitenizde arıza, kargo ve ziyaretçi takibi; sakin, danışma ve yönetim bir arada.";
const IOS_NAME = "SiteDesk";
const IOS_SUBTITLE = "Arıza, kargo ve ziyaretçi";
const IOS_KEYWORDS = "site,apartman,villa,danışma,güvenlik,kargo,ziyaretçi,arıza,talep,şikayet,sakin,yönetim,kulübe";
const IOS_PROMO = "Sitenizin danışma kulübesi ve arıza takibi artık telefonunuzda: kargonuz gelince, arızanız çözülünce ve yönetim cevap verince anında haber alın.";
const DESCRIPTION = `SiteDesk; site sakinleri, danışma görevlileri ve site yönetimini tek uygulamada buluşturur. Arıza ve talepler kaybolmaz, kargo ve ziyaretçiler kâğıda yazılmaz, herkes kendi işini telefonundan görür.

SAKİNLER İÇİN
• Arıza, talep ve şikâyetinizi fotoğraf ya da kısa videoyla bildirin; yönetimin cevabını ve işin durumunu (Yeni, İnceleniyor, Yapılıyor, Tamamlandı) adım adım izleyin.
• Kargonuz danışmaya ulaşınca telefonunuza bildirim gelsin.
• Dairenize ya da villanıza gelen ziyaretçileri görün.
• İnternet zayıfsa kaydınız telefonda bekler, bağlantı gelince kendiliğinden gönderilir.

DANIŞMA İÇİN
• Gelen kargoyu tek dokunuşla kaydedin, teslim edince işaretleyin.
• Ziyaretçi girişini ve çıkışını saniyeler içinde yazın; sakini tek dokunuşla arayın.
• Sakin adına arıza kaydı açın, durumunu güncelleyin.

YÖNETİM İÇİN
• Bütün arıza ve talepler tek listede: acil olanlar önde, blok ve türe göre süzün.
• Sakinlere cevap yazın, durumu güncelleyin; sakin anında haberdar olsun.
• Sitenizi kendiniz ekleyin; sakinler site koduyla katılır, siz onaylarsınız. İsterseniz WhatsApp'tan davet gönderin ya da Excel listesinden toplu davet edin.
• Danışma görevlilerini ve diğer yöneticileri davet edin; taşınanın erişimini kapatın.

GÜVENLİ VE SADE
• Herkes sadece kendi rolünün gerektirdiğini görür; komşular birbirinin bilgisini göremez.
• Parmak izi ya da yüz tanıma kilidi.
• Reklam yok, takip yok, bilgileriniz satılmaz.

SiteDesk tamamen ücretsizdir. Sakinler site koduyla ya da yönetimin davetiyle katılır; yönetici kendi sitesini uygulamadan ekler.`;

const REVIEW_NOTES = `SiteDesk is used by residential complexes (sites). Anyone can create an account (phone number + password) and add their own site, or join an existing site with its site code. A site's data is only visible after its manager invites the person or approves the join request, so a new account alone sees no site data.

Please sign in with the demo accounts below (phone number + password). They belong to a demo site with sample data:
• Resident (Sakin): 0500 000 01 03 — create a ticket (Arıza) with a photo, see parcels (Kargo).
• Front desk (Danışma): 0500 000 01 02 — register a parcel or a visitor, update a ticket.
• Manager (Yönetici): 0500 000 01 01 — see all tickets, reply, invite people (Kişiler).

Account deletion: Profil › Hesabımı Sil (also available on the web: ${WEB}/hesap-sil).
The app is completely free: no payments, no in-app purchases, no ads.`;

function Counted({ label, text, max }: { label: string; text: string; max: number }) {
  const over = text.length > max;
  return (
    <div className="flex flex-col gap-1.5">
      <div className="flex items-baseline justify-between gap-4">
        <span className="font-medium">{label}</span>
        <span className={`text-sm tabular-nums ${over ? "font-semibold text-borc" : "text-muted-foreground"}`}>
          {text.length} / {max}
        </span>
      </div>
      <pre className="whitespace-pre-wrap rounded-lg border border-border bg-card p-3 font-sans text-[15px] leading-relaxed">{text}</pre>
    </div>
  );
}

function Table({ head, rows }: { head: string[]; rows: string[][] }) {
  return (
    <div className="overflow-x-auto rounded-xl border border-border">
      <table className="w-full min-w-[34rem] text-left text-sm">
        <thead className="bg-muted">
          <tr>
            {head.map((h) => (
              <th key={h} className="px-3 py-2 font-semibold">
                {h}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((r, i) => (
            <tr key={i} className="border-t border-border align-top">
              {r.map((c, j) => (
                <td key={j} className="px-3 py-2">
                  {c}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export default function StoreInfoPage() {
  return (
    <Doc title="Mağaza Bilgileri" lead="Google Play ve App Store'a girilecek metinler ve cevaplar. Bu sayfa arama motorlarına kapalıdır ve menüde yoktur.">
      <Note tone="bekliyor">
        <strong>Bekleyen kararlar:</strong> geliştirici adı ({blank(LEGAL.owner, "doldurulacak")}), iletişim e-postası ({blank(LEGAL.email, "doldurulacak")}), il (
        {blank(LEGAL.city, "doldurulacak")}). Gizlilik ve destek sayfalarında iletişim GitHub üzerinden (kişisel bilgi yok).
      </Note>

      <Section title="1. Uygulama kimliği">
        <Table
          head={["Alan", "Değer"]}
          rows={[
            ["Paket adı / Bundle ID", "com.sitedesk.app (mağazaya yüklendikten sonra değişmez)"],
            ["Sürüm", "1.0.0"],
            ["Kategori (Google Play)", "Ev ve Konut (House & Home)"],
            ["Kategori (App Store)", "Birincil: Yaşam Tarzı · İkincil: Verimlilik"],
            ["Fiyat", "Tamamen ücretsiz · satın alma yok · reklam yok"],
            ["Dil", "Türkçe"],
            ["Gizlilik politikası adresi", `${WEB}/gizlilik`],
            ["Destek adresi", `${WEB}/destek`],
            ["Hesap silme adresi (Google Play)", `${WEB}/hesap-sil`],
          ]}
        />
      </Section>

      <Section title="2. Google Play metinleri">
        <Counted label="Uygulama adı" text={PLAY_NAME} max={30} />
        <Counted label="Kısa açıklama" text={PLAY_SHORT} max={80} />
        <Counted label="Tam açıklama" text={DESCRIPTION} max={4000} />
      </Section>

      <Section title="3. App Store metinleri">
        <Counted label="Ad" text={IOS_NAME} max={30} />
        <Counted label="Alt başlık" text={IOS_SUBTITLE} max={30} />
        <Counted label="Anahtar kelimeler (virgülle, boşluksuz)" text={IOS_KEYWORDS} max={100} />
        <Counted label="Tanıtım metni" text={IOS_PROMO} max={170} />
        <P>Açıklama: Google Play&apos;deki tam açıklamanın aynısı.</P>
      </Section>

      <Section title="4. Veri güvenliği (Google Play) ve gizlilik etiketi (App Store)">
        <P>
          İki mağazada da aynı cevaplar: <strong>veriler toplanıyor ama üçüncü taraflarla paylaşılmıyor</strong> (altyapı sağlayıcıları paylaşım sayılmaz),{" "}
          <strong>reklam ve takip yok</strong>, <strong>aktarım şifreli</strong>, <strong>kullanıcı silme isteyebilir</strong>.
        </P>
        <Table
          head={["Veri türü", "Ne", "Amaç", "Zorunlu mu", "Kimliğe bağlı"]}
          rows={[
            ["Ad", "Ad soyad", "Uygulama işlevi, hesap yönetimi", "Evet", "Evet"],
            ["Telefon numarası", "Giriş numarası", "Hesap yönetimi, uygulama işlevi", "Evet", "Evet"],
            ["Kullanıcı kimliği", "Hesap numarası", "Hesap yönetimi", "Evet", "Evet"],
            ["Fotoğraf ve video", "Kayıt ekleri, profil resmi", "Uygulama işlevi", "Hayır (isteğe bağlı)", "Evet"],
            ["Diğer kullanıcı içeriği", "Arıza/talep metinleri, notlar", "Uygulama işlevi", "Evet", "Evet"],
            ["Cihaz kimliği", "Bildirim adresi (push token)", "Uygulama işlevi (bildirim)", "Hayır (izinle)", "Evet"],
          ]}
        />
        <List
          items={[
            "Toplanmayanlar: konum, rehber, takvim, sağlık, finans, tarama geçmişi, reklam kimliği, çökme/analiz verisi.",
            "Ziyaretçi adı ve plakası, sakinin değil danışmanın girdiği üçüncü kişi bilgisidir; Google Play'de “Kişisel bilgi › Ad” ve “Diğer” altında belirtilir.",
            "App Store: “Data Used to Track You” → Yok. “Data Linked to You” → Contact Info (Name, Phone), User Content (Photos or Videos, Other User Content), Identifiers (User ID).",
          ]}
        />
      </Section>

      <Section title="5. Yaş sınırı anketi">
        <List
          items={[
            "Şiddet, cinsellik, küfür, kumar, uyuşturucu: Hayır.",
            "Kullanıcılar arası iletişim: Evet — sakin ile site yönetimi/danışma arasında, sadece kendi kayıtları üzerinden; herkese açık içerik ya da sohbet yok.",
            "Kullanıcının konumu paylaşılıyor mu: Hayır. Dijital satın alma: Hayır.",
            "Beklenen sonuç: Google Play “Herkes (3+)”, App Store “4+”.",
          ]}
        />
      </Section>

      <Section title="6. İzin açıklamaları (uygulamada hazır)">
        <Table
          head={["İzin", "Telefonda görünen açıklama"]}
          rows={[
            ["Kamera", "Arızanın fotoğrafını veya videosunu çekebilmeniz için kameraya erişim gerekiyor."],
            ["Galeri", "Kayda fotoğraf veya video ekleyebilmeniz için galerinize erişim gerekiyor."],
            ["Mikrofon", "Video çekerken ses kaydedilebilmesi için mikrofona erişim gerekiyor."],
            ["Yüz tanıma", "SiteDesk'e yüz tanıma ile hızlı ve güvenli giriş yapabilmeniz için."],
            ["Bildirim", "İzin istemeden önce uygulama içinde nedenini Türkçe anlatır (ör. “Kargonuz gelince… haber verelim”)."],
          ]}
        />
      </Section>

      <Section title="7. İnceleme ekibine not (İngilizce)">
        <Counted label="App Review / Google Play erişim notu" text={REVIEW_NOTES} max={4000} />
        <Note tone="bekliyor">
          Şifreler bu sayfada yazmaz; mağaza panelindeki gizli “giriş bilgileri” alanına girilir. İnceleme ekibi “Hesabımı Sil”i deneyebileceği için yayından önce demo hesapları{" "}
          <code className="rounded bg-muted px-1">scripts/demo-mobil.mjs</code> ile yeniden kurulur.
        </Note>
      </Section>

      <Section title="8. Ekran görüntüleri (çekilecek)">
        <P>
          Telefonda dikey çekilir (Google Play: 2–8 adet; App Store: 6,9 inç ekran için 1320×2868 ya da 6,5 inç için 1284×2778). Demo hesaplarıyla, açık (bej) temada, sırayla:
        </P>
        <Table
          head={["#", "Hesap", "Ekran", "Altına yazılacak cümle"]}
          rows={[
            ["1", "Sakin", "Kayıtlarım (devam eden ve tamamlanan kayıtlar)", "Arıza ve taleplerinizi tek yerden izleyin"],
            ["2", "Sakin", "Yeni kayıt (tür, fotoğraf, acil)", "Fotoğraflı bildirin, saniyeler sürer"],
            ["3", "Sakin", "Kayıt detayı (durum adımları ve yönetimin cevabı)", "Durumu adım adım görün"],
            ["4", "Sakin", "Kargo › Kargolarım", "Kargonuz gelince haberiniz olsun"],
            ["5", "Danışma", "Kargo › Yeni kargo (daire düğmeleri)", "Danışma tek dokunuşla kaydeder"],
            ["6", "Danışma", "Ziyaretçi › İçeride", "Ziyaretçi girişi ve çıkışı kayıt altında"],
            ["7", "Yönetici", "Kayıtlar (acil önde, süzgeçler, bu ayın özeti)", "Yönetim bütün kayıtları tek listede görür"],
            ["8", "Yönetici", "Kişiler › Davet", "Sakinleri WhatsApp'tan davetle ekleyin"],
          ]}
        />
        <P>Google Play ayrıca 1024×500 boyutunda bir “öne çıkan görsel” ister; hazır: <code className="rounded bg-muted px-1">magaza-gorselleri/one-cikan-1024x500.png</code> (simge: simge-512.png).</P>
      </Section>

      <Section title="9. Yayına kalan işler (beklemede)">
        <List
          items={[
            "Karar verildi: önce Android, kişisel Google Play hesabı, uygulama ücretsiz. Bekleyen: geliştirici adı, e-posta, il ve adres (lib/legal.ts).",
            "Hesaplar: Expo ve Firebase hazır; Google Play Console (25 $ bir kez) açılacak; iPhone için Apple Developer (99 $/yıl) sonra.",
            "Android deneme sürümü ve gerçek bildirim denemesi yapıldı (12.10.2026).",
            "İnceleme hesapları ve ekran görüntüleri.",
            "Google Play kapalı test (kişisel hesapta 12 kişi × 14 gün), sonra yayın.",
            "Davet sayfasında “yakında” yerine mağaza bağlantıları.",
            "Gizlilik politikasının hukukçu incelemesi.",
          ]}
        />
      </Section>
    </Doc>
  );
}
