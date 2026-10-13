import { useCallback, useState, useRef } from "react";
import { Alert, Linking, Pressable, RefreshControl, ScrollView, Text, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { BellRing, MessageCircle, Package, PackageCheck } from "lucide-react-native";
import { useAuth } from "@/auth";
import { NETWORK_ERROR, supabase } from "@/lib/supabase";
import { useAutoRefresh } from "@/lib/use-auto-refresh";
import { formatTime, isTodayTR, uuid } from "@/lib/uuid";
import { formatDateTime } from "@/lib/tickets";
import { Sheet } from "@/components/sheet";
import { UnitGrid, type GridUnit } from "@/components/unit-grid";
import { Button, EmptyState, Field, ListGroup, ListRow, Muted, Notice, ScreenTitle, Segmented } from "@/components/ui";
import { FONT, SIZE, useTheme } from "@/theme";
import { useWords } from "@/lib/words";

type Pkg = { id: string; unit_id: string; note: string | null; received_at: string; delivered_at: string | null; delivered_to: string | null; units: { no: string; blocks: { name: string } | null } | null };
type Person = { full_name: string; phone: string | null; user_id: string | null };
type Tab = "yeni" | "bekleyen" | "teslim";

const label = (p: Pkg) => (p.units ? `${p.units.blocks?.name ?? ""}-${p.units.no}` : "");

// Danışma › Kargo (kargoyu sadece danışma ve sakin görür): daireye dokun → kaydet (sakine bildirim) · bekleyenler → tekrar haber ver / teslim et · bugün teslim edilenler (geri al)
export default function DeskPackages() {
  const w = useWords();
  const { colors } = useTheme();
  const insets = useSafeAreaInsets();
  const { active } = useAuth();
  const siteId = active.kind === "danisma" ? active.siteId : "";
  const siteName = active.kind === "danisma" ? active.siteName : "";
  const [tab, setTab] = useState<Tab>("yeni");
  const [pending, setPending] = useState<Pkg[]>([]);
  const [delivered, setDelivered] = useState<Pkg[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  // Kaydet paneli
  const [unit, setUnit] = useState<GridUnit | null>(null);
  const [people, setPeople] = useState<Person[]>([]);
  const [note, setNote] = useState("");
  const [clientId, setClientId] = useState(uuid());
  const [saved, setSaved] = useState(false);
  // Teslim paneli
  const [deliver, setDeliver] = useState<Pkg | null>(null);
  const [to, setTo] = useState("");
  const [busy, setBusy] = useState(false);
  const [info, setInfo] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!siteId) return;
    const cols = "id, unit_id, note, received_at, delivered_at, delivered_to, units(no, blocks(name))";
    const since = new Date(Date.now() - 36 * 3600 * 1000).toISOString();
    const [p, d] = await Promise.all([
      supabase.from("packages").select(cols).eq("site_id", siteId).is("delivered_at", null).order("received_at"),
      supabase.from("packages").select(cols).eq("site_id", siteId).gte("delivered_at", since).order("delivered_at", { ascending: false }),
    ]);
    if (p.error) return setError(p.error.message.includes("fetch") ? NETWORK_ERROR : "Kargolar alınamadı.");
    setError(null);
    setPending((p.data ?? []) as unknown as Pkg[]);
    setDelivered(((d.data ?? []) as unknown as Pkg[]).filter((x) => x.delivered_at && isTodayTR(x.delivered_at)));
  }, [siteId]);
  useAutoRefresh(load);

  // Açık olan pencerenin dairesi: geç gelen cevap başka dairenin sakinlerini göstermesin
  const peopleFor = useRef<string | null>(null);
  async function loadPeople(unitId: string) {
    peopleFor.current = unitId;
    setPeople([]);
    const { data } = await supabase.from("unit_residents").select("residents(full_name, phone, user_id)").eq("unit_id", unitId).is("ended_on", null);
    if (peopleFor.current !== unitId) return;
    setPeople(((data ?? []) as unknown as { residents: Person | null }[]).map((r) => r.residents).filter(Boolean) as Person[]);
  }

  async function openUnit(u: GridUnit) {
    setUnit(u);
    setNote("");
    setSaved(false);
    setClientId(uuid());
    setError(null);
    await loadPeople(u.id);
  }

  async function save() {
    if (!unit) return;
    setBusy(true);
    setError(null);
    // Aynı kimlikle tekrar gönderilirse ikinci kargo açılmaz (zayıf internet)
    const { error: e } = await supabase.rpc("record_package", { p_client_id: clientId, p_unit_id: unit.id, p_note: note.trim() || null });
    setBusy(false);
    if (e) return setError(e.message.includes("fetch") ? `${NETWORK_ERROR} Tekrar "Kaydet"e basın.` : "Kargo kaydedilemedi.");
    setSaved(true);
    load();
    // Uygulamayı kullanan sakin kargoyu "Kargolarım"da görür; kullanmayan ve telefonu olan varsa WhatsApp ile haber verilir
    if (!people.some((p) => !p.user_id && p.phone)) setUnit(null);
  }

  async function doDeliver() {
    if (!deliver) return;
    setBusy(true);
    const { error: e } = await supabase.rpc("deliver_package", { p_package_id: deliver.id, p_to: to.trim() || null });
    setBusy(false);
    if (e) return setError(e.message.includes("fetch") ? NETWORK_ERROR : "Teslim kaydedilemedi.");
    setDeliver(null);
    load();
  }

  // Bekleyen kargo için sakine telefon bildirimiyle yeniden haber ver (aynı kargoya saatte bir)
  async function remind(p: Pkg) {
    setError(null);
    setInfo(null);
    const { error: e } = await supabase.rpc("remind_package", { p_package_id: p.id });
    if (!e) return setInfo(`${label(p)} sakinlerine “Kargonuz danışmada bekliyor” bildirimi gönderildi.`);
    setError(e.message.includes("fetch") ? NETWORK_ERROR : e.code === "SD030" ? "Bu kargo için az önce haber verildi. Bir saat sonra tekrar gönderebilirsiniz." : "Haber verilemedi.");
  }

  async function openDeliver(p: Pkg) {
    setDeliver(p);
    setTo("");
    await loadPeople(p.unit_id);
  }

  function rowMenu(p: Pkg) {
    if (!isTodayTR(p.received_at)) return;
    Alert.alert(`${label(p)} kargosu`, `Yanlış ${w.dat} mi girildi?`, [
      { text: "Vazgeç", style: "cancel" },
      {
        text: "Yanlış Kayıt, Sil",
        style: "destructive",
        onPress: async () => {
          const { error: e } = await supabase.rpc("delete_package", { p_package_id: p.id });
          if (e) setError("Silinemedi. Sadece bugün girilen, teslim edilmemiş kargo silinebilir.");
          load();
        },
      },
    ]);
  }

  const counts: Record<string, number> = {};
  for (const p of pending) counts[p.unit_id] = (counts[p.unit_id] ?? 0) + 1;
  const waText = (name: string) => `Merhaba ${name}, ${unit?.label} adına kargonuz danışmaya ulaştı. Danışmadan teslim alabilirsiniz.\n\n${siteName} Danışma`;

  return (
    <View style={{ flex: 1, backgroundColor: colors.zemin }}>
      <ScrollView
        contentContainerStyle={{ paddingTop: insets.top + 8, paddingHorizontal: SIZE.kenar, paddingBottom: 40, gap: 18 }}
        refreshControl={<RefreshControl refreshing={refreshing} tintColor={colors.vurgu} onRefresh={async () => { setRefreshing(true); await load(); setRefreshing(false); }} />}
      >
        <ScreenTitle title="Kargo" subtitle={siteName} />
        <Segmented
          value={tab}
          onChange={setTab}
          options={[
            { key: "yeni", label: "Yeni kargo" },
            { key: "bekleyen", label: `Bekleyen${pending.length ? ` (${pending.length})` : ""}` },
            { key: "teslim", label: "Bugün verilen" },
          ]}
        />
        {error && !unit && !deliver && <Notice tone="hata" text={error} />}
        {info && !error && <Notice tone="basari" text={info} />}

        {tab === "yeni" && (
          <>
            <Muted style={{ paddingHorizontal: 4 }}>{`Kargonun geldiği ${w.dat} dokunun.`}</Muted>
            <UnitGrid siteId={siteId} onPick={openUnit} counts={counts} />
          </>
        )}

        {tab === "bekleyen" &&
          (pending.length === 0 ? (
            <EmptyState icon={Package} title="Bekleyen kargo yok" text="Kaydedilen kargolar teslim edilene kadar burada durur." />
          ) : (
            <>
              <ListGroup>
                {pending.map((p) => (
                  <Pressable key={p.id} onLongPress={() => rowMenu(p)}>
                    <ListRow
                      title={label(p)}
                      subtitle={`${isTodayTR(p.received_at) ? `Bugün ${formatTime(p.received_at)}` : formatDateTime(p.received_at)}${p.note ? ` · ${p.note}` : ""}`}
                      right={
                        <View style={{ flexDirection: "row", gap: 8 }}>
                          <Pressable
                            accessibilityRole="button"
                            accessibilityLabel={`${label(p)} sakinlerine tekrar haber ver`}
                            onPress={() => remind(p)}
                            style={{ width: 44, minHeight: 44, borderRadius: 12, alignItems: "center", justifyContent: "center", backgroundColor: colors.kutuKoyu }}
                          >
                            <BellRing size={20} color={colors.vurgu} />
                          </Pressable>
                          <Pressable accessibilityRole="button" onPress={() => openDeliver(p)} style={{ minHeight: 44, paddingHorizontal: 14, borderRadius: 12, justifyContent: "center", backgroundColor: colors.vurgu }}>
                            <Text style={{ fontFamily: FONT.kalin, fontSize: 15, color: colors.vurguYazi }}>Teslim et</Text>
                          </Pressable>
                        </View>
                      }
                    />
                  </Pressable>
                ))}
              </ListGroup>
              <Muted style={{ paddingHorizontal: 4 }}>{`Zil düğmesi sakine “Kargonuz danışmada bekliyor” bildirimini tekrar gönderir. Yanlış ${w.dat} girilen kargoyu silmek için satıra basılı tutun (sadece bugün girilenler).`}</Muted>
            </>
          ))}

        {tab === "teslim" &&
          (delivered.length === 0 ? (
            <EmptyState icon={PackageCheck} title="Bugün teslim edilen yok" text="Teslim edilen kargolar burada görünür; yanlışlıkla teslim edildiyse geri alabilirsiniz." />
          ) : (
            <ListGroup>
              {delivered.map((p) => (
                <ListRow
                  key={p.id}
                  title={label(p)}
                  subtitle={`${formatTime(p.delivered_at!)} teslim edildi${p.delivered_to ? ` · ${p.delivered_to}` : ""}`}
                  right={
                    <Text
                      accessibilityRole="button"
                      onPress={async () => {
                        const { error: e } = await supabase.rpc("undo_package_delivery", { p_package_id: p.id });
                        if (e) setError("Geri alınamadı.");
                        load();
                      }}
                      style={{ fontFamily: FONT.orta, fontSize: 15, color: colors.vurgu, padding: 10 }}
                    >
                      Geri al
                    </Text>
                  }
                />
              ))}
            </ListGroup>
          ))}
      </ScrollView>

      {/* Kargo kaydet */}
      <Sheet visible={!!unit} onClose={() => setUnit(null)} title={unit?.label ?? ""} subtitle={saved ? "Kargo kaydedildi" : "Yeni kargo"}>
        {!saved ? (
          <>
            <Field label="Not (isteğe bağlı)" value={note} onChangeText={setNote} maxLength={200} placeholder="Ör. büyük koli, soğuk zincir" />
            {error && <Notice tone="hata" text={error} />}
            <Button label="Kaydet" icon={Package} onPress={save} loading={busy} />
            <Muted>Kaydedince uygulamayı kullanan sakinlere “Kargonuz geldi” bildirimi gider.</Muted>
          </>
        ) : (
          <>
            <Notice tone="basari" text="Kargo kaydedildi ve uygulamayı kullanan sakinlere bildirim gitti. Uygulamayı kullanmayan sakinlere WhatsApp'tan haber verebilirsiniz." />
            <ListGroup>
              {people
                .filter((p) => !p.user_id && p.phone)
                .map((p) => (
                  <ListRow
                    key={p.phone!}
                    title={p.full_name}
                    subtitle="Uygulamayı kullanmıyor"
                    right={<MessageCircle size={22} color={colors.basari} />}
                    onPress={() => Linking.openURL(`https://wa.me/${p.phone}?text=${encodeURIComponent(waText(p.full_name))}`)}
                    chevron={false}
                  />
                ))}
            </ListGroup>
            <Button label="Tamam" variant="ikincil" onPress={() => setUnit(null)} />
          </>
        )}
      </Sheet>

      {/* Teslim et */}
      <Sheet visible={!!deliver} onClose={() => setDeliver(null)} title={deliver ? label(deliver) : ""} subtitle="Teslim et">
        {people.length > 0 && (
          <View style={{ flexDirection: "row", flexWrap: "wrap", gap: 8 }}>
            {people.map((p) => (
              <Pressable
                key={p.full_name}
                accessibilityRole="button"
                onPress={() => setTo(p.full_name)}
                style={{ minHeight: 44, paddingHorizontal: 14, borderRadius: 22, justifyContent: "center", borderWidth: 1.5, borderColor: to === p.full_name ? colors.vurgu : "transparent", backgroundColor: to === p.full_name ? colors.vurguAcik : colors.kutu }}
              >
                <Text style={{ fontFamily: FONT.orta, fontSize: 15, color: colors.yazi }}>{p.full_name}</Text>
              </Pressable>
            ))}
          </View>
        )}
        <Field label="Kime teslim edildi? (isteğe bağlı)" value={to} onChangeText={setTo} maxLength={100} placeholder="Ad soyad" />
        {error && <Notice tone="hata" text={error} />}
        <Button label="Teslim Et" icon={PackageCheck} onPress={doDeliver} loading={busy} />
      </Sheet>
    </View>
  );
}
