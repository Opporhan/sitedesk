import { SiteFooter, SiteHeader } from "@/components/doc";

// Herkese açık sayfalar (giriş gerekmez): tanıtım, gizlilik, destek, hesap silme.
export default function MarketingLayout({ children }: { children: React.ReactNode }) {
  return (
    <>
      <SiteHeader />
      <main className="flex flex-1 flex-col">{children}</main>
      <SiteFooter />
    </>
  );
}
