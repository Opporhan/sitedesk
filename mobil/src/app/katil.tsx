import { Redirect, router } from "expo-router";
import { useState } from "react";
import { KeyboardAvoidingView, Platform, View } from "react-native";
import { CheckCircle2, Send } from "lucide-react-native";
import { useAuth } from "@/auth";
import { NETWORK_ERROR, supabase } from "@/lib/supabase";
import { unitWords } from "@/lib/words";
import { BlockPicker } from "@/components/unit-grid";
import { BackHeader, Body, Button, Card, Choice, EmptyState, Field, Grid, Muted, Notice, Screen, SectionLabel } from "@/components/ui";
import { FONT } from "@/theme";

type Found = { site_id: string; name: string; type: string; units: { id: string; block: string; no: string }[] };

// Site koduyla katılma: kod → site ve daireler → daire + malik/kiracı → istek; sitenin yöneticisi onaylayınca girer
export default function JoinSite() {
  const { session, context, reloadContext } = useAuth();
  const [code, setCode] = useState("");
  const [site, setSite] = useState<Found | null>(null);
  const [block, setBlock] = useState("");
  const [unitId, setUnitId] = useState<string | null>(null);
  const [relation, setRelation] = useState<"malik" | "kiraci">("malik");
  const [name, setName] = useState(context?.full_name ?? "");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [sent, setSent] = useState<string | null>(null);
  if (!session) return <Redirect href="/giris" />;
  const w = unitWords(site?.type);
  const blocks = [...new Set((site?.units ?? []).map((u) => u.block))];

  async function find() {
    setError(null);
    setBusy(true);
    const { data, error: e } = await supabase.rpc("site_by_code", { p_code: code.trim() });
    setBusy(false);
    if (e) return setError(e.message.includes("fetch") ? NETWORK_ERROR : "Kod kontrol edilemedi. Tekrar deneyin.");
    if (!data) return setError("Bu kodla bir site bulunamadı. Kodu yönetiminizden kontrol edin.");
    const s = data as Found;
    s.units.sort((a, b) => a.block.localeCompare(b.block, "tr") || a.no.localeCompare(b.no, "tr", { numeric: true }));
    setSite(s);
    setBlock(s.units[0]?.block ?? "");
    setUnitId(null);
  }

  async function send() {
    if (!site || !unitId) return setError(`${w.Nom.slice(0, 1)}${w.acc.slice(1)} seçin.`);
    if (name.trim().length < 3) return setError("Adınızı ve soyadınızı yazın.");
    setBusy(true);
    setError(null);
    const { error: e } = await supabase.rpc("request_join", { p_code: code.trim(), p_unit_id: unitId, p_full_name: name.trim(), p_relation: relation });
    setBusy(false);
    if (e)
      return setError(
        e.message.includes("fetch") ? NETWORK_ERROR : e.code === "SD061" ? `Bu ${w.dat} zaten bağlısınız.` : e.code === "SD062" ? "Bugün çok fazla istek gönderdiniz. Yarın tekrar deneyin." : e.code === "SD063" ? "Yönetiminiz size davet göndermiş. WhatsApp'tan gelen davet bağlantısına dokunun ya da giriş ekranında “Davet veya Şifre Kodum Var” deyip kodu yazın." : e.code === "SD060" ? "Site kodu artık geçerli değil. Yönetiminizden yeni kodu isteyin." : "İstek gönderilemedi. Tekrar deneyin."
      );
    const u = site.units.find((x) => x.id === unitId);
    setSent(`${site.name} · ${u?.block}-${u?.no}`);
    reloadContext();
  }

  if (sent)
    return (
      <Screen title="İstek gönderildi" header={<BackHeader />}>
        <EmptyState icon={CheckCircle2} title={sent} text="İsteğiniz site yönetimine gitti. Yönetim onaylayınca telefonunuza bildirim gelir ve uygulamayı kullanmaya başlarsınız." />
        <Button label="Tamam" onPress={() => router.replace("/")} />
      </Screen>
    );

  return (
    <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === "ios" ? "padding" : undefined}>
      <Screen title="Siteme Katıl" header={<BackHeader />} footer={site ? <Button label="Katılma İsteği Gönder" icon={Send} onPress={send} loading={busy} /> : undefined}>
        {!site ? (
          <>
            <Muted>Site yönetiminizin paylaştığı 6 haneli site kodunu yazın.</Muted>
            <Field label="Site kodu" value={code} onChangeText={(t) => setCode(t.toUpperCase())} autoCapitalize="characters" autoCorrect={false} maxLength={12} placeholder="ÖRN. K7M3PQ" onSubmitEditing={find} />
            {error && <Notice tone="hata" text={error} />}
            <Button label="Devam" onPress={find} loading={busy} disabled={code.trim().length < 6} />
            <Muted>Kodu bilmiyorsanız site yönetiminize sorun. Yönetiminiz size ayrıca davet de gönderebilir.</Muted>
          </>
        ) : (
          <>
            <Card>
              <Body style={{ fontFamily: FONT.kalin }}>{site.name}</Body>
              <Muted>{`${w.Nom.slice(0, 1)}${w.acc.slice(1)} seçin, sonra isteği gönderin.`}</Muted>
            </Card>
            {site.units.length === 0 ? (
              <Notice tone="bekliyor" text={`Bu sitede henüz ${w.nom} eklenmemiş. Yönetiminizden eklemesini isteyin.`} />
            ) : (
              <>
                {blocks.length > 1 && <BlockPicker blocks={blocks} value={block} onChange={setBlock} />}
                <Grid>
                  {site.units
                    .filter((u) => blocks.length < 2 || u.block === block)
                    .map((u) => (
                      <Choice key={u.id} label={`${u.block}-${u.no}`} selected={unitId === u.id} onPress={() => setUnitId(u.id)} />
                    ))}
                </Grid>
              </>
            )}
            <SectionLabel>{`BU ${w.nom.toLocaleUpperCase("tr-TR")}`}</SectionLabel>
            <View accessibilityRole="radiogroup" style={{ flexDirection: "row", gap: 8 }}>
              <Choice label="Malik (ev sahibi)" selected={relation === "malik"} onPress={() => setRelation("malik")} />
              <Choice label="Kiracı" selected={relation === "kiraci"} onPress={() => setRelation("kiraci")} />
            </View>
            <Field label="Ad soyad" value={name} onChangeText={setName} autoCapitalize="words" maxLength={100} />
            {error && <Notice tone="hata" text={error} />}
            <Muted>Yönetim, adınızı ve telefon numaranızı görüp onaylar.</Muted>
          </>
        )}
      </Screen>
    </KeyboardAvoidingView>
  );
}
