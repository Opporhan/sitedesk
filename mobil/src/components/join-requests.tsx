import * as Clipboard from "expo-clipboard";
import { useCallback, useEffect, useState } from "react";
import { Alert, Linking, Pressable, Text, View } from "react-native";
import { Check, Copy, MessageCircle, RefreshCw, X } from "lucide-react-native";
import { NETWORK_ERROR, supabase, WEB_URL } from "@/lib/supabase";
import { formatPhone } from "@/lib/phone";
import { useAutoRefresh } from "@/lib/use-auto-refresh";
import { Body, Button, Card, ListGroup, ListRow, Muted, Notice, SectionLabel } from "@/components/ui";
import { FONT, useTheme } from "@/theme";

type Request = { id: string; full_name: string; phone: string; relation: string; created_at: string; units: { no: string; blocks: { name: string } | null } | null };

// Sitenin kodu: sakinler bu kodla "Siteme katıl" der; yönetici WhatsApp grubuna paylaşır, gerekirse yeniler (eski kod çalışmaz)
export function SiteCodeCard({ siteId, siteName }: { siteId: string; siteName: string }) {
  const { colors } = useTheme();
  const [code, setCode] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [info, setInfo] = useState<string | null>(null);
  useEffect(() => {
    supabase.from("sites").select("join_code").eq("id", siteId).maybeSingle().then(({ data }) => setCode((data?.join_code as string) ?? null));
  }, [siteId]);
  if (!code) return null;
  const message = [
    `Merhaba komşular, ${siteName} artık SiteDesk kullanıyor: arıza ve taleplerinizi bildirip takip edebilir, kargonuz ve misafiriniz geldiğinde haber alabilirsiniz.`,
    "",
    `1) SiteDesk uygulamasını indirin: ${WEB_URL}`,
    `2) “Siteme Katıl” deyin ve site kodunu yazın: ${code}`,
    "3) Dairenizi seçin; yönetim onaylayınca kullanmaya başlarsınız.",
    "",
    `${siteName} Yönetimi`,
  ].join("\n");

  function renew() {
    Alert.alert("Kod yenilensin mi?", "Eski kod artık çalışmaz. Yeni kodu sakinlerle tekrar paylaşmanız gerekir.", [
      { text: "Vazgeç", style: "cancel" },
      {
        text: "Yenile",
        style: "destructive",
        onPress: async () => {
          setBusy(true);
          const { data, error } = await supabase.rpc("renew_join_code", { p_site_id: siteId });
          setBusy(false);
          if (!error) setCode(data as string);
        },
      },
    ]);
  }

  return (
    <Card>
      <Body style={{ fontFamily: FONT.kalin }}>Site kodu</Body>
      <Text selectable style={{ fontFamily: FONT.cokKalin, fontSize: 32, letterSpacing: 4, color: colors.yazi }}>{code}</Text>
      <Muted>Sakinler uygulamada “Siteme Katıl” deyip bu kodu yazar, dairesini seçer; siz onaylayınca girerler. Tek tek davet göndermenize gerek kalmaz.</Muted>
      <Button label="WhatsApp Grubuna Paylaş" icon={MessageCircle} onPress={() => Linking.openURL(`https://wa.me/?text=${encodeURIComponent(message)}`).catch(() => {})} />
      <View style={{ flexDirection: "row", gap: 8 }}>
        <View style={{ flex: 1 }}>
          <Button
            label="Mesajı Kopyala"
            icon={Copy}
            variant="ikincil"
            onPress={async () => {
              await Clipboard.setStringAsync(message);
              setInfo("Mesaj kopyalandı.");
            }}
          />
        </View>
        <View style={{ flex: 1 }}>
          <Button label="Kodu Yenile" icon={RefreshCw} variant="ikincil" loading={busy} onPress={renew} />
        </View>
      </View>
      {info && <Muted>{info}</Muted>}
    </Card>
  );
}

// Site koduyla gelen katılma istekleri: yönetici onaylar (kişi daireye bağlanır) ya da reddeder
export function JoinRequests({ siteId, onChange }: { siteId: string; onChange?: () => void }) {
  const { colors } = useTheme();
  const [list, setList] = useState<Request[]>([]);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    const { data } = await supabase
      .from("join_requests")
      .select("id, full_name, phone, relation, created_at, units(no, blocks(name))")
      .eq("site_id", siteId)
      .eq("status", "bekliyor")
      .order("created_at");
    setList((data ?? []) as unknown as Request[]);
  }, [siteId]);
  useAutoRefresh(load);

  async function decide(r: Request, approve: boolean) {
    setBusy(r.id);
    setError(null);
    const { error: e } = await supabase.rpc("decide_join", { p_request_id: r.id, p_approve: approve });
    setBusy(null);
    if (e)
      return setError(
        e.message.includes("fetch")
          ? NETWORK_ERROR
          : e.code === "SD063"
            ? `${r.full_name} için daha önce davet gönderilmiş; bu istek onaylanamaz. Kişi kendisine gelen davetle girmeli (gerekirse Davet bölümünden yeniden gönderin). İsteği ✕ ile kapatabilirsiniz.`
            : "İşlem yapılamadı. Tekrar deneyin."
      );
    await load();
    onChange?.();
  }

  if (!list.length) return null;
  const btn = (bg: string) => ({ width: 44, height: 44, borderRadius: 22, alignItems: "center" as const, justifyContent: "center" as const, backgroundColor: bg });
  return (
    <>
      <SectionLabel>{`KATILMA İSTEKLERİ (${list.length})`}</SectionLabel>
      <ListGroup>
        {list.map((r) => {
          const unit = r.units ? `${r.units.blocks?.name ?? ""}-${r.units.no}` : "";
          return (
            <ListRow
              key={r.id}
              title={`${unit} · ${r.full_name}`}
              subtitle={`${r.relation === "kiraci" ? "Kiracı" : "Malik"} · ${formatPhone(r.phone)}`}
              chevron={false}
              onPress={() => Linking.openURL(`tel:+${r.phone}`).catch(() => {})}
              right={
                <View style={{ flexDirection: "row", gap: 8, opacity: busy === r.id ? 0.5 : 1 }}>
                  <Pressable accessibilityRole="button" accessibilityLabel={`${r.full_name} isteğini reddet`} disabled={!!busy} onPress={() => decide(r, false)} style={btn(colors.hataZemin)}>
                    <X size={20} color={colors.hata} />
                  </Pressable>
                  <Pressable accessibilityRole="button" accessibilityLabel={`${r.full_name} isteğini onayla`} disabled={!!busy} onPress={() => decide(r, true)} style={btn(colors.vurgu)}>
                    <Check size={20} color={colors.vurguYazi} />
                  </Pressable>
                </View>
              }
            />
          );
        })}
      </ListGroup>
      <Muted style={{ paddingHorizontal: 4 }}>Onaylamadan önce kişinin adına dokunup arayarak gerçekten o olduğunu doğrulayın; sonra ✓ ile onaylayın. Tanımıyorsanız ✕ ile reddedin.</Muted>
      {error && <Notice tone="hata" text={error} />}
    </>
  );
}
