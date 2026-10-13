import { Redirect, router } from "expo-router";
import { useCallback, useState } from "react";
import { Pressable, RefreshControl, ScrollView, Text, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { Building2, ChevronRight, House, Plus, Siren, Sparkles, Wrench, type LucideIcon } from "lucide-react-native";
import { useAuth } from "@/auth";
import { NETWORK_ERROR, supabase } from "@/lib/supabase";
import { useAutoRefresh } from "@/lib/use-auto-refresh";
import { Button, EmptyState, Notice, Pill, ScreenTitle } from "@/components/ui";
import { FONT, SIZE, useTheme } from "@/theme";

type SiteRow = { site_id: string; name: string; type: string; active: boolean; open_tickets: number; urgent_open: number; new_tickets: number };

// Sitelerim: birden çok siteyi yöneten kişi bütün sitelerini tek ekranda görür (acil kaydı olan en üstte); dokununca o siteye geçer
export default function MySites() {
  const { colors } = useTheme();
  const insets = useSafeAreaInsets();
  const { session, roleOptions, setActive } = useAuth();
  const [sites, setSites] = useState<SiteRow[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);

  const load = useCallback(async () => {
    const { data, error: e } = await supabase.rpc("my_sites_overview");
    if (e) return setError(e.message.includes("fetch") ? NETWORK_ERROR : "Siteler alınamadı.");
    setError(null);
    const rows = (data ?? []) as SiteRow[];
    rows.sort((a, b) => b.urgent_open - a.urgent_open || b.new_tickets - a.new_tickets || b.open_tickets - a.open_tickets || a.name.localeCompare(b.name, "tr"));
    setSites(rows);
  }, []);
  useAutoRefresh(load);
  if (!session) return <Redirect href="/" />;

  const total = (k: keyof SiteRow) => sites.reduce((s, x) => s + Number(x[k]), 0);
  function open(siteId: string) {
    const role = roleOptions.find((r) => r.kind === "yonetici" && r.siteId === siteId);
    if (!role) return;
    setActive(role);
    router.push("/yonetici"); // liste altta kalır: geri tuşu buraya döner (lib/nav.ts)
  }

  // Üstteki toplamlar: simge + "7 Açık kayıt" yan yana (acil varsa kırmızı)
  const stat = (Icon: LucideIcon, n: number, label: string, alarm?: boolean) => (
    <View style={{ flex: 1, flexDirection: "row", alignItems: "center", justifyContent: "center", gap: 5, paddingHorizontal: 8, paddingVertical: 9, borderRadius: 999, backgroundColor: alarm ? colors.hataZemin : colors.kutu }}>
      <Icon size={15} color={alarm ? colors.hata : colors.vurgu} strokeWidth={2} />
      <Text numberOfLines={1} adjustsFontSizeToFit minimumFontScale={0.8} style={{ flexShrink: 1, fontFamily: FONT.orta, fontSize: 13, color: alarm ? colors.hata : colors.yazi }}>
        <Text style={{ fontFamily: FONT.cokKalin, fontVariant: ["tabular-nums"] }}>{n}</Text> {label}
      </Text>
    </View>
  );

  // Simgeli küçük sayı: simge + "3 kayıt" (sıfırsa soluk)
  const chip = (Icon: LucideIcon, n: number, label: string) => (
    <View style={{ flexDirection: "row", alignItems: "center", gap: 5, paddingHorizontal: 9, paddingVertical: 5, borderRadius: 999, backgroundColor: colors.kutuKoyu, opacity: n ? 1 : 0.6 }}>
      <Icon size={14} color={n ? colors.yazi : colors.yaziSoluk} strokeWidth={2} />
      <Text style={{ fontFamily: FONT.orta, fontSize: 13, color: n ? colors.yazi : colors.yaziSoluk, fontVariant: ["tabular-nums"] }}>
        {n} {label}
      </Text>
    </View>
  );

  return (
    <ScrollView
      style={{ flex: 1, backgroundColor: colors.zemin }}
      contentContainerStyle={{ paddingTop: insets.top + 8, paddingHorizontal: SIZE.kenar, paddingBottom: 40, gap: 18 }}
      refreshControl={<RefreshControl refreshing={refreshing} tintColor={colors.vurgu} onRefresh={async () => { setRefreshing(true); await load(); setRefreshing(false); }} />}
    >
      <ScreenTitle title="Sitelerim" subtitle={sites.length ? `${sites.length} site` : undefined} />
      <Button label="Yeni Site Ekle" icon={Plus} variant="ikincil" onPress={() => router.push("/site-yonetimi/yeni")} />
      {error && <Notice tone="hata" text={error} />}
      {sites.length > 0 && (
        <View style={{ flexDirection: "row", gap: 6 }}>
          {stat(Wrench, total("open_tickets"), "Açık kayıt")}
          {stat(Siren, total("urgent_open"), "Acil", total("urgent_open") > 0)}
          {stat(Sparkles, total("new_tickets"), "Yeni")}
        </View>
      )}
      {sites.length === 0 && !error ? (
        <EmptyState icon={Building2} title="Yönettiğiniz site yok" text="Sitenizi “Yeni Site Ekle” ile ekleyin ya da bir siteye yönetici olarak davet edilince burada görünür." />
      ) : (
        <View style={{ gap: 10 }}>
          {sites.map((s) => {
            const Icon = s.type === "villa" ? House : Building2;
            return (
              <Pressable
                key={s.site_id}
                accessibilityRole="button"
                accessibilityLabel={`${s.name}: ${s.open_tickets} açık kayıt, ${s.urgent_open} acil`}
                onPress={() => open(s.site_id)}
                style={({ pressed }) => ({ flexDirection: "row", alignItems: "center", gap: 14, padding: 14, borderRadius: 18, backgroundColor: pressed ? colors.kutuKoyu : colors.kutu })}
              >
                <View style={{ width: 48, height: 48, borderRadius: 14, alignItems: "center", justifyContent: "center", backgroundColor: s.urgent_open ? colors.hataZemin : colors.vurguAcik }}>
                  <Icon size={24} color={s.urgent_open ? colors.hata : colors.vurgu} strokeWidth={1.75} />
                </View>
                <View style={{ flex: 1, gap: 8, alignItems: "flex-start" }}>
                  <View style={{ flexDirection: "row", alignItems: "center", gap: 8, alignSelf: "stretch" }}>
                    <Text numberOfLines={1} style={{ flex: 1, fontFamily: FONT.kalin, fontSize: 17, color: colors.yazi }}>
                      {s.name}
                    </Text>
                    {s.urgent_open ? <Pill label={`${s.urgent_open} acil`} tone="hata" /> : s.new_tickets ? <Pill label={`${s.new_tickets} yeni`} tone="bilgi" /> : null}
                  </View>
                  <View style={{ flexDirection: "row", flexWrap: "wrap", gap: 6 }}>
                    {chip(Wrench, s.open_tickets, "kayıt")}
                  </View>
                </View>
                <ChevronRight size={20} color={colors.yaziSoluk} />
              </Pressable>
            );
          })}
        </View>
      )}
    </ScrollView>
  );
}
