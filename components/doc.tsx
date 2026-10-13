import Link from "next/link";

// Metin sayfaları (gizlilik, destek, mağaza bilgileri) için sade yapı taşları
export function Doc({ title, lead, children }: { title: string; lead?: string; children: React.ReactNode }) {
  return (
    <article className="mx-auto flex w-full max-w-2xl flex-col gap-8 px-4 py-10 sm:py-14">
      <header className="flex flex-col gap-3">
        <h1 className="text-3xl font-bold tracking-tight sm:text-4xl">{title}</h1>
        {lead && <p className="text-lg text-muted-foreground">{lead}</p>}
      </header>
      {children}
    </article>
  );
}

export function Section({ title, id, children }: { title: string; id?: string; children: React.ReactNode }) {
  return (
    <section id={id} className="flex scroll-mt-6 flex-col gap-3">
      <h2 className="text-xl font-semibold tracking-tight">{title}</h2>
      {children}
    </section>
  );
}

export function P({ children }: { children: React.ReactNode }) {
  return <p className="leading-relaxed">{children}</p>;
}

export function List({ items }: { items: React.ReactNode[] }) {
  return (
    <ul className="flex list-disc flex-col gap-1.5 pl-5 leading-relaxed">
      {items.map((x, i) => (
        <li key={i}>{x}</li>
      ))}
    </ul>
  );
}

export function Note({ children, tone = "bilgi" }: { children: React.ReactNode; tone?: "bilgi" | "bekliyor" }) {
  return <div className={`rounded-xl p-4 leading-relaxed ${tone === "bekliyor" ? "bg-bekliyor-zemin text-bekliyor" : "bg-bilgi-zemin text-bilgi"}`}>{children}</div>;
}

export function DraftBanner() {
  return (
    <Note tone="bekliyor">
      <strong>Not:</strong> SiteDesk ticari olmayan, açık kaynak bir projedir; bu metin bir hukukçu tarafından incelenmemiştir.
    </Note>
  );
}

export function SiteHeader() {
  return (
    <div className="border-b border-border">
      <nav className="mx-auto flex w-full max-w-6xl items-center justify-between gap-4 px-4 py-3">
        <Link href="/" className="text-lg font-bold tracking-tight">
          SiteDesk
        </Link>
        <div className="flex gap-4 text-sm text-muted-foreground">
          <Link href="/destek" className="hover:text-foreground">
            Destek
          </Link>
          <Link href="/gizlilik" className="hover:text-foreground">
            Gizlilik
          </Link>
        </div>
      </nav>
    </div>
  );
}

export function SiteFooter() {
  return (
    <footer className="mt-auto border-t border-border">
      <div className="mx-auto flex w-full max-w-6xl flex-wrap gap-x-5 gap-y-2 px-4 py-6 text-sm text-muted-foreground">
        <span>© 2026 SiteDesk</span>
        <Link href="/destek" className="hover:text-foreground">
          Destek
        </Link>
        <Link href="/gizlilik" className="hover:text-foreground">
          Gizlilik politikası
        </Link>
        <Link href="/hesap-sil" className="hover:text-foreground">
          Hesap silme
        </Link>
      </div>
    </footer>
  );
}
