import { router } from "expo-router";
import { useCallback, useEffect, useState } from "react";
import { RefreshControl, ScrollView, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { ClipboardList, Plus } from "lucide-react-native";
import { useAuth } from "@/auth";
import { useOutbox } from "@/outbox";
import { OutboxList } from "@/components/outbox-list";
import { NETWORK_ERROR, supabase } from "@/lib/supabase";
import { useAutoRefresh } from "@/lib/use-auto-refresh";
import { formatDateTime, KIND_LABEL, STATUS_LABEL, statusTone, TICKET_COLUMNS, type Ticket } from "@/lib/tickets";
import { Button, EmptyState, ListGroup, ListRow, Notice, Pill, ScreenTitle, SectionLabel } from "@/components/ui";
import { SIZE, useTheme } from "@/theme";
import { useWords } from "@/lib/words";

// Sakin: kendi dairesinin kayıtları (devam eden / tamamlanan) + gönderilmeyi bekleyenler; altta büyük "Yeni kayıt" düğmesi
export default function RecordsScreen() {
  const w = useWords();
  const { colors } = useTheme();
  const insets = useSafeAreaInsets();
  const { context } = useAuth();
  const { drafts, online, retry, lastSent } = useOutbox();
  const [tickets, setTickets] = useState<Ticket[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const units = context?.units ?? [];
  const unitKey = units.map((u) => u.unit_id).join(",");
  const subtitle = units.length === 1 ? `${units[0].label} · ${units[0].site_name}` : units.length ? `${units.length} ${w.nom}` : undefined;

  const load = useCallback(async () => {
    if (!unitKey) return;
    const { data, error: e } = await supabase.from("tickets").select(TICKET_COLUMNS).in("unit_id", unitKey.split(",")).order("created_at", { ascending: false }).limit(50);
    if (e) setError(e.message.includes("fetch") ? NETWORK_ERROR : "Kayıtlar alınamadı.");
    else {
      setError(null);
      setTickets((data ?? []) as Ticket[]);
    }
  }, [unitKey]);
  useAutoRefresh(load);
  useEffect(() => {
    if (lastSent) load();
  }, [lastSent, load]);

  const open = tickets.filter((t) => t.status !== "tamamlandi");
  const done = tickets.filter((t) => t.status === "tamamlandi");
  const row = (t: Ticket) => (
    <ListRow
      key={t.id}
      title={t.title}
      subtitle={`${KIND_LABEL[t.kind]}${t.urgent ? " · Acil" : ""} · ${formatDateTime(t.created_at)}`}
      right={<Pill label={STATUS_LABEL[t.status]} tone={statusTone(t)} />}
      onPress={() => router.push({ pathname: "/kayit/[id]", params: { id: t.id } })}
      chevron={false}
    />
  );

  return (
    <View style={{ flex: 1, backgroundColor: colors.zemin }}>
      <ScrollView
        contentContainerStyle={{ paddingTop: insets.top + 8, paddingHorizontal: SIZE.kenar, paddingBottom: 110, gap: 20 }}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            tintColor={colors.vurgu}
            onRefresh={async () => {
              setRefreshing(true);
              retry();
              await load();
              setRefreshing(false);
            }}
          />
        }
      >
        <ScreenTitle title="Kayıtlarım" subtitle={subtitle} />

        {!online && <Notice tone="bekliyor" text="İnternet yok. Yeni kayıtlarınız telefonda bekler, bağlantı gelince kendiliğinden gönderilir." />}
        {error && <Notice tone="hata" text={error} />}

        <OutboxList />

        {tickets.length === 0 && drafts.length === 0 && !error ? (
          <EmptyState icon={ClipboardList} title="Henüz kayıt yok" text="Arıza, talep ya da şikâyetinizi aşağıdaki düğmeyle yönetime iletin." />
        ) : (
          <>
            {open.length > 0 && (
              <>
                <SectionLabel>DEVAM EDENLER</SectionLabel>
                <ListGroup>{open.map(row)}</ListGroup>
              </>
            )}
            {done.length > 0 && (
              <>
                <SectionLabel>TAMAMLANANLAR</SectionLabel>
                <ListGroup>{done.map(row)}</ListGroup>
              </>
            )}
          </>
        )}
      </ScrollView>

      <View style={{ position: "absolute", left: SIZE.kenar, right: SIZE.kenar, bottom: 16 }}>
        <Button label="Yeni Kayıt" icon={Plus} onPress={() => router.push("/kayit/yeni")} />
      </View>
    </View>
  );
}
