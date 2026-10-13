import type { Metadata } from "next";
import Link from "next/link";
import { Doc, List, Section } from "@/components/doc";
import { DeleteAccountForm } from "./delete-form";

export const metadata: Metadata = {
  title: "Hesap Silme · SiteDesk",
  description: "SiteDesk hesabınızı uygulama olmadan, telefon numaranız ve şifrenizle silin.",
};

// Uygulama olmadan hesap silme (Google Play şartı): telefon + şifre ile giriş yapılır, hesap sunucuda silinir.
export default function DeleteAccountPage() {
  return (
    <Doc title="Hesabımı Sil" lead="Uygulama telefonunuzda yoksa hesabınızı buradan silebilirsiniz. Uygulamada da Profil › Hesabımı Sil ile silinir.">
      <Section title="Neler silinir?">
        <List
          items={[
            "Giriş bilgileriniz (telefon numarası ve şifre), profiliniz ve profil resminiz hemen silinir.",
            "Bir daha bu hesapla giriş yapamazsınız; telefon bildirimleri durur.",
            "Sitenin kaydı olan arıza, kargo ve ziyaretçi kayıtları (ve bu kayıtlardaki yazar adı) site yönetiminin hizmeti sürdüğü sürece kalır; silinmesi için site yönetiminize başvurun.",
          ]}
        />
      </Section>
      <DeleteAccountForm />
      <p className="text-sm text-muted-foreground">
        Şifrenizi hatırlamıyor musunuz?{" "}
        <Link href="/destek#hesap-silme" className="font-medium text-primary underline underline-offset-4">
          Destek sayfasındaki yolları
        </Link>{" "}
        kullanın.
      </p>
    </Doc>
  );
}
