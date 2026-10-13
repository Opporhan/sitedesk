import { useCallback, useState, useRef } from "react";
import { Alert, Linking, Pressable, RefreshControl, ScrollView, Text, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { DoorOpen, LogIn, Phone, UserCheck } from "lucide-react-native";
import { useAuth } from "@/auth";
import { NETWORK_ERROR, supabase } from "@/lib/supabase";
import { formatPhone } from "@/lib/phone";
import { useAutoRefresh } from "@/lib/use-auto-refresh";
import { formatTime, isTodayTR, uuid } from "@/lib/uuid";
import { formatDateTime } from "@/lib/tickets";
import { Sheet } from "@/components/sheet";
import { UnitGrid, type GridUnit } from "@/components/unit-grid";
import { Button, EmptyState, Field, ListGroup, ListRow, Muted, Notice, ScreenTitle, SectionLabel, Segmented } from "@/components/ui";
import { FONT, SIZE, useTheme } from "@/theme";
import { useWords } from "@/lib/words";

type Visit = { id: string; visitor_name: string; plate: string | null; kind: "misafir" | "hizmet"; arrived_at: string; departed_at: string | null; units: { no: string; blocks: { name: string } | null } | null };
type Person = { full_name: string; phone: string | null; relation: string };
type Tab = "yeni" | "iceride" | "cikan";

const unitLabel = (v: Visit) => (v.units ? `${v.units.blocks?.name ?? ""}-${v.units.no}` : "");

// Danışma › Ziyaretçi: daireye dokun → sakini ara → ad (+ plaka) → kaydet · içeridekiler → "Çıkış yaptı" · bugün çıkanlar (geri al)
export default function DeskVisitors() {
  const w = useWords();
  const { colors } = useTheme();
  const insets = useSafeAreaInsets();
  const { active } = useAuth();
  const siteId = active.kind === "danisma" ? active.siteId : "";
  const siteName = active.kind === "danisma" ? active.siteName : "";
  const [tab, setTab] = useState<Tab>("yeni");
  const [inside, setInside] = useState<Visit[]>([]);
  const [left, setLeft] = useState<Visit[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const [unit, setUnit] = useState<GridUnit | null>(null);
  const [people, setPeople] = useState<Person[]>([]);
  const [name, setName] = useState("");
  const [plate, setPlate] = useState("");
  const [kind, setKind] = useState<"misafir" | "hizmet">("misafir");
  const [clientId, setClientId] = useState(uuid());
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    if (!siteId) return;
    const cols = "id, visitor_name, plate, kind, arrived_at, departed_at, units(no, blocks(name))";
    const day = new Date(Date.now() - 36 * 3600 * 1000).toISOString();
    const [i, l] = await Promise.all([
      supabase.from("visitors").select(cols).eq("site_id", siteId).is("departed_at", null).order("arrived_at", { ascending: false }),
      supabase.from("visitors").select(cols).eq("site_id", siteId).gte("departed_at", day).order("departed_at", { ascending: false }),
    ]);
    if (i.error) return setError(i.error.message.includes("fetch") ? NETWORK_ERROR : "Ziyaretçiler alınamadı.");
    setError(null);
    setInside((i.data ?? []) as unknown as Visit[]);
    setLeft(((l.data ?? []) as unknown as Visit[]).filter((v) => v.departed_at && isTodayTR(v.departed_at)));
  }, [siteId]);
  useAutoRefresh(load);

  const peopleFor = useRef<string | null>(null);
  async function openUnit(u: GridUnit) {
    setUnit(u);
    setName("");
    setPlate("");
    setKind("misafir");
    setClientId(uuid());
    setError(null);
    peopleFor.current = u.id;
    setPeople([]);
    const { data } = await supabase.from("unit_residents").select("relation, residents(full_name, phone)").eq("unit_id", u.id).is("ended_on", null);
    if (peopleFor.current !== u.id) return; // geç gelen cevap başka dairenin sakinlerini göstermesin
    // Kiracı önce (onay kiracıdan alınır)
    const list = ((data ?? []) as unknown as { relation: string; residents: { full_name: string; phone: string | null } | null }[])
      .filter((r) => r.residents)
      .map((r) => ({ full_name: r.residents!.full_name, phone: r.residents!.phone, relation: r.relation }))
      .sort((a, b) => (a.relation === "kiraci" ? -1 : 0) - (b.relation === "kiraci" ? -1 : 0));
    setPeople(list);
  }

  async function save() {
    if (!unit) return;
    if (name.trim().length < 2) return setError(kind === "hizmet" ? "Gelen kişiyi ya da firmayı yazın." : "Ziyaretçinin adını yazın.");
    setBusy(true);
    setError(null);
    const { error: e } = await supabase.rpc("record_visitor", { p_client_id: clientId, p_unit_id: unit.id, p_name: name.trim(), p_plate: plate.trim() || null, p_kind: kind });
    setBusy(false);
    if (e) return setError(e.message.includes("fetch") ? `${NETWORK_ERROR} Tekrar "Girişi kaydet"e basın.` : e.code === "23514" ? "Plaka 34ABC123 gibi olmalı." : "Kaydedilemedi.");
    setUnit(null);
    setTab("iceride");
    load();
  }

  async function act(rpc: string, id: string, fail: string) {
    const { error: e } = await supabase.rpc(rpc, { p_visitor_id: id });
    if (e) setError(e.message.includes("fetch") ? NETWORK_ERROR : fail);
    load();
  }

  function rowMenu(v: Visit) {
    if (!isTodayTR(v.arrived_at)) return;
    Alert.alert(v.visitor_name, "Yanlış girilmiş bir kayıt mı?", [
      { text: "Vazgeç", style: "cancel" },
      { text: "Yanlış Kayıt, Sil", style: "destructive", onPress: () => act("delete_visitor", v.id, "Silinemedi. Sadece bugün girilen kayıt silinebilir.") },
    ]);
  }

  return (
    <View style={{ flex: 1, backgroundColor: colors.zemin }}>
      <ScrollView
        contentContainerStyle={{ paddingTop: insets.top + 8, paddingHorizontal: SIZE.kenar, paddingBottom: 40, gap: 18 }}
        refreshControl={<RefreshControl refreshing={refreshing} tintColor={colors.vurgu} onRefresh={async () => { setRefreshing(true); await load(); setRefreshing(false); }} />}
      >
        <ScreenTitle title="Ziyaretçi" subtitle={siteName} />
        <Segmented
          value={tab}
          onChange={setTab}
          options={[
            { key: "yeni", label: "Yeni giriş" },
            { key: "iceride", label: `İçeride${inside.length ? ` (${inside.length})` : ""}` },
            { key: "cikan", label: "Bugün çıkan" },
          ]}
        />
        {error && !unit && <Notice tone="hata" text={error} />}

        {tab === "yeni" && (
          <>
            <Muted style={{ paddingHorizontal: 4 }}>{`Ziyaretçinin gideceği ${w.dat} dokunun.`}</Muted>
            <UnitGrid siteId={siteId} onPick={openUnit} />
          </>
        )}

        {tab === "iceride" &&
          (inside.length === 0 ? (
            <EmptyState icon={DoorOpen} title="İçeride ziyaretçi yok" text="Girişi kaydedilen ziyaretçiler, çıkış yapana kadar burada görünür." />
          ) : (
            <>
              <ListGroup>
                {inside.map((v) => (
                  <Pressable key={v.id} onLongPress={() => rowMenu(v)}>
                    <ListRow
                      title={`${v.visitor_name} → ${unitLabel(v)}`}
                      subtitle={`${v.kind === "hizmet" ? "Hizmet · " : ""}${isTodayTR(v.arrived_at) ? `Giriş ${formatTime(v.arrived_at)}` : `Giriş ${formatDateTime(v.arrived_at)}`}${v.plate ? ` · ${v.plate}` : ""}`}
                      right={
                        <Pressable accessibilityRole="button" onPress={() => act("mark_visitor_departed", v.id, "Çıkış kaydedilemedi.")} style={{ minHeight: 44, paddingHorizontal: 12, borderRadius: 12, justifyContent: "center", backgroundColor: colors.vurgu }}>
                          <Text style={{ fontFamily: FONT.kalin, fontSize: 14, color: colors.vurguYazi }}>Çıkış yaptı</Text>
                        </Pressable>
                      }
                    />
                  </Pressable>
                ))}
              </ListGroup>
              <Muted style={{ paddingHorizontal: 4 }}>Yanlış girilen kaydı silmek için satıra basılı tutun (sadece bugün girilenler).</Muted>
            </>
          ))}

        {tab === "cikan" &&
          (left.length === 0 ? (
            <EmptyState icon={UserCheck} title="Bugün çıkan yok" text="Çıkışı yazılan ziyaretçiler burada görünür; yanlışlıkla basıldıysa geri alabilirsiniz." />
          ) : (
            <ListGroup>
              {left.map((v) => (
                <ListRow
                  key={v.id}
                  title={`${v.visitor_name} · ${unitLabel(v)}`}
                  subtitle={`${v.kind === "hizmet" ? "Hizmet · " : ""}Giriş ${formatTime(v.arrived_at)} · Çıkış ${formatTime(v.departed_at!)}${v.plate ? ` · ${v.plate}` : ""}`}
                  right={
                    <Text accessibilityRole="button" onPress={() => act("undo_visitor_departure", v.id, "Geri alınamadı.")} style={{ fontFamily: FONT.orta, fontSize: 15, color: colors.vurgu, padding: 10 }}>
                      Geri al
                    </Text>
                  }
                />
              ))}
            </ListGroup>
          ))}
      </ScrollView>

      <Sheet visible={!!unit} onClose={() => setUnit(null)} title={unit?.label ?? ""} subtitle="Ziyaretçi girişi">
        {people.length > 0 ? (
          <>
            <SectionLabel>ÖNCE SAKİNDEN ONAY ALIN</SectionLabel>
            <ListGroup>
              {people.map((p) => (
                <ListRow
                  key={`${p.full_name}-${p.phone}`}
                  title={p.full_name}
                  subtitle={`${p.relation === "kiraci" ? "Kiracı" : "Malik"}${p.phone ? ` · ${formatPhone(p.phone)}` : " · Telefon yok"}`}
                  right={p.phone ? <Phone size={22} color={colors.vurgu} /> : undefined}
                  onPress={p.phone ? () => Linking.openURL(`tel:+${p.phone}`) : undefined}
                  chevron={false}
                />
              ))}
            </ListGroup>
          </>
        ) : (
          <Notice tone="bekliyor" text={`Bu ${w.loc} kayıtlı sakin yok.`} />
        )}
        <Segmented
          value={kind}
          onChange={setKind}
          options={[
            { key: "misafir", label: "Misafir" },
            { key: "hizmet", label: "Hizmet / tamir" },
          ]}
        />
        <Muted>{kind === "hizmet" ? "Tamirci, servis, teknisyen, temizlik gibi iş için gelenler. Yönetim bu girişleri görür." : "Sakinin misafiri. Sadece danışma ve sakin görür."}</Muted>
        <Field
          label={kind === "hizmet" ? "Kişi ya da firma" : "Ziyaretçinin adı"}
          value={name}
          onChangeText={setName}
          autoCapitalize="words"
          maxLength={100}
          placeholder={kind === "hizmet" ? "Ör. Klima servisi, Ahmet Usta" : undefined}
        />
        <Field label="Plaka (isteğe bağlı)" value={plate} onChangeText={(t) => setPlate(t.toUpperCase().replace(/İ/g, "I"))} autoCapitalize="characters" maxLength={14} placeholder="34 ABC 123" />
        {error && <Notice tone="hata" text={error} />}
        <Button label="Girişi Kaydet" icon={LogIn} onPress={save} loading={busy} />
        <Muted>Giriş saati kendiliğinden yazılır.</Muted>
      </Sheet>
    </View>
  );
}
