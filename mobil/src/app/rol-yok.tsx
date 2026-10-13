import { Redirect, router } from "expo-router";
import { CircleHelp, Clock } from "lucide-react-native";
import { useAuth } from "@/auth";
import { Button, EmptyState, ListGroup, ListRow, Muted, Screen, SectionLabel } from "@/components/ui";

// Giriş yapan kişinin henüz hiçbir sitede rolü yok: katılma isteği bekliyor olabilir, siteye katılabilir ya da kendi sitesini açabilir
export default function NoRoleScreen() {
  const { session, active, context, reloadContext, signOut } = useAuth();
  if (!session || active.kind !== "yok") return <Redirect href="/" />;
  const closed = context?.closed_sites ?? [];
  const pending = context?.pending_joins ?? [];
  return (
    <Screen title="Hoş geldiniz" subtitle={context?.full_name || undefined}>
      {pending.length > 0 ? (
        <>
          <SectionLabel>ONAY BEKLEYEN İSTEKLERİNİZ</SectionLabel>
          <ListGroup>
            {pending.map((p) => (
              <ListRow key={`${p.site_name}-${p.label}`} left={<Clock size={20} color="#9a5300" />} title={`${p.site_name} · ${p.label}`} subtitle="Site yönetiminin onayı bekleniyor" chevron={false} />
            ))}
          </ListGroup>
          <Muted>Yönetim onaylayınca telefonunuza bildirim gelir. Onaydan sonra “Yenile”ye basın.</Muted>
        </>
      ) : closed.length > 0 ? (
        <EmptyState icon={CircleHelp} title={`${closed.join(", ")} şu an kapalı`} text="Sitenizin SiteDesk kullanımı şu an durdurulmuş. Bilgileriniz silinmedi; ayrıntı için site yönetiminizle görüşün." />
      ) : (
        <EmptyState icon={CircleHelp} title="Henüz bir siteye bağlı değilsiniz" text="Yönetiminizin paylaştığı site koduyla katılın ya da sitenizin yöneticisiyseniz sitenizi ekleyin." />
      )}
      <Button label="Siteme Katıl (Site Kodu)" onPress={() => router.push("/katil")} />
      <Button label="Sitemi Ekle (Yöneticiyim)" variant="ikincil" onPress={() => router.push("/site-yonetimi/yeni")} />
      <Button label="Davet veya Şifre Kodum Var" variant="ikincil" onPress={() => router.push("/davet")} />
      <Button label="Yenile" variant="metin" onPress={reloadContext} />
      <Button label="Çıkış Yap" variant="metin" onPress={signOut} />
    </Screen>
  );
}
