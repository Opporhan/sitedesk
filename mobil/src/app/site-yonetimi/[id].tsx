import { Redirect, router, useFocusEffect, useLocalSearchParams } from "expo-router";
import { useCallback, useEffect, useRef, useState } from "react";
import { Alert, KeyboardAvoidingView, Platform, Pressable, Switch, Text, View } from "react-native";
import { Eye } from "lucide-react-native";
import { useAuth } from "@/auth";
import { NETWORK_ERROR, supabase } from "@/lib/supabase";
import { sendPasswordReset } from "@/lib/reset";
import { unitWords } from "@/lib/words";
import { formatBytes } from "@/lib/format";
import { formatPhone } from "@/lib/phone";
import { InviteForm } from "@/components/invite-form";
import { ContactButtons } from "@/components/people-manager";
import { BackHeader, Body, Button, Card, Muted, Notice, Screen } from "@/components/ui";
import { FONT, useTheme } from "@/theme";

type Site = { id: string; name: string; type: string; address: string | null; active: boolean; is_demo: boolean };
type Stat = { units: number; residents_with_app: number; staff: number; open_tickets: number; storage_bytes: number };
type Manager = { id: string; started_on: string; profiles: { full_name: string; phone: string | null } | null };

// Sistem yöneticisi: bir site — açık/kapalı, sayılar, yöneticiler ve yönetici daveti
export default function SiteAdmin() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { colors } = useTheme();
  const { context, active, setActive } = useAuth();
  // "Yönetici gözüyle bak"tan geri dönünce yeniden sistem yöneticisi olur
  // (sadece ekrana dönüldüğünde; düğmeye basılınca hemen geri almasın diye son değerler ref'te)
  const latest = useRef({ admin: false, kind: "", setActive });
  latest.current = { admin: !!context?.platform_admin, kind: active.kind, setActive };
  useFocusEffect(
    useCallback(() => {
      const l = latest.current;
      if (l.admin && l.kind !== "platform") l.setActive({ kind: "platform" });
    }, [])
  );
  const [site, setSite] = useState<Site | null>(null);
  const [stat, setStat] = useState<Stat | null>(null);
  const [managers, setManagers] = useState<Manager[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    const [s, st, m] = await Promise.all([
      supabase.from("sites").select("id, name, type, address, active, is_demo").eq("id", id).maybeSingle(),
      supabase.rpc("platform_site_stats"),
      supabase.from("memberships").select("id, started_on, profiles(full_name, phone)").eq("site_id", id).eq("role", "yonetici").is("ended_on", null),
    ]);
    if (s.error) return setError(s.error.message.includes("fetch") ? NETWORK_ERROR : "Site açılamadı.");
    const row = s.data as Site | null;
    setSite(row);
    setStat(((st.data ?? []) as (Stat & { site_id: string })[]).find((x) => x.site_id === id) ?? null);
    setManagers((m.data ?? []) as unknown as Manager[]);
  }, [id]);
  useEffect(() => {
    load();
  }, [load]);
  if (!context?.platform_admin) return <Redirect href="/" />;

  async function update(values: Partial<Site>, message: string) {
    setBusy(true);
    setError(null);
    setSaved(null);
    const { error: e } = await supabase.from("sites").update(values).eq("id", id);
    setBusy(false);
    if (e) return setError(e.message.includes("fetch") ? NETWORK_ERROR : "Kaydedilemedi.");
    setSaved(message);
    load();
  }

  function toggleActive(next: boolean) {
    if (next) return update({ active: true }, "Site açıldı. Herkes yeniden girebilir.");
    Alert.alert("Site kapatılsın mı?", "Yönetici, danışma ve sakinler bu siteye giremez. Hiçbir bilgi silinmez; istediğiniz zaman yeniden açabilirsiniz.", [
      { text: "Vazgeç", style: "cancel" },
      { text: "Kapat", style: "destructive", onPress: () => update({ active: false }, "Site kapatıldı.") },
    ]);
  }

  function endManager(m: Manager) {
    Alert.alert("Erişim kapatılsın mı?", `${m.profiles?.full_name ?? "Yönetici"} artık bu siteyi yönetemez.`, [
      { text: "Vazgeç", style: "cancel" },
      {
        text: "Kapat",
        style: "destructive",
        onPress: async () => {
          const { error: e } = await supabase.from("memberships").update({ ended_on: new Date().toISOString().slice(0, 10) }).eq("id", m.id);
          if (e) setError("Erişim kapatılamadı.");
          load();
        },
      },
    ]);
  }

  return (
    <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === "ios" ? "padding" : undefined}>
      <Screen title={site?.name ?? "Site"} subtitle={site?.address ?? undefined} header={<BackHeader />}>
        {error && <Notice tone="hata" text={error} />}
        {saved && <Notice tone="basari" text={saved} />}
        {site && (
          <>
            <Card>
              <View style={{ flexDirection: "row", alignItems: "center", gap: 12, minHeight: 48 }}>
                <View style={{ flex: 1 }}>
                  <Body style={{ fontFamily: FONT.kalin, color: site.active ? colors.basari : colors.hata }}>{site.active ? "Site aktif" : "Site kapalı"}</Body>
                  <Muted>{site.active ? "Herkes uygulamayı kullanabiliyor." : "Sistem yöneticisi dışında kimse giremiyor."}</Muted>
                </View>
                <Switch value={site.active} onValueChange={toggleActive} disabled={busy} trackColor={{ true: colors.basari, false: colors.cizgi }} accessibilityLabel="Site aktif" />
              </View>
            </Card>

            {stat && (
              <Card>
                <Muted>
                  {stat.units} {unitWords(site.type).nom} · {stat.residents_with_app} sakin uygulamada · {stat.staff} görevli · {stat.open_tickets} açık kayıt · depo {formatBytes(Number(stat.storage_bytes))}
                </Muted>
              </Card>
            )}

            <Button
              label="Bu Siteye Yönetici Gözüyle Bak"
              icon={Eye}
              variant="ikincil"
              onPress={() => {
                setActive({ kind: "yonetici", siteId: site.id, siteName: site.name, siteType: site.type });
                router.push("/yonetici");
              }}
            />

            <Card>
              <Body style={{ fontFamily: FONT.kalin }}>Yöneticiler</Body>
              {managers.length === 0 ? (
                <Muted>Henüz yönetici yok. Aşağıdan davet edin.</Muted>
              ) : (
                managers.map((m) => (
                  <View key={m.id} style={{ gap: 4, borderTopWidth: 1, borderTopColor: colors.cizgi, paddingTop: 8 }}>
                    <View style={{ flexDirection: "row", alignItems: "center", gap: 8 }}>
                      <View style={{ flex: 1 }}>
                        <Body>{m.profiles?.full_name || "Yönetici"}</Body>
                        <Muted>{m.profiles?.phone ? formatPhone(m.profiles.phone) : ""}</Muted>
                      </View>
                      <ContactButtons phone={m.profiles?.phone ?? null} />
                    </View>
                    <View style={{ flexDirection: "row", gap: 16 }}>
                      {m.profiles?.phone ? (
                        <Pressable
                          accessibilityRole="button"
                          onPress={async () => {
                            setError(null);
                            const err = await sendPasswordReset(site.id, site.name, m.profiles!.phone!);
                            if (err) setError(err);
                          }}
                          style={{ minHeight: 44, justifyContent: "center" }}
                        >
                          <Text style={{ fontFamily: FONT.orta, fontSize: 15, color: colors.vurgu }}>Şifre yenileme kodu gönder</Text>
                        </Pressable>
                      ) : null}
                      <Pressable accessibilityRole="button" onPress={() => endManager(m)} style={{ minHeight: 44, justifyContent: "center" }}>
                        <Text style={{ fontFamily: FONT.orta, fontSize: 15, color: colors.hata }}>Erişimi kapat</Text>
                      </Pressable>
                    </View>
                  </View>
                ))
              )}
            </Card>

            <InviteForm siteId={site.id} siteName={site.name} roles={["yonetici"]} />
          </>
        )}
      </Screen>
    </KeyboardAvoidingView>
  );
}
