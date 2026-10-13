import { Redirect, router } from "expo-router";
import { useEffect, useState } from "react";
import { Image, KeyboardAvoidingView, Platform, Pressable, Switch, Text, View } from "react-native";
import { Camera, ClipboardList, Images, MessageSquareWarning, Send, Video, Wrench, X, type LucideIcon } from "lucide-react-native";
import { useAuth } from "@/auth";
import { useOutbox } from "@/outbox";
import { BlockPicker } from "@/components/unit-grid";
import { supabase } from "@/lib/supabase";
import { captureMedia, MAX_PHOTOS, pickFromLibrary, type PickedMedia } from "@/lib/media";
import { KIND_LABEL, LOCATION_LABEL, type TicketKind, type TicketLocation } from "@/lib/tickets";
import { BackHeader, Button, Choice, Field, Grid, Muted, Notice, Screen, SectionLabel, Segmented } from "@/components/ui";
import { FONT, useTheme } from "@/theme";
import { useWords } from "@/lib/words";

const KINDS: { key: TicketKind; icon: LucideIcon }[] = [
  { key: "ariza", icon: Wrench },
  { key: "talep", icon: ClipboardList },
  { key: "sikayet", icon: MessageSquareWarning },
];

// Fotoğraf/video ekleme kutucuğu
function MediaTile({ icon: Icon, label, disabled, onPress }: { icon: LucideIcon; label: string; disabled?: boolean; onPress: () => void }) {
  const { colors } = useTheme();
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityState={{ disabled }}
      disabled={disabled}
      onPress={onPress}
      style={({ pressed }) => ({ flex: 1, minHeight: 84, borderRadius: 14, backgroundColor: colors.kutu, alignItems: "center", justifyContent: "center", gap: 6, opacity: disabled ? 0.4 : pressed ? 0.8 : 1 })}
    >
      <Icon size={24} color={colors.vurgu} strokeWidth={1.75} />
      <Text style={{ fontFamily: FONT.orta, fontSize: 14, color: colors.yazi }}>{label}</Text>
    </Pressable>
  );
}

// Yeni kayıt (sakin kendi dairesi için; yönetim ve danışma sitenin bir dairesi için) (tür, yer, başlık, açıklama, en fazla 5 fotoğraf ya da 1 video, acil). Gönder'e basınca giden kutusuna girer.
export default function NewTicketScreen() {
  const w = useWords();
  const { colors } = useTheme();
  const { session, context, active } = useAuth();
  const { enqueue } = useOutbox();
  // Yönetim ve danışma sitenin herhangi bir dairesi için kayıt açar (sakin adına); sakin kendi daireleri için
  const staff = active.kind === "yonetici" || active.kind === "danisma" ? active : null;
  const [siteUnits, setSiteUnits] = useState<{ block: string; units: { id: string; no: string }[] }[]>([]);
  const [block, setBlock] = useState<string | null>(null);
  useEffect(() => {
    if (!staff) return;
    supabase
      .from("blocks")
      .select("name, units(id, no)")
      .eq("site_id", staff.siteId)
      .order("name")
      .then(({ data }) => {
        const rows = ((data ?? []) as { name: string; units: { id: string; no: string }[] }[]).map((b) => ({
          block: b.name,
          units: [...b.units].sort((p, q) => p.no.localeCompare(q.no, "tr", { numeric: true })),
        }));
        setSiteUnits(rows);
        setBlock(rows[0]?.block ?? null);
      });
  }, [staff?.siteId]); // eslint-disable-line react-hooks/exhaustive-deps
  const units = staff
    ? siteUnits.flatMap((b) => b.units.map((u) => ({ unit_id: u.id, site_id: staff.siteId, site_name: staff.siteName, label: `${b.block}-${u.no}` })))
    : (context?.units ?? []);
  const [unitId, setUnitId] = useState(staff ? "" : (context?.units[0]?.unit_id ?? ""));
  const [kind, setKind] = useState<TicketKind>("ariza");
  const [location, setLocation] = useState<TicketLocation>("daire");
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [urgent, setUrgent] = useState(false);
  const [media, setMedia] = useState<PickedMedia[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  if (!session) return <Redirect href="/" />;

  const hasVideo = media.some((m) => m.kind === "video");
  const photoSlots = hasVideo ? 0 : MAX_PHOTOS - media.length;

  async function add(fn: () => Promise<PickedMedia | PickedMedia[] | string | null>) {
    setError(null);
    try {
      const r = await fn();
      if (r === null) return;
      if (typeof r === "string") return setError(r);
      const list = Array.isArray(r) ? r : [r];
      if (list.some((m) => m.kind === "video") && media.length) return setError("Video eklemek için önce fotoğrafları çıkarın (en fazla 5 fotoğraf ya da 1 video).");
      setMedia([...media, ...list].slice(0, list[0]?.kind === "video" ? 1 : MAX_PHOTOS));
    } catch {
      setError("Dosya eklenemedi. Lütfen tekrar deneyin.");
    }
  }

  async function submit() {
    setError(null);
    const unit = units.find((u) => u.unit_id === unitId);
    if (!unit) return setError(staff ? `Hangi ${w.nom} için olduğunu seçin.` : `${w.Nom.slice(0, 1)}${w.acc.slice(1)} seçin.`);
    if (title.trim().length < 3) return setError("Kısa bir başlık yazın (en az 3 harf).");
    setBusy(true);
    try {
      await enqueue({ siteId: unit.site_id, unitId: unit.unit_id, unitLabel: unit.label, kind, location, title: title.trim(), description: description.trim(), urgent, media });
      router.back();
    } catch {
      setError("Kayıt hazırlanamadı. Lütfen tekrar deneyin.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === "ios" ? "padding" : undefined}>
      <Screen title="Yeni kayıt" header={<BackHeader />} footer={<Button label="Gönder" icon={Send} onPress={submit} loading={busy} />}>
        {staff && (
          <>
            <SectionLabel>{`HANGİ ${w.nom.toLocaleUpperCase("tr-TR")} İÇİN?`}</SectionLabel>
            {siteUnits.length > 1 && <BlockPicker blocks={siteUnits.map((b) => b.block)} value={block ?? ""} onChange={setBlock} />}
            <Grid>
              {siteUnits
                .filter((b) => b.block === block)
                .flatMap((b) => b.units.map((u) => ({ id: u.id, label: `${b.block}-${u.no}` })))
                .map((u) => (
                  <Choice key={u.id} label={u.label} selected={unitId === u.id} onPress={() => setUnitId(u.id)} />
                ))}
            </Grid>
            {siteUnits.length === 0 && <Muted>{`Bu sitede henüz ${w.nom} yok. Kişiler › ${w.Plural} bölümünden ekleyin.`}</Muted>}
          </>
        )}
        {!staff && units.length > 1 && (
          <>
            <SectionLabel>{w.nom.toLocaleUpperCase("tr-TR")}</SectionLabel>
            <Grid minItemWidth={140}>
              {units.map((u) => (
                <Choice key={u.unit_id} label={u.label} selected={unitId === u.unit_id} onPress={() => setUnitId(u.unit_id)} />
              ))}
            </Grid>
          </>
        )}

        <SectionLabel>NE BİLDİRMEK İSTİYORSUNUZ?</SectionLabel>
        <View accessibilityRole="radiogroup" style={{ flexDirection: "row", gap: 8 }}>
          {KINDS.map((k) => (
            <View key={k.key} style={{ flex: 1 }}>
              <Choice label={KIND_LABEL[k.key]} icon={k.icon} selected={kind === k.key} onPress={() => setKind(k.key)} style={{ minHeight: 76 }} />
            </View>
          ))}
        </View>

        <SectionLabel>NEREDE?</SectionLabel>
        <Segmented value={location} onChange={setLocation} options={(["daire", "ortak"] as TicketLocation[]).map((l) => ({ key: l, label: l === "ortak" ? LOCATION_LABEL.ortak : staff ? `${w.Nom} içi` : w.mine }))} />

        <Field label="Başlık" value={title} onChangeText={setTitle} maxLength={80} placeholder="Ör. Banyo musluğu damlatıyor" />
        <Field label="Açıklama (isteğe bağlı)" value={description} onChangeText={setDescription} maxLength={1000} multiline placeholder="Ne zamandan beri, tam olarak nerede…" style={{ minHeight: 110, textAlignVertical: "top", paddingTop: 14 }} />

        <SectionLabel>FOTOĞRAF / VİDEO</SectionLabel>
        {media.length > 0 && (
          <Grid minItemWidth={58} gap={8}>
            {media.map((m, i) => (
              <View key={m.uri} style={{ width: "100%", aspectRatio: 1, borderRadius: 12, overflow: "hidden", backgroundColor: colors.kutuKoyu, alignItems: "center", justifyContent: "center" }}>
                {m.kind === "foto" ? <Image source={{ uri: m.uri }} style={{ width: "100%", height: "100%" }} resizeMode="cover" /> : <Video size={30} color={colors.yazi} strokeWidth={1.75} />}
                {m.kind === "video" && m.durationMs ? (
                  <Text style={{ position: "absolute", bottom: 6, left: 8, fontFamily: FONT.kalin, fontSize: 13, color: colors.yazi }}>{Math.round(m.durationMs / 1000)} sn</Text>
                ) : null}
                <Pressable
                  accessibilityRole="button"
                  accessibilityLabel="Dosyayı çıkar"
                  onPress={() => setMedia(media.filter((_, j) => j !== i))}
                  hitSlop={10}
                  style={{ position: "absolute", top: 3, right: 3, width: 26, height: 26, borderRadius: 13, backgroundColor: colors.kutu, alignItems: "center", justifyContent: "center" }}
                >
                  <X size={14} color={colors.yazi} />
                </Pressable>
              </View>
            ))}
          </Grid>
        )}
        <View style={{ flexDirection: "row", gap: 8 }}>
          <MediaTile icon={Camera} label="Fotoğraf" disabled={photoSlots <= 0} onPress={() => add(() => captureMedia("foto"))} />
          <MediaTile icon={Video} label="Video" disabled={media.length > 0} onPress={() => add(() => captureMedia("video"))} />
          <MediaTile icon={Images} label="Galeri" disabled={photoSlots <= 0} onPress={() => add(() => pickFromLibrary(photoSlots, media.length === 0))} />
        </View>
        <Muted style={{ marginTop: -8, paddingHorizontal: 4 }}>En fazla 5 fotoğraf ya da 30 saniyelik 1 video.</Muted>

        <View style={{ flexDirection: "row", alignItems: "center", gap: 12, backgroundColor: urgent ? colors.hataZemin : colors.kutu, borderRadius: 14, paddingVertical: 12, paddingHorizontal: 16 }}>
          <View style={{ flex: 1, gap: 2 }}>
            <Text style={{ fontFamily: FONT.kalin, fontSize: 16, color: urgent ? colors.hata : colors.yazi }}>Acil</Text>
            <Muted>Su baskını, elektrik, asansörde kalma gibi.</Muted>
          </View>
          <Switch value={urgent} onValueChange={setUrgent} trackColor={{ true: colors.hata, false: colors.cizgi }} accessibilityLabel="Acil" />
        </View>

        {error && <Notice tone="hata" text={error} />}
      </Screen>
    </KeyboardAvoidingView>
  );
}
