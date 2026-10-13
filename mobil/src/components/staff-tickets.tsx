import { router } from "expo-router";
import { useCallback, useEffect, useMemo, useState } from "react";
import { Modal, Pressable, RefreshControl, ScrollView, Text, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { ChevronDown, ClipboardList, Plus, Siren } from "lucide-react-native";
import { monthStartTR } from "@/lib/format";
import { NETWORK_ERROR, supabase } from "@/lib/supabase";
import { useAutoRefresh } from "@/lib/use-auto-refresh";
import { useOutbox } from "@/outbox";
import { OutboxList } from "@/components/outbox-list";
import { KIND_LABEL, STATUS_LABEL, statusTone, TICKET_COLUMNS, type Ticket, type TicketKind } from "@/lib/tickets";
import { Button, Card, EmptyState, ListGroup, ListRow, Muted, Notice, Pill, ScreenTitle, Segmented } from "@/components/ui";
import { FONT, SIZE, useTheme } from "@/theme";

type Row = Ticket & { units: { no: string; blocks: { id: string; name: string } | null } | null };
type StatusFilter = "acik" | "biten" | "tumu";

const STATUS_FILTERS: { key: StatusFilter; label: string }[] = [
  { key: "acik", label: "Açık" },
  { key: "biten", label: "Biten" },
  { key: "tumu", label: "Tümü" },
];

// Eşit genişlikte küçük filtre düğmesi (Acil · Tür · Blok)
function FilterButton({ label, active, onPress, tone, icon }: { label: string; active: boolean; onPress: () => void; tone?: "acil"; icon?: "acilir" | "acil" }) {
  const { colors } = useTheme();
  const accent = tone === "acil" ? colors.hata : colors.vurgu;
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityState={{ selected: active }}
      onPress={onPress}
      style={{ flex: 1, minHeight: 44, borderRadius: 12, borderWidth: 1.5, flexDirection: "row", alignItems: "center", justifyContent: "center", gap: 4, paddingHorizontal: 6, borderColor: active ? accent : "transparent", backgroundColor: active ? (tone === "acil" ? colors.hataZemin : colors.vurguAcik) : colors.kutu }}
    >
      {icon === "acil" && <Siren size={16} color={active ? accent : colors.yaziSoluk} />}
      <Text numberOfLines={1} style={{ flexShrink: 1, fontFamily: active ? FONT.kalin : FONT.orta, fontSize: 14, color: active ? accent : colors.yazi }}>{label}</Text>
      {icon === "acilir" && <ChevronDown size={16} color={active ? accent : colors.yaziSoluk} />}
    </Pressable>
  );
}

// Alttan açılan seçim listesi (tür / blok)
function PickerSheet({ title, options, value, onPick, onClose }: { title: string; options: { key: string | null; label: string }[]; value: string | null; onPick: (k: string | null) => void; onClose: () => void }) {
  const { colors } = useTheme();
  return (
    <Modal transparent animationType="fade" onRequestClose={onClose}>
      <Pressable accessibilityLabel="Kapat" onPress={onClose} style={{ flex: 1, backgroundColor: "rgba(20,15,10,0.45)", justifyContent: "flex-end" }}>
        <Pressable style={{ backgroundColor: colors.zemin, borderTopLeftRadius: 20, borderTopRightRadius: 20, padding: SIZE.kenar, paddingBottom: 36, gap: 8 }}>
          <Text style={{ fontFamily: FONT.kalin, fontSize: 17, color: colors.yazi, marginBottom: 4 }}>{title}</Text>
          {options.map((o) => {
            const on = o.key === value;
            return (
              <Pressable
                key={o.key ?? "hepsi"}
                accessibilityRole="radio"
                accessibilityState={{ selected: on }}
                onPress={() => {
                  onPick(o.key);
                  onClose();
                }}
                style={{ minHeight: 54, borderRadius: 14, paddingHorizontal: 16, justifyContent: "center", backgroundColor: on ? colors.vurguAcik : colors.kutu, borderWidth: 1.5, borderColor: on ? colors.vurgu : "transparent" }}
              >
                <Text style={{ fontFamily: on ? FONT.kalin : FONT.orta, fontSize: 16, color: colors.yazi }}>{o.label}</Text>
              </Pressable>
            );
          })}
        </Pressable>
      </Pressable>
    </Modal>
  );
}

function durationText(ms: number) {
  const h = ms / 3_600_000;
  if (h < 1) return `${Math.max(1, Math.round(ms / 60000))} dk`;
  if (h < 48) return `${Math.round(h)} saat`;
  return `${Math.round(h / 24)} gün`;
}

// Yönetici ve danışma: sitenin kayıtları. Açıklar: acil üstte, sonra en eski bekleyen. Üstte bu ayın özeti (sadece yönetici).
export function StaffTickets({ siteId, siteName, showSummary, title = "Kayıtlar", header }: { siteId: string; siteName: string; showSummary: boolean; title?: string; header?: React.ReactNode }) {
  const { colors } = useTheme();
  const insets = useSafeAreaInsets();
  const [rows, setRows] = useState<Row[]>([]);
  const [monthClosed, setMonthClosed] = useState<{ opened: number; closed: number; avgMs: number | null }>({ opened: 0, closed: 0, avgMs: null });
  const [error, setError] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const [status, setStatus] = useState<StatusFilter>("acik");
  const [kind, setKind] = useState<TicketKind | null>(null);
  const [block, setBlock] = useState<string | null>(null);
  const [urgentOnly, setUrgentOnly] = useState(false);
  const [sheet, setSheet] = useState<"tur" | "blok" | null>(null);
  const { lastSent } = useOutbox();

  const load = useCallback(async () => {
    let q = supabase.from("tickets").select(`${TICKET_COLUMNS}, units(no, blocks(id, name))`).eq("site_id", siteId);
    if (status === "acik") q = q.neq("status", "tamamlandi");
    if (status === "biten") q = q.eq("status", "tamamlandi");
    q = status === "acik" ? q.order("urgent", { ascending: false }).order("created_at", { ascending: true }) : q.order("created_at", { ascending: false });
    const { data, error: e } = await q.limit(200);
    if (e) return setError(e.message.includes("fetch") ? NETWORK_ERROR : "Kayıtlar alınamadı.");
    setError(null);
    setRows((data ?? []) as unknown as Row[]);
    if (showSummary) {
      // Bu ay (Türkiye saatiyle ayın 1'inden itibaren): açılan, kapanan ve ortalama çözüm süresi
      const iso = monthStartTR();
      const [opened, closed] = await Promise.all([
        supabase.from("tickets").select("id", { count: "exact", head: true }).eq("site_id", siteId).gte("created_at", iso),
        supabase.from("tickets").select("created_at, closed_at").eq("site_id", siteId).eq("status", "tamamlandi").gte("closed_at", iso).limit(1000),
      ]);
      const done = (closed.data ?? []) as { created_at: string; closed_at: string }[];
      const avg = done.length ? done.reduce((s, t) => s + (new Date(t.closed_at).getTime() - new Date(t.created_at).getTime()), 0) / done.length : null;
      setMonthClosed({ opened: opened.count ?? 0, closed: done.length, avgMs: avg });
    }
  }, [siteId, status, showSummary]);

  useAutoRefresh(load);
  useEffect(() => {
    if (lastSent) load();
  }, [lastSent, load]);

  const blocks = useMemo(() => {
    const m = new Map<string, string>();
    for (const r of rows) if (r.units?.blocks) m.set(r.units.blocks.id, r.units.blocks.name);
    return [...m.entries()].sort((a, b) => a[1].localeCompare(b[1], "tr"));
  }, [rows]);
  const shown = rows.filter((r) => (!kind || r.kind === kind) && (!block || r.units?.blocks?.id === block) && (!urgentOnly || r.urgent));

  return (
    <View style={{ flex: 1, backgroundColor: colors.zemin }}>
    <ScrollView
      style={{ flex: 1 }}
      contentContainerStyle={{ paddingTop: insets.top + 8, paddingHorizontal: SIZE.kenar, paddingBottom: 100, gap: 14 }}
      refreshControl={
        <RefreshControl
          refreshing={refreshing}
          tintColor={colors.vurgu}
          onRefresh={async () => {
            setRefreshing(true);
            await load();
            setRefreshing(false);
          }}
        />
      }
    >
      {header}
      <ScreenTitle title={title} subtitle={siteName} />

      {showSummary && (
        <Card>
          <Muted style={{ fontFamily: FONT.kalin, fontSize: 14 }}>BU AY</Muted>
          <View style={{ flexDirection: "row", gap: 8, marginTop: -6 }}>
            {[
              { label: "Açılan", value: String(monthClosed.opened) },
              { label: "Kapanan", value: String(monthClosed.closed) },
              { label: "Ort. çözüm", value: monthClosed.avgMs === null ? "—" : durationText(monthClosed.avgMs) },
            ].map((x) => (
              <View key={x.label} style={{ flex: 1, gap: 2 }}>
                <Text style={{ fontFamily: FONT.cokKalin, fontSize: 26, letterSpacing: -0.5, color: colors.yazi }}>{x.value}</Text>
                <Muted>{x.label}</Muted>
              </View>
            ))}
          </View>
        </Card>
      )}

      <Segmented value={status} onChange={setStatus} options={STATUS_FILTERS} />
      <View style={{ flexDirection: "row", gap: 8 }}>
        <FilterButton label="Acil" icon="acil" tone="acil" active={urgentOnly} onPress={() => setUrgentOnly(!urgentOnly)} />
        <FilterButton label={kind ? KIND_LABEL[kind] : "Tür"} icon="acilir" active={!!kind} onPress={() => setSheet("tur")} />
        {blocks.length > 1 && <FilterButton label={block ? `${blocks.find(([id]) => id === block)?.[1] ?? ""} Blok` : "Blok"} icon="acilir" active={!!block} onPress={() => setSheet("blok")} />}
      </View>
      {sheet === "tur" && (
        <PickerSheet
          title="Tür"
          value={kind}
          options={[{ key: null, label: "Bütün Türler" }, ...(Object.keys(KIND_LABEL) as TicketKind[]).map((k) => ({ key: k, label: KIND_LABEL[k] }))]}
          onPick={(k) => setKind(k as TicketKind | null)}
          onClose={() => setSheet(null)}
        />
      )}
      {sheet === "blok" && (
        <PickerSheet title="Blok" value={block} options={[{ key: null, label: "Bütün Bloklar" }, ...blocks.map(([id, name]) => ({ key: id, label: `${name} Blok` }))]} onPick={setBlock} onClose={() => setSheet(null)} />
      )}

      {error && <Notice tone="hata" text={error} />}
      <OutboxList />
      {shown.length === 0 && !error ? (
        <EmptyState icon={ClipboardList} title={status === "acik" && !kind && !block && !urgentOnly ? "Açık kayıt yok" : "Bu filtrede kayıt yok"} text="Sakinlerin arıza, talep ve şikâyetleri burada listelenir." />
      ) : (
        <ListGroup>
          {shown.map((t) => {
            const unit = t.units ? `${t.units.blocks?.name ?? ""}-${t.units.no}` : "";
            const waitMs = Date.now() - new Date(t.created_at).getTime();
            const urgentOpen = t.urgent && t.status !== "tamamlandi";
            return (
              <ListRow
                key={t.id}
                left={<View style={{ width: 4, alignSelf: "stretch", borderRadius: 2, backgroundColor: urgentOpen ? colors.hata : "transparent", marginLeft: -10 }} />}
                title={t.title}
                subtitle={[
                  urgentOpen ? "Acil" : null,
                  `${KIND_LABEL[t.kind]} · ${unit}${t.location === "ortak" ? " · Ortak alan" : ""}`,
                  t.status !== "tamamlandi" ? `${durationText(waitMs)} önce` : null,
                  t.resolution === "devam" && t.status !== "tamamlandi" ? "Sorun devam ediyor" : null,
                ]
                  .filter(Boolean)
                  .join(" · ")}
                right={<Pill label={STATUS_LABEL[t.status]} tone={statusTone(t)} />}
                onPress={() => router.push({ pathname: "/kayit/[id]", params: { id: t.id } })}
                chevron={false}
              />
            );
          })}
        </ListGroup>
      )}
    </ScrollView>
      {/* Yönetim ve danışma da kayıt açar (sakin adına ya da ortak alan için) */}
      <View style={{ position: "absolute", left: SIZE.kenar, right: SIZE.kenar, bottom: 16 }}>
        <Button label="Yeni Kayıt" icon={Plus} onPress={() => router.push("/kayit/yeni")} />
      </View>
    </View>
  );
}
