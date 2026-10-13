import { useCallback, useState } from "react";
import { RefreshControl, ScrollView, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { DoorOpen, Package } from "lucide-react-native";
import { NETWORK_ERROR, supabase } from "@/lib/supabase";
import { useAutoRefresh } from "@/lib/use-auto-refresh";
import { formatTime, isTodayTR } from "@/lib/uuid";
import { formatDateTime } from "@/lib/tickets";
import { EmptyState, ListGroup, ListRow, Notice, Pill, ScreenTitle, SectionLabel, Segmented } from "@/components/ui";
import { SIZE, useTheme } from "@/theme";
import { useWords } from "@/lib/words";

type Unit = { no: string; blocks: { name: string } | null } | null;
type Pkg = { id: string; note: string | null; received_at: string; delivered_at: string | null; delivered_to: string | null; units: Unit };
type Visit = { id: string; visitor_name: string; plate: string | null; kind?: string; arrived_at: string; departed_at: string | null; units: Unit };

const label = (u: Unit) => (u ? `${u.blocks?.name ?? ""}-${u.no}` : "");
const when = (iso: string) => (isTodayTR(iso) ? `Bugün ${formatTime(iso)}` : formatDateTime(iso));

// Kargo ve ziyaretçi kayıtları (sadece görüntüleme).
// Sakin: kendi dairelerinin kargoları ve son 30 günün ziyaretçileri · Yönetici: sadece HİZMET girişleri (tamir, servis; içeridekiler ve son 7 gün);
// kargoyu ve sakinlerin misafirlerini görmez (veritabanı da vermez).
export function DeskLog({ title, subtitle, siteId, unitIds }: { title: string; subtitle?: string; siteId?: string; unitIds?: string[] }) {
  const w = useWords();
  const { colors } = useTheme();
  const insets = useSafeAreaInsets();
  const resident = !siteId;
  const [tab, setTab] = useState<"kargo" | "ziyaretci">(siteId ? "ziyaretci" : "kargo");
  const [pkgs, setPkgs] = useState<Pkg[]>([]);
  const [visits, setVisits] = useState<Visit[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const unitKey = (unitIds ?? []).join(",");

  const load = useCallback(async () => {
    if (!siteId && !unitKey) return;
    const days = (n: number) => new Date(Date.now() - n * 86400 * 1000).toISOString();
    let p = supabase.from("packages").select("id, note, received_at, delivered_at, delivered_to, units(no, blocks(name))").or(`received_at.gte.${days(30)},delivered_at.is.null`); // bekleyen kargo ne kadar eski olursa olsun görünür
    let v = supabase.from("visitors").select("id, visitor_name, plate, kind, arrived_at, departed_at, units(no, blocks(name))").or(`arrived_at.gte.${days(resident ? 30 : 7)},departed_at.is.null`); // içeride olan her zaman görünür
    if (siteId) {
      p = p.eq("site_id", siteId);
      v = v.eq("site_id", siteId);
    } else {
      p = p.in("unit_id", unitKey.split(","));
      v = v.in("unit_id", unitKey.split(","));
    }
    // Yönetici kargoyu görmez (veritabanı da vermez); sadece sakin için sorulur
    const [pr, vr] = await Promise.all([resident ? p.order("received_at", { ascending: false }).limit(200) : Promise.resolve({ data: [], error: null }), v.order("arrived_at", { ascending: false }).limit(200)]);
    if (pr.error || vr.error) return setError((pr.error ?? vr.error)!.message.includes("fetch") ? NETWORK_ERROR : "Bilgiler alınamadı.");
    setError(null);
    setPkgs((pr.data ?? []) as unknown as Pkg[]);
    setVisits((vr.data ?? []) as unknown as Visit[]);
  }, [siteId, unitKey, resident]);
  useAutoRefresh(load);

  const waiting = pkgs.filter((p) => !p.delivered_at);
  const given = pkgs.filter((p) => p.delivered_at);
  const inside = visits.filter((x) => !x.departed_at);
  const gone = visits.filter((x) => x.departed_at);

  return (
    <ScrollView
      style={{ flex: 1, backgroundColor: colors.zemin }}
      contentContainerStyle={{ paddingTop: insets.top + 8, paddingHorizontal: SIZE.kenar, paddingBottom: 40, gap: 18 }}
      refreshControl={<RefreshControl refreshing={refreshing} tintColor={colors.vurgu} onRefresh={async () => { setRefreshing(true); await load(); setRefreshing(false); }} />}
    >
      <ScreenTitle title={title} subtitle={subtitle} />
      {resident && (
        <Segmented
          value={tab}
          onChange={setTab}
          options={[
            { key: "kargo", label: `Kargolarım${waiting.length ? ` (${waiting.length})` : ""}` },
            { key: "ziyaretci", label: "Ziyaretçilerim" },
          ]}
        />
      )}
      {error && <Notice tone="hata" text={error} />}

      {tab === "kargo" &&
        (pkgs.length === 0 ? (
          <EmptyState icon={Package} title="Bekleyen kargonuz yok" text="Danışmaya kargonuz gelince telefonunuza bildirim gelir ve burada görünür; danışmadan teslim alabilirsiniz." />
        ) : (
          <>
            {waiting.length > 0 && (
              <>
                <SectionLabel>DANIŞMADA BEKLEYEN</SectionLabel>
                <ListGroup>
                  {waiting.map((p) => (
                    <ListRow key={p.id} title={`Kargo · ${label(p.units)}`} subtitle={`${when(p.received_at)}${p.note ? ` · ${p.note}` : ""}`} right={<Pill label="Bekliyor" tone="bekliyor" />} />
                  ))}
                </ListGroup>
              </>
            )}
            {given.length > 0 && (
              <>
                <SectionLabel>TESLİM EDİLENLER (SON 30 GÜN)</SectionLabel>
                <ListGroup>
                  {given.map((p) => (
                    <ListRow key={p.id} title={`Kargo · ${label(p.units)}`} subtitle={`${when(p.delivered_at!)} teslim edildi${p.delivered_to ? ` · ${p.delivered_to}` : ""}`} right={<Pill label="Teslim" tone="basari" />} />
                  ))}
                </ListGroup>
              </>
            )}
          </>
        ))}

      {tab === "ziyaretci" &&
        (visits.length === 0 ? (
          <EmptyState icon={DoorOpen} title={resident ? "Ziyaretçi kaydı yok" : "Hizmet girişi yok"} text={resident ? `Danışmanın ${w.yourDat} kaydettiği ziyaretçiler (son 30 gün) burada görünür.` : "Son 7 günde tamir, servis ya da teknisyen girişi yok. Sakinlerin misafirleri burada görünmez."} />
        ) : (
          <>
            {inside.length > 0 && (
              <>
                <SectionLabel>İÇERİDE</SectionLabel>
                <ListGroup>
                  {inside.map((x) => (
                    <ListRow key={x.id} title={resident ? x.visitor_name : `${x.visitor_name} → ${label(x.units)}`} subtitle={`${x.kind === "hizmet" ? "Hizmet · " : ""}Giriş ${when(x.arrived_at)}${x.plate ? ` · ${x.plate}` : ""}`} right={<Pill label="İçeride" tone="bilgi" />} />
                  ))}
                </ListGroup>
              </>
            )}
            {gone.length > 0 && (
              <>
                <SectionLabel>{resident ? "SON 30 GÜN" : "SON 7 GÜN"}</SectionLabel>
                <ListGroup>
                  {gone.map((x) => (
                    <ListRow key={x.id} title={resident ? x.visitor_name : `${x.visitor_name} → ${label(x.units)}`} subtitle={`${x.kind === "hizmet" ? "Hizmet · " : ""}${when(x.arrived_at)} – ${formatTime(x.departed_at!)}${x.plate ? ` · ${x.plate}` : ""}`} />
                  ))}
                </ListGroup>
              </>
            )}
          </>
        ))}
      <View />
    </ScrollView>
  );
}
