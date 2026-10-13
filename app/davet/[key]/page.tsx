import type { Metadata } from "next";
import { Building2 } from "lucide-react";
import { createAdminClient } from "@/lib/supabase/admin";
import { CopyCode } from "./copy-code";
import { APK_URL } from "@/lib/legal";

export const metadata: Metadata = { title: "SiteDesk daveti", robots: { index: false } };

type Preview = { valid: boolean; status: string; code: string; role: string; full_name: string; site_name: string; unit_label: string | null };
const ROLE_TEXT: Record<string, string> = { sakin: "Sakin", danisma: "Danışma görevlisi", yonetici: "Yönetici", sifre: "Şifre yenileme" };

// WhatsApp'tan gelen davet bağlantısı: uygulama yüklüyse açar, değilse Android uygulamasının indirme bağlantısını gösterir; kod kopyalanır,
// böylece uygulama yüklendikten sonra kaldığı yerden devam edilir (iPhone'da panodan, her yerde elle kod girişiyle).
export default async function InvitePage({ params }: PageProps<"/davet/[key]">) {
  const { key } = await params;
  const { data } = await createAdminClient().rpc("invite_preview", { p_key: key });
  const invite = data as Preview | null;
  const appLink = `sitedesk://davet/${encodeURIComponent(key)}`;

  return (
    <div className="mx-auto flex w-full max-w-md flex-1 flex-col gap-6 px-4 py-12">
      <div className="flex flex-col items-center gap-2 text-center">
        <Building2 className="size-10 text-primary" aria-hidden />
        <h1 className="text-2xl font-bold tracking-tight">SiteDesk</h1>
      </div>
      {!invite ? (
        <p className="rounded-xl bg-muted p-4 text-center">Bu davet bulunamadı. Yönetiminizden yeni davet isteyin.</p>
      ) : !invite.valid ? (
        <p className="rounded-xl bg-muted p-4 text-center">
          {invite.status === "kullanildi"
            ? "Bu davet kullanılmış. Uygulamada telefon numaranız ve şifrenizle giriş yapabilirsiniz."
            : "Bu davetin süresi dolmuş ya da iptal edilmiş. Yönetiminizden yeni davet isteyin."}
        </p>
      ) : (
        <>
          <div className="flex flex-col gap-1 rounded-2xl border bg-card p-5 text-center">
            <p className="text-lg font-semibold">Merhaba {invite.full_name}</p>
            <p className="text-muted-foreground">
              {invite.role === "sifre" ? `${invite.site_name} · Şifrenizi yenilemek için uygulamada açın` : `${invite.site_name} sizi SiteDesk'e davet ediyor · ${ROLE_TEXT[invite.role] ?? ""}`}
              {invite.unit_label ? ` · ${invite.unit_label}` : ""}
            </p>
          </div>
          <a
            href={appLink}
            className="inline-flex h-12 items-center justify-center rounded-lg bg-primary px-6 text-base font-medium text-primary-foreground hover:bg-primary/90 focus-visible:outline-none focus-visible:ring-3 focus-visible:ring-ring/50"
          >
            Uygulamada aç
          </a>
          <div className="flex flex-col gap-3 rounded-2xl border bg-card p-5">
            <p className="font-semibold">Uygulama yüklü değil mi?</p>
            <ol className="flex list-decimal flex-col gap-1 pl-5 text-muted-foreground">
              <li>Aşağıdaki davet kodunu kopyalayın.</li>
              <li>
                SiteDesk uygulamasını yükleyin:{" "}
                <a href={APK_URL} className="font-medium text-primary underline underline-offset-4">
                  Android uygulamasını indir
                </a>
                .
              </li>
              <li>Uygulamada &quot;Davet veya Şifre Kodum Var&quot; deyip kodu yapıştırın.</li>
            </ol>
            <CopyCode code={invite.code} />
          </div>
        </>
      )}
    </div>
  );
}
