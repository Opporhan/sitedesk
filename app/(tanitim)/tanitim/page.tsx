import type { Metadata } from "next";
import Link from "next/link";
import { ArrowRight, Building2, ClipboardList, DoorOpen, EyeOff, Fingerprint, Lock, ShieldCheck, Trash2, Users, WifiOff, type LucideIcon } from "lucide-react";
import { DeskParcel, DeskVisitors, ManagerInvite, ManagerTickets, NewTicket, ResidentParcel, ResidentRecords, TicketDetail } from "@/components/app-mockups";
import { APK_URL } from "@/lib/legal";

export const metadata: Metadata = {
  title: "SiteDesk · Site danışma, arıza, kargo ve ziyaretçi takibi",
  description:
    "Sakin arızayı fotoğrafla bildirir, yönetim adım adım çözer; danışma kargoyu ve ziyaretçiyi saniyeler içinde kaydeder, sakine anında haber gider. Ücretsiz Android uygulaması.",
};

// Ekranlar telefon çerçevesinde yan yana; dar ekranda yatay kaydırılır (sayfa değil, sadece bu şerit)
function Phones({ children }: { children: React.ReactNode }) {
  return (
    <div className="-mx-4 overflow-x-auto px-4 pb-6 [scrollbar-width:thin] sm:mx-0 sm:px-0">
      <div className="flex w-max snap-x snap-mandatory gap-6 sm:w-auto sm:flex-wrap sm:justify-center [&>*]:snap-center">{children}</div>
    </div>
  );
}

function Feature({ items }: { items: string[] }) {
  return (
    <ul className="flex flex-col gap-3">
      {items.map((x) => (
        <li key={x} className="flex gap-3 leading-relaxed">
          <span aria-hidden className="mt-2 size-2 shrink-0 rounded-full bg-primary" />
          <span>{x}</span>
        </li>
      ))}
    </ul>
  );
}

function RoleSection({ id, eyebrow, title, lead, items, children, tint }: { id: string; eyebrow: string; title: string; lead: string; items: string[]; children: React.ReactNode; tint?: boolean }) {
  return (
    <section id={id} className={`scroll-mt-4 py-16 sm:py-24 ${tint ? "bg-card" : ""}`}>
      <div className="mx-auto flex w-full max-w-6xl flex-col gap-10 px-4">
        <div className="mx-auto flex max-w-2xl flex-col gap-4 text-center">
          <span className="text-sm font-semibold tracking-widest text-primary">{eyebrow}</span>
          <h2 className="text-3xl font-bold tracking-tight text-balance sm:text-4xl">{title}</h2>
          <p className="text-lg text-muted-foreground text-pretty">{lead}</p>
        </div>
        <div className="mx-auto w-full max-w-2xl">
          <Feature items={items} />
        </div>
        <Phones>{children}</Phones>
      </div>
    </section>
  );
}

const ROLES: { href: string; icon: LucideIcon; title: string; text: string }[] = [
  { href: "#sakin", icon: ClipboardList, title: "Sakin", text: "Arızayı fotoğrafla bildirir, durumunu izler; kargosu gelince haber alır." },
  { href: "#danisma", icon: DoorOpen, title: "Danışma", text: "Kargoyu ve ziyaretçiyi tek dokunuşla kaydeder, sakini arar." },
  { href: "#yonetim", icon: Users, title: "Yönetim", text: "Bütün kayıtları tek listede görür, cevap verir, kişileri davet eder." },
];

const SAFETY: { icon: LucideIcon; title: string; text: string }[] = [
  { icon: EyeOff, title: "Komşular birbirini görmez", text: "Sakin sadece kendi dairesinin kayıtlarını görür. Başka site hiçbir şey göremez; kurallar veritabanında uygulanır." },
  { icon: Fingerprint, title: "Parmak izi / yüz tanıma", text: "Uygulama açılırken ve uzun süre sonra geri dönünce kimlik sorulur." },
  { icon: Lock, title: "Fotoğraflar kapalı depoda", text: "Fotoğraf ve videolar herkese kapalıdır; sadece yetkili kişiye birkaç dakikalık bağlantıyla açılır." },
  { icon: WifiOff, title: "İnternet yoksa kaybolmaz", text: "Zayıf bağlantıda kayıt telefonda bekler, internet gelince kendiliğinden gönderilir." },
  { icon: ShieldCheck, title: "Reklam ve takip yok", text: "Bilgiler satılmaz, reklam gösterilmez. Her gün şifreli yedek alınır." },
  { icon: Trash2, title: "Gereksiz bilgi tutulmaz", text: "Ziyaretçi kayıtları 1 yıl, kapanan kayıtların videoları 6 ay sonra kendiliğinden silinir." },
];

const STEPS = [
  { title: "Yönetici sitesini ekler", text: "Uygulamada “Sitemi Ekle” der; bloklar ve daireler/villalar girilir. Hepsi birkaç dakika sürer." },
  { title: "Sakinler katılır", text: "Yönetici site kodunu WhatsApp grubuna paylaşır ya da davet gönderir; sakin dairesini seçer, yönetici onaylar. SMS ya da e-posta gerekmez." },
  { title: "Herkes telefonundan kullanır", text: "SiteDesk herkes için tamamen ücretsizdir; telefon numarası ve kendi şifrenizle girersiniz. Şu an sadece Android için." },
];

export default function LandingPage() {
  return (
    <>
      {/* Giriş */}
      <section className="overflow-hidden">
        <div className="mx-auto grid w-full max-w-6xl items-center gap-12 px-4 py-14 sm:py-20 lg:grid-cols-[1.1fr_1fr]">
          <div className="flex flex-col gap-6">
            <a href={APK_URL} className="inline-flex w-fit items-center gap-2 rounded-full bg-[var(--vurgu-acik)] px-3 py-1 text-sm font-medium text-primary hover:underline">
              <Building2 className="size-4" aria-hidden /> Ücretsiz · Android uygulamasını indir
            </a>
            <h1 className="text-4xl font-bold tracking-tight text-balance sm:text-5xl">Sitenizin danışma kulübesi ve arıza takibi tek uygulamada</h1>
            <p className="text-lg leading-relaxed text-muted-foreground text-pretty">
              Sakin arızayı fotoğrafla bildirir, yönetim adım adım çözer. Danışma kargoyu ve ziyaretçiyi saniyeler içinde kaydeder, sakine anında haber gider. Kâğıt defter ve WhatsApp
              grubunda kaybolan mesaj yok.
            </p>
            <div className="flex flex-wrap gap-3">
              <a href="#nasil" className="inline-flex h-12 items-center gap-2 rounded-lg bg-primary px-6 text-base font-medium text-primary-foreground hover:bg-primary/90 focus-visible:outline-none focus-visible:ring-3 focus-visible:ring-ring/50">
                Nasıl çalışır? <ArrowRight className="size-4" aria-hidden />
              </a>
              <Link href="/destek" className="inline-flex h-12 items-center rounded-lg border border-border bg-card px-6 text-base font-medium hover:bg-muted focus-visible:outline-none focus-visible:ring-3 focus-visible:ring-ring/50">
                Bilgi alın
              </Link>
            </div>
          </div>
          <div className="flex justify-center lg:-rotate-2">
            <ResidentRecords />
          </div>
        </div>
      </section>

      {/* Kimin için */}
      <section className="border-y border-border bg-card">
        <div className="mx-auto grid w-full max-w-6xl gap-4 px-4 py-10 sm:grid-cols-3">
          {ROLES.map((r) => (
            <a key={r.title} href={r.href} className="group flex gap-4 rounded-2xl p-4 hover:bg-muted focus-visible:outline-none focus-visible:ring-3 focus-visible:ring-ring/50">
              <span className="flex size-11 shrink-0 items-center justify-center rounded-xl bg-[var(--vurgu-acik)] text-primary">
                <r.icon className="size-5" aria-hidden />
              </span>
              <span className="flex flex-col gap-1">
                <span className="font-semibold">{r.title}</span>
                <span className="text-sm leading-relaxed text-muted-foreground">{r.text}</span>
              </span>
            </a>
          ))}
        </div>
      </section>

      <RoleSection
        id="sakin"
        eyebrow="SAKİN OLARAK"
        title="Arızanızı bildirin, gerisini telefonunuzdan izleyin"
        lead="Kime söyleyeceğinizi, söyleyip söylemediğinizi düşünmeyin. Kaydınız yönetime gider, her adımda size haber verilir."
        items={[
          "Arıza, talep ya da şikâyetinizi 5 fotoğraf ya da 30 saniyelik bir videoyla bildirin; acilse işaretleyin.",
          "Kaydınızın durumunu adım adım görün: Yeni, İnceleniyor, Yapılıyor, Tamamlandı. Yönetimin cevabı da burada.",
          "İş bitince “Evet, Çözüldü” ya da “Hayır, Sorun Devam Ediyor” deyin; devam ediyorsa kayıt yeniden yönetimin önüne düşer.",
          "Kargonuz danışmaya ulaşınca, kaydınızın durumu değişince ve yönetim cevap yazınca telefonunuza bildirim gelir.",
          "Dairenize gelen ziyaretçileri ve kargolarınızı görün.",
        ]}
      >
        <NewTicket />
        <TicketDetail />
        <ResidentParcel />
      </RoleSection>

      <RoleSection
        id="danisma"
        tint
        eyebrow="DANIŞMA GÖREVLİSİ OLARAK"
        title="Kulübede defter devri bitti"
        lead="Büyük düğmeler, en az dokunuş. Yoğun saatte bile kargo ve ziyaretçi birkaç saniyede kayda girer."
        items={[
          "Kargo gelince daireye dokunun, “Kaydet” deyin: sakine telefon bildirimi gider. Uygulamayı kullanmayan sakine tek dokunuşla WhatsApp mesajı.",
          "Teslim ederken kime verildiğini seçin; yanlışlıkla basarsanız aynı gün geri alın.",
          "Ziyaretçinin adı ve isteğe bağlı plakası; giriş saati kendiliğinden yazılır, çıkışta tek dokunuş.",
          "Ziyaretçiyi içeri almadan önce sakini uygulamadan tek dokunuşla arayın.",
          "Sakin telefonla ya da kulübeye gelip söylediğinde onun adına arıza kaydı açın, durumunu güncelleyin.",
        ]}
      >
        <DeskParcel />
        <DeskVisitors />
      </RoleSection>

      <RoleSection
        id="yonetim"
        eyebrow="YÖNETİM OLARAK"
        title="Sitenizde ne oluyor, tek bakışta görün"
        lead="Hangi arıza açık, hangisi gecikti, kim ne zaman cevap verdi; hepsi kayıt altında ve elinizin altında."
        items={[
          "Bütün arıza ve talepler tek listede: acil olanlar en üstte. Türe, bloğa ve acile göre süzün.",
          "Bu ayın özeti: kaç kayıt açıldı, kaçı tamamlandı, ortalama kaç günde çözüldü.",
          "Kaydın durumunu değiştirin, sakine cevap yazın; sakin anında haberdar olur. Acil kayıt gelince telefonunuza bildirim düşer.",
          "Sakinleri ve danışma görevlilerini WhatsApp'tan davetle ekleyin; taşınanın ya da ayrılanın erişimini tek dokunuşla kapatın.",
          "Şifresini unutana şifre yenileme kodu gönderin; sakin bilgilerini düzeltin, blok ve daireleri yönetin.",
          "Her değişiklik işlem geçmişine yazılır: kim, ne zaman, ne yaptı.",
        ]}
      >
        <ManagerTickets />
        <ManagerInvite />
      </RoleSection>

      {/* Güvenlik */}
      <section className="bg-card py-16 sm:py-24">
        <div className="mx-auto flex w-full max-w-6xl flex-col gap-10 px-4">
          <div className="mx-auto flex max-w-2xl flex-col gap-4 text-center">
            <span className="text-sm font-semibold tracking-widest text-primary">GÜVENLİK VE GİZLİLİK</span>
            <h2 className="text-3xl font-bold tracking-tight text-balance sm:text-4xl">Herkes sadece görmesi gerekeni görür</h2>
          </div>
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {SAFETY.map((s) => (
              <div key={s.title} className="flex flex-col gap-3 rounded-2xl border border-border bg-background p-5">
                <span className="flex size-10 items-center justify-center rounded-xl bg-[var(--vurgu-acik)] text-primary">
                  <s.icon className="size-5" aria-hidden />
                </span>
                <span className="font-semibold">{s.title}</span>
                <span className="text-sm leading-relaxed text-muted-foreground">{s.text}</span>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Nasıl başlanır */}
      <section id="nasil" className="scroll-mt-4 py-16 sm:py-24">
        <div className="mx-auto flex w-full max-w-6xl flex-col gap-10 px-4">
          <div className="mx-auto flex max-w-2xl flex-col gap-4 text-center">
            <span className="text-sm font-semibold tracking-widest text-primary">NASIL BAŞLANIR?</span>
            <h2 className="text-3xl font-bold tracking-tight text-balance sm:text-4xl">Üç adımda sitenizde</h2>
          </div>
          <ol className="grid gap-4 sm:grid-cols-3">
            {STEPS.map((s, i) => (
              <li key={s.title} className="flex flex-col gap-3 rounded-2xl border border-border bg-card p-6">
                <span className="flex size-10 items-center justify-center rounded-full bg-primary text-lg font-bold text-primary-foreground">{i + 1}</span>
                <span className="text-lg font-semibold">{s.title}</span>
                <span className="leading-relaxed text-muted-foreground">{s.text}</span>
              </li>
            ))}
          </ol>
        </div>
      </section>

      {/* Son çağrı */}
      <section className="px-4 pb-20">
        <div className="mx-auto flex w-full max-w-4xl flex-col items-center gap-5 rounded-3xl bg-primary px-6 py-12 text-center text-primary-foreground">
          <h2 className="text-3xl font-bold tracking-tight text-balance">SiteDesk&apos;i sitenizde kullanmak ister misiniz?</h2>
          <p className="max-w-xl text-lg opacity-90 text-pretty">Tamamen ücretsiz. Site yönetiminize önerin ya da bize yazın; birlikte gösterelim.</p>
          <Link href="/destek" className="inline-flex h-12 items-center gap-2 rounded-lg bg-primary-foreground px-6 text-base font-medium text-primary hover:opacity-90 focus-visible:outline-none focus-visible:ring-3 focus-visible:ring-ring/50">
            Bize ulaşın <ArrowRight className="size-4" aria-hidden />
          </Link>
        </div>
      </section>
    </>
  );
}
