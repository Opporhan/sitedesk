import {
  Bell,
  Camera,
  Check,
  ChevronLeft,
  ClipboardList,
  DoorOpen,
  Images,
  MessageCircle,
  MessageSquareWarning,
  Package,
  Plus,
  Send,
  SlidersHorizontal,
  User,
  UserPlus,
  Users,
  Video,
  Wrench,
  type LucideIcon,
} from "lucide-react";

// Tanıtım sayfasındaki telefon ekranları: uygulamanın gerçek ekranlarının aynısı, aynı renklerle (app/globals.css ile
// mobil/src/theme.tsx aynı) ve demo bilgileriyle çizilir. Gerçek kişi bilgisi içermez.

type Tone = "bilgi" | "bekliyor" | "basari" | "hata" | "notr";
const TONE: Record<Tone, string> = {
  bilgi: "bg-[var(--bilgi-zemin)] text-[var(--bilgi)]",
  bekliyor: "bg-[var(--bekliyor-zemin)] text-[var(--bekliyor)]",
  basari: "bg-[var(--odendi-zemin)] text-[var(--odendi)]",
  hata: "bg-[var(--borc-zemin)] text-[var(--borc)]",
  notr: "bg-[var(--kutu-koyu)] text-[var(--yazi-soluk)]",
};

function Pill({ label, tone }: { label: string; tone: Tone }) {
  return <span className={`shrink-0 rounded-full px-2 py-0.5 text-[10px] font-semibold ${TONE[tone]}`}>{label}</span>;
}

function Title({ title, subtitle }: { title: string; subtitle?: string }) {
  return (
    <div className="flex flex-col gap-0.5 px-1">
      <span className="text-[20px] font-bold leading-tight tracking-tight">{title}</span>
      {subtitle && <span className="text-[11px] text-[var(--yazi-soluk)]">{subtitle}</span>}
    </div>
  );
}

function Label({ children }: { children: React.ReactNode }) {
  return <span className="px-1 text-[9.5px] font-semibold tracking-wider text-[var(--yazi-soluk)]">{children}</span>;
}

function Group({ children }: { children: React.ReactNode }) {
  return <div className="flex flex-col divide-y divide-[var(--cizgi)] overflow-hidden rounded-[14px] bg-[var(--kutu)]">{children}</div>;
}

function Row({ title, subtitle, right, bar }: { title: string; subtitle?: string; right?: React.ReactNode; bar?: boolean }) {
  return (
    <div className="relative flex items-center gap-2 px-3 py-2.5">
      {bar && <span className="absolute inset-y-2 left-0 w-[3px] rounded-r bg-[var(--borc)]" />}
      <div className="flex min-w-0 flex-1 flex-col gap-0.5">
        <span className="truncate text-[12px] font-semibold">{title}</span>
        {subtitle && <span className="truncate text-[10px] text-[var(--yazi-soluk)]">{subtitle}</span>}
      </div>
      {right}
    </div>
  );
}

function Segmented({ items, active = 0 }: { items: string[]; active?: number }) {
  return (
    <div className="flex gap-1 rounded-[12px] bg-[var(--kutu-koyu)] p-1">
      {items.map((x, i) => (
        <span
          key={x}
          className={`flex-1 truncate rounded-[9px] py-1.5 text-center text-[10.5px] font-semibold ${i === active ? "bg-[var(--kutu)] text-[var(--yazi)] shadow-sm" : "text-[var(--yazi-soluk)]"}`}
        >
          {x}
        </span>
      ))}
    </div>
  );
}

function MainButton({ label, icon: Icon }: { label: string; icon?: LucideIcon }) {
  return (
    <div className="flex h-10 items-center justify-center gap-1.5 rounded-[12px] bg-[var(--vurgu)] text-[12px] font-semibold text-[var(--vurgu-yazi)]">
      {Icon && <Icon className="size-3.5" strokeWidth={2.25} />}
      {label}
    </div>
  );
}

function Tabs({ items, active }: { items: { label: string; icon: LucideIcon }[]; active: number }) {
  return (
    <div className="absolute inset-x-0 bottom-0 flex rounded-t-[20px] bg-[var(--kutu)] px-2 pb-4 pt-2 shadow-[0_-4px_16px_rgba(43,31,20,0.08)]">
      {items.map((t, i) => (
        <div key={t.label} className={`flex flex-1 flex-col items-center gap-0.5 ${i === active ? "text-[var(--vurgu)]" : "text-[var(--yazi-soluk)]"}`}>
          <span className={`flex h-6 w-11 items-center justify-center rounded-full ${i === active ? "bg-[var(--vurgu-acik)]" : ""}`}>
            <t.icon className="size-4" strokeWidth={i === active ? 2.25 : 1.75} />
          </span>
          <span className="text-[9px] font-semibold">{t.label}</span>
        </div>
      ))}
    </div>
  );
}

const SAKIN_TABS = [
  { label: "Kayıtlarım", icon: ClipboardList },
  { label: "Kargo", icon: Package },
  { label: "Profil", icon: User },
];
const DANISMA_TABS = [
  { label: "Kargo", icon: Package },
  { label: "Ziyaretçi", icon: DoorOpen },
  { label: "Arıza", icon: Wrench },
  { label: "Profil", icon: User },
];
const YONETICI_TABS = [
  { label: "Kayıtlar", icon: ClipboardList },
  { label: "Hizmet", icon: Wrench },
  { label: "Kişiler", icon: Users },
  { label: "Profil", icon: User },
];

// Telefon çerçevesi
export function Phone({ children, label }: { children: React.ReactNode; label: string }) {
  return (
    <figure aria-label={label} className="w-[272px] shrink-0 rounded-[44px] border border-[var(--cizgi)] bg-[#1d1915] p-[9px] shadow-[0_24px_60px_-20px_rgba(43,31,20,0.45)]">
      <div className="relative h-[560px] overflow-hidden rounded-[36px] bg-[var(--zemin)] text-[var(--yazi)]">
        <div className="flex items-center justify-between px-6 pb-1 pt-3 text-[10px] font-semibold">
          <span>09:41</span>
          <span className="h-[18px] w-[72px] rounded-full bg-[#1d1915]" />
          <span className="flex items-center gap-1">
            <span className="h-[7px] w-[14px] rounded-[2px] border border-current" />
          </span>
        </div>
        <div className="flex flex-col gap-3 px-3.5 pt-2">{children}</div>
      </div>
    </figure>
  );
}

// ——— Sakin ———
export function ResidentRecords() {
  return (
    <Phone label="Sakin: Kayıtlarım ekranı">
      <Title title="Kayıtlarım" subtitle="A-1 · Demo Sitesi" />
      <Label>DEVAM EDENLER</Label>
      <Group>
        <Row title="Banyo musluğu damlatıyor" subtitle="Arıza · Bugün 09:12" right={<Pill label="Yapılıyor" tone="bekliyor" />} />
        <Row title="Otopark lambası yanmıyor" subtitle="Arıza · Acil · Dün 21:40" right={<Pill label="Yeni" tone="bilgi" />} />
        <Row title="Bahçe sulaması geç saatte" subtitle="Talep · 03.10.2026" right={<Pill label="İnceleniyor" tone="bekliyor" />} />
      </Group>
      <Label>TAMAMLANANLAR</Label>
      <Group>
        <Row title="Kapı kolu gevşemiş" subtitle="Talep · 28.09.2026" right={<Pill label="Tamamlandı" tone="basari" />} />
        <Row title="Asansör sesi" subtitle="Şikâyet · 21.09.2026" right={<Pill label="Tamamlandı" tone="basari" />} />
      </Group>
      <div className="absolute inset-x-3.5 bottom-[74px]">
        <MainButton label="Yeni kayıt" icon={Plus} />
      </div>
      <Tabs items={SAKIN_TABS} active={0} />
    </Phone>
  );
}

export function NewTicket() {
  const kinds: { label: string; icon: LucideIcon; on?: boolean }[] = [
    { label: "Arıza", icon: Wrench, on: true },
    { label: "Talep", icon: ClipboardList },
    { label: "Şikâyet", icon: MessageSquareWarning },
  ];
  return (
    <Phone label="Sakin: Yeni kayıt ekranı">
      <span className="flex items-center gap-1 text-[12px] font-medium text-[var(--vurgu)]">
        <ChevronLeft className="size-4" /> Geri
      </span>
      <Title title="Yeni kayıt" />
      <Label>NE BİLDİRMEK İSTİYORSUNUZ?</Label>
      <div className="grid grid-cols-3 gap-1.5">
        {kinds.map((k) => (
          <div
            key={k.label}
            className={`flex h-12 flex-col items-center justify-center gap-0.5 rounded-[12px] border-2 text-[10.5px] font-semibold ${k.on ? "border-[var(--vurgu)] bg-[var(--vurgu-acik)]" : "border-transparent bg-[var(--kutu)]"}`}
          >
            <k.icon className="size-3.5 text-[var(--vurgu)]" />
            {k.label}
          </div>
        ))}
      </div>
      <Segmented items={["Dairem", "Ortak alan"]} />
      <div className="flex flex-col gap-1">
        <span className="px-1 text-[10px] font-medium text-[var(--yazi-soluk)]">Başlık</span>
        <div className="rounded-[12px] border-2 border-[var(--vurgu)] bg-[var(--kutu)] px-3 py-2 text-[12px]">Banyo musluğu damlatıyor</div>
      </div>
      <div className="flex gap-1.5">
        <div className="size-14 overflow-hidden rounded-[10px] bg-[linear-gradient(135deg,#c9d6d8,#8fa7ab_55%,#5f7c80)]" />
        {[Camera, Video, Images].map((I, i) => (
          <div key={i} className="flex size-14 items-center justify-center rounded-[10px] bg-[var(--kutu)]">
            <I className="size-4 text-[var(--vurgu)]" />
          </div>
        ))}
      </div>
      <div className="flex items-center gap-2 rounded-[12px] bg-[var(--kutu)] px-3 py-2">
        <div className="flex flex-1 flex-col">
          <span className="text-[11.5px] font-semibold">Acil</span>
          <span className="text-[9.5px] text-[var(--yazi-soluk)]">Su baskını, elektrik, asansörde kalma gibi.</span>
        </div>
        <span className="h-4 w-7 rounded-full bg-[var(--cizgi)] p-0.5">
          <span className="block size-3 rounded-full bg-[var(--kutu)]" />
        </span>
      </div>
      <div className="absolute inset-x-3.5 bottom-5">
        <MainButton label="Gönder" icon={Send} />
      </div>
    </Phone>
  );
}

export function TicketDetail() {
  const steps = ["Yeni", "İnceleniyor", "Yapılıyor", "Tamamlandı"];
  return (
    <Phone label="Sakin: Kayıt detayı ve durum adımları">
      <span className="flex items-center gap-1 text-[12px] font-medium text-[var(--vurgu)]">
        <ChevronLeft className="size-4" /> Geri
      </span>
      <Title title="Banyo musluğu damlatıyor" subtitle="Arıza · A-1" />
      <div className="flex gap-1.5 px-1">
        <Pill label="Yapılıyor" tone="bekliyor" />
      </div>
      <div className="rounded-[14px] bg-[var(--kutu)] px-2 py-3">
        <div className="flex">
          {steps.map((s, i) => (
            <div key={s} className="flex flex-1 flex-col items-center gap-1">
              <div className="flex w-full items-center">
                <span className={`h-0.5 flex-1 ${i === 0 ? "bg-transparent" : i <= 2 ? "bg-[var(--vurgu)]" : "bg-[var(--cizgi)]"}`} />
                <span className={`flex size-4 items-center justify-center rounded-full ${i <= 2 ? "bg-[var(--vurgu)]" : "bg-[var(--kutu-koyu)]"}`}>
                  {i <= 2 && <Check className="size-2.5 text-[var(--vurgu-yazi)]" strokeWidth={3} />}
                </span>
                <span className={`h-0.5 flex-1 ${i === 3 ? "bg-transparent" : i < 2 ? "bg-[var(--vurgu)]" : "bg-[var(--cizgi)]"}`} />
              </div>
              <span className={`text-[8.5px] ${i === 2 ? "font-semibold" : "text-[var(--yazi-soluk)]"}`}>{s}</span>
            </div>
          ))}
        </div>
      </div>
      <div className="h-24 rounded-[14px] bg-[linear-gradient(135deg,#c9d6d8,#8fa7ab_55%,#5f7c80)]" />
      <Label>GEÇMİŞ</Label>
      <div className="flex flex-col gap-2.5 px-1">
        {[
          { t: "Yapılıyor", b: "Tesisatçı yarın 10:00'da geliyor.", m: "Mehmet Yılmaz (Yönetim) · 10:20", on: true },
          { t: "İnceleniyor", b: "", m: "Mehmet Yılmaz (Yönetim) · 09:35", on: true },
          { t: "Ayşe Kaya", b: "Mutfağın altına da su sızıyor.", m: "Sakin · 09:14", on: false },
        ].map((e) => (
          <div key={e.m} className="flex gap-2">
            <span className={`mt-1 size-2 shrink-0 rounded-full ${e.on ? "bg-[var(--vurgu)]" : "bg-[var(--cizgi)]"}`} />
            <div className="flex flex-col gap-0.5">
              <span className="text-[11px] font-semibold">{e.t}</span>
              {e.b && <span className="text-[11px]">{e.b}</span>}
              <span className="text-[9.5px] text-[var(--yazi-soluk)]">{e.m}</span>
            </div>
          </div>
        ))}
      </div>
    </Phone>
  );
}

export function ResidentParcel() {
  return (
    <Phone label="Sakin: kargo bildirimi ve Kargolarım">
      <div className="absolute inset-x-2.5 top-10 z-10 flex gap-2 rounded-[16px] bg-[var(--kutu)] p-2.5 shadow-[0_10px_30px_-8px_rgba(43,31,20,0.35)]">
        <span className="flex size-8 shrink-0 items-center justify-center rounded-[9px] bg-[var(--vurgu)]">
          <Bell className="size-4 text-[var(--vurgu-yazi)]" />
        </span>
        <div className="flex min-w-0 flex-col">
          <span className="text-[10.5px] font-semibold">Kargonuz geldi</span>
          <span className="text-[10px] leading-snug text-[var(--yazi-soluk)]">A-1 adına kargonuz danışmaya ulaştı. Danışmadan teslim alabilirsiniz.</span>
        </div>
      </div>
      <div className="h-16" />
      <Title title="Kargo" subtitle="A-1 · Demo Sitesi" />
      <Segmented items={["Kargolarım (1)", "Ziyaretçilerim"]} />
      <Label>DANIŞMADA BEKLEYEN</Label>
      <Group>
        <Row title="Kargo · A-1" subtitle="Bugün 14:20 · Büyük koli" right={<Pill label="Bekliyor" tone="bekliyor" />} />
      </Group>
      <Label>TESLİM EDİLENLER (SON 30 GÜN)</Label>
      <Group>
        <Row title="Kargo · A-1" subtitle="02.10.2026 18:05 teslim edildi · Ayşe Kaya" right={<Pill label="Teslim" tone="basari" />} />
        <Row title="Kargo · A-1" subtitle="27.09.2026 12:40 teslim edildi" right={<Pill label="Teslim" tone="basari" />} />
      </Group>
      <Tabs items={SAKIN_TABS} active={1} />
    </Phone>
  );
}

// ——— Danışma ———
export function DeskParcel() {
  const units = ["A-1", "A-2", "A-3", "A-4", "A-5", "A-6", "A-7", "A-8", "A-9"];
  const counts: Record<string, number> = { "A-3": 2, "A-7": 1 };
  return (
    <Phone label="Danışma: kargo kaydı">
      <Title title="Kargo" subtitle="Demo Sitesi" />
      <Segmented items={["Yeni kargo", "Bekleyen (3)", "Bugün verilen"]} />
      <span className="px-1 text-[10.5px] text-[var(--yazi-soluk)]">Kargonun geldiği daireye dokunun.</span>
      <Segmented items={["A Blok", "B Blok"]} />
      <div className="grid grid-cols-3 gap-1.5">
        {units.map((u) => (
          <div key={u} className={`relative flex h-12 items-center justify-center rounded-[12px] text-[13px] font-bold ${u === "A-1" ? "border-2 border-[var(--vurgu)] bg-[var(--vurgu-acik)]" : "bg-[var(--kutu)]"}`}>
            {u}
            {counts[u] && (
              <span className="absolute right-1 top-1 flex size-4 items-center justify-center rounded-full bg-[var(--bekliyor)] text-[8.5px] font-bold text-[var(--vurgu-yazi)]">{counts[u]}</span>
            )}
          </div>
        ))}
      </div>
      <div className="absolute inset-x-0 bottom-[66px] flex flex-col gap-2 rounded-t-[20px] bg-[var(--zemin)] px-3.5 pb-3 pt-3 shadow-[0_-10px_30px_-10px_rgba(43,31,20,0.35)]">
        <span className="text-[10px] text-[var(--yazi-soluk)]">Yeni kargo</span>
        <span className="text-[17px] font-bold">A-1</span>
        <div className="rounded-[12px] bg-[var(--kutu)] px-3 py-2 text-[11px] text-[var(--yazi-soluk)]">Not: Büyük koli</div>
        <MainButton label="Kaydet" icon={Package} />
      </div>
      <Tabs items={DANISMA_TABS} active={0} />
    </Phone>
  );
}

export function DeskVisitors() {
  const people = [
    { n: "Zeynep Arslan → A-3", s: "Giriş 13:05 · 34ABC123" },
    { n: "Can Demir → B-2", s: "Giriş 12:40" },
    { n: "Klima servisi → A-6", s: "Giriş 11:15 · 06KLM42" },
  ];
  return (
    <Phone label="Danışma: içerideki ziyaretçiler">
      <Title title="Ziyaretçi" subtitle="Demo Sitesi" />
      <Segmented items={["Yeni giriş", "İçeride (3)", "Bugün çıkan"]} active={1} />
      <Group>
        {people.map((p) => (
          <Row
            key={p.n}
            title={p.n}
            subtitle={p.s}
            right={<span className="shrink-0 rounded-[10px] bg-[var(--vurgu)] px-2 py-1.5 text-[10px] font-semibold text-[var(--vurgu-yazi)]">Çıkış yaptı</span>}
          />
        ))}
      </Group>
      <span className="px-1 text-[10px] leading-snug text-[var(--yazi-soluk)]">Giriş saati kendiliğinden yazılır; “Çıkış yaptı”ya basınca çıkış saati de.</span>
      <Label>BUGÜN ÇIKAN</Label>
      <Group>
        <Row title="Elif Şahin · A-1" subtitle="Giriş 09:20 · Çıkış 10:45" right={<span className="text-[10.5px] font-medium text-[var(--vurgu)]">Geri al</span>} />
      </Group>
      <Tabs items={DANISMA_TABS} active={1} />
    </Phone>
  );
}

// ——— Yönetici ———
export function ManagerTickets() {
  return (
    <Phone label="Yönetici: bütün kayıtlar">
      <Title title="Kayıtlar" subtitle="Demo Sitesi" />
      <div className="grid grid-cols-3 gap-1.5">
        {[
          ["14", "Açılan"],
          ["11", "Kapanan"],
          ["1,5 gün", "Ort. çözüm"],
        ].map(([n, l]) => (
          <div key={l} className="flex flex-col rounded-[12px] bg-[var(--kutu)] px-2 py-2">
            <span className="text-[14px] font-bold tabular-nums">{n}</span>
            <span className="text-[9px] text-[var(--yazi-soluk)]">{l}</span>
          </div>
        ))}
      </div>
      <Segmented items={["Açık", "Biten", "Tümü"]} />
      <div className="flex gap-1.5">
        {["Acil", "Tür", "Blok"].map((f) => (
          <span key={f} className="flex items-center gap-1 rounded-full bg-[var(--kutu)] px-2.5 py-1 text-[10px] font-semibold">
            {f === "Acil" ? null : <SlidersHorizontal className="size-3" />}
            {f}
          </span>
        ))}
      </div>
      <Group>
        <Row bar title="Su baskını" subtitle="Acil · Arıza · B-4 · 45 dk önce" right={<Pill label="Yeni" tone="bilgi" />} />
        <Row title="Banyo musluğu damlatıyor" subtitle="Arıza · A-1 · 4 saat önce" right={<Pill label="Yapılıyor" tone="bekliyor" />} />
        <Row title="Otopark lambası yanmıyor" subtitle="Arıza · A-1 · Ortak alan · 15 saat önce" right={<Pill label="Yeni" tone="bilgi" />} />
        <Row title="Bahçe sulaması geç saatte" subtitle="Talep · A-1 · 5 gün önce" right={<Pill label="İnceleniyor" tone="bekliyor" />} />
      </Group>
      <Tabs items={YONETICI_TABS} active={0} />
    </Phone>
  );
}

export function ManagerInvite() {
  return (
    <Phone label="Yönetici: WhatsApp ile davet">
      <Title title="Kişiler" subtitle="Demo Sitesi" />
      <Segmented items={["Davet", "Sakinler", "Görevliler", "Daireler"]} />
      <div className="flex flex-col gap-1.5 rounded-[14px] bg-[var(--kutu)] p-3">
        <span className="text-[12px] font-semibold">Davet hazır: Ayşe Kaya</span>
        <span className="text-[10px] text-[var(--yazi-soluk)]">Davet kodu</span>
        <span className="text-[22px] font-bold tracking-[0.18em]">K7M3PQ2X</span>
        <div className="flex h-9 items-center justify-center gap-1.5 rounded-[11px] bg-[var(--vurgu)] text-[11px] font-semibold text-[var(--vurgu-yazi)]">
          <MessageCircle className="size-3.5" /> WhatsApp&apos;ta gönder
        </div>
      </div>
      <div className="flex flex-col gap-1.5 rounded-[14px] bg-[var(--kutu)] p-3">
        <span className="text-[12px] font-semibold">Yeni davet</span>
        <div className="flex gap-1.5">
          {["Sakin", "Danışma", "Yönetici"].map((r, i) => (
            <span key={r} className={`flex-1 rounded-[10px] border-2 py-1.5 text-center text-[10.5px] font-semibold ${i === 0 ? "border-[var(--vurgu)] bg-[var(--vurgu-acik)]" : "border-transparent bg-[var(--kutu-koyu)]"}`}>
              {r}
            </span>
          ))}
        </div>
        <div className="flex flex-wrap gap-1">
          {["A-1", "A-2", "A-3", "A-4", "A-5", "A-6"].map((u, i) => (
            <span key={u} className={`rounded-[8px] border px-2 py-1 text-[10px] font-semibold ${i === 3 ? "border-[var(--vurgu)] bg-[var(--vurgu-acik)]" : "border-[var(--cizgi)]"}`}>
              {u}
            </span>
          ))}
        </div>
        <div className="rounded-[10px] bg-[var(--kutu-koyu)] px-2.5 py-1.5 text-[10.5px]">Ali Çelik</div>
        <div className="rounded-[10px] bg-[var(--kutu-koyu)] px-2.5 py-1.5 text-[10.5px]">0532 000 00 00</div>
        <div className="flex h-9 items-center justify-center gap-1.5 rounded-[11px] bg-[var(--vurgu)] text-[10.5px] font-semibold text-[var(--vurgu-yazi)]">
          <UserPlus className="size-3.5" /> Davet et ve WhatsApp&apos;ta gönder
        </div>
      </div>
      <Tabs items={YONETICI_TABS} active={2} />
    </Phone>
  );
}
