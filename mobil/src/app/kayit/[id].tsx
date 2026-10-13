import { Redirect, useLocalSearchParams } from "expo-router";
import { useCallback, useEffect, useState } from "react";
import { ActivityIndicator, Image, KeyboardAvoidingView, Platform, Pressable, RefreshControl, ScrollView, Text, View } from "react-native";
import { useVideoPlayer, VideoView } from "expo-video";
import { Check, CircleAlert, CircleCheck, Send } from "lucide-react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { useAuth } from "@/auth";
import { NETWORK_ERROR, supabase } from "@/lib/supabase";
import {
  formatDateTime,
  KIND_LABEL,
  ROLE_LABEL,
  STATUS_LABEL,
  STATUS_ORDER,
  statusTone,
  TICKET_COLUMNS,
  type Ticket,
  type TicketEvent,
  type TicketMedia,
} from "@/lib/tickets";
import { ContactButtons } from "@/components/people-manager";
import { Avatar } from "@/components/avatar";
import { BackHeader, Body, Button, Card, Field, ListGroup, ListRow, Muted, Notice, Pill, ScreenTitle, SectionLabel } from "@/components/ui";
import { FONT, SIZE, useTheme } from "@/theme";
import { useWords } from "@/lib/words";

type Signed = TicketMedia & { url: string | null };
type Person = { id: string; relation: string; residents: { full_name: string; phone: string | null; user_id: string | null } | null };
const RELATION_LABEL: Record<string, string> = { malik: "Malik", kiraci: "Kiracı" };

function VideoBox({ url }: { url: string }) {
  const player = useVideoPlayer(url);
  return <VideoView player={player} style={{ width: "100%", aspectRatio: 9 / 16, maxHeight: 440, borderRadius: 18 }} nativeControls contentFit="contain" />;
}

// Durum adımları: noktalar + çizgi, geçilen adımlar vurgu renginde
function Steps({ status }: { status: Ticket["status"] }) {
  const { colors } = useTheme();
  const index = STATUS_ORDER.indexOf(status);
  return (
    <View accessibilityLabel={`Durum: ${STATUS_LABEL[status]}`} style={{ flexDirection: "row", alignItems: "flex-start" }}>
      {STATUS_ORDER.map((s, i) => {
        const done = i <= index;
        return (
          <View key={s} style={{ flex: 1, alignItems: "center", gap: 8 }}>
            <View style={{ flexDirection: "row", alignItems: "center", alignSelf: "stretch" }}>
              <View style={{ flex: 1, height: 2, backgroundColor: i === 0 ? "transparent" : done ? colors.vurgu : colors.cizgi }} />
              <View style={{ width: 24, height: 24, borderRadius: 12, alignItems: "center", justifyContent: "center", backgroundColor: done ? colors.vurgu : colors.kutuKoyu }}>
                {done && <Check size={14} color={colors.vurguYazi} strokeWidth={3} />}
              </View>
              <View style={{ flex: 1, height: 2, backgroundColor: i === STATUS_ORDER.length - 1 ? "transparent" : i < index ? colors.vurgu : colors.cizgi }} />
            </View>
            <Text numberOfLines={1} adjustsFontSizeToFit style={{ fontFamily: i === index ? FONT.kalin : FONT.normal, fontSize: 13, color: done ? colors.yazi : colors.yaziSoluk }}>
              {STATUS_LABEL[s]}
            </Text>
          </View>
        );
      })}
    </View>
  );
}

// Kayıt detayı: durum, fotoğraf/video, sakinler (yönetim için), geçmiş, not/cevap; sakin için "çözüldü / devam ediyor"
export default function TicketScreen() {
  const w = useWords();
  const { id } = useLocalSearchParams<{ id: string }>();
  const { colors } = useTheme();
  const insets = useSafeAreaInsets();
  const { session, active, context } = useAuth();
  const [ticket, setTicket] = useState<Ticket | null>(null);
  const [events, setEvents] = useState<TicketEvent[]>([]);
  const [media, setMedia] = useState<Signed[]>([]);
  const [unitText, setUnitText] = useState<string | null>(null);
  const [people, setPeople] = useState<Person[]>([]);
  const [avatars, setAvatars] = useState<Record<string, string | null>>({});
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    setError(null);
    const [t, e, m] = await Promise.all([
      supabase.from("tickets").select(TICKET_COLUMNS).eq("id", id).maybeSingle(),
      supabase.from("ticket_events").select("id, kind, body, status, author_name, author_role, created_at").eq("ticket_id", id).order("created_at"),
      supabase.from("ticket_media").select("id, kind, path, deleted_at").eq("ticket_id", id).order("created_at"),
    ]);
    setLoading(false);
    if (t.error) return setError(t.error.message.includes("fetch") ? NETWORK_ERROR : "Kayıt açılamadı.");
    const tk = t.data as Ticket | null;
    setTicket(tk);
    setEvents((e.data ?? []) as TicketEvent[]);
    // Dosyalar herkese kapalı depoda: 10 dakikalık süreli bağlantıyla gösterilir
    const rows = (m.data ?? []) as TicketMedia[];
    const live = rows.filter((r) => !r.deleted_at);
    const { data: urls } = live.length ? await supabase.storage.from("kayitlar").createSignedUrls(live.map((r) => r.path), 600) : { data: [] };
    setMedia(rows.map((r) => ({ ...r, url: urls?.find((u) => u.path === r.path)?.signedUrl ?? null })));
    if (tk) {
      const [u, p] = await Promise.all([
        supabase.from("units").select("no, blocks(name)").eq("id", tk.unit_id).maybeSingle(),
        supabase.from("unit_residents").select("id, relation, residents(full_name, phone, user_id)").eq("unit_id", tk.unit_id).is("ended_on", null),
      ]);
      const unit = u.data as unknown as { no: string; blocks: { name: string } | null } | null;
      setUnitText(unit ? `${unit.blocks?.name ?? ""}-${unit.no}` : null);
      const list = (p.data ?? []) as unknown as Person[];
      setPeople(list);
      const ids = list.map((x) => x.residents?.user_id).filter(Boolean) as string[];
      if (ids.length) {
        const { data: prof } = await supabase.from("profiles").select("user_id, avatar_path").in("user_id", ids);
        setAvatars(Object.fromEntries((prof ?? []).map((x) => [x.user_id as string, x.avatar_path as string | null])));
      }
    }
  }, [id]);

  useEffect(() => {
    load();
  }, [load]);
  if (!session) return <Redirect href="/" />;

  const isResident = active.kind === "sakin";
  const isStaff = active.kind === "yonetici" || active.kind === "danisma"; // ikisi de durumu değiştirir
  const unitLabel = context?.units.find((u) => u.unit_id === ticket?.unit_id)?.label ?? unitText;

  async function run(fn: () => PromiseLike<{ error: { message: string } | null }>) {
    setBusy(true);
    setError(null);
    const { error: e } = await fn();
    setBusy(false);
    if (e) return setError(e.message.includes("fetch") ? NETWORK_ERROR : "İşlem yapılamadı. Lütfen tekrar deneyin.");
    setNote("");
    load();
  }

  return (
    <KeyboardAvoidingView style={{ flex: 1, backgroundColor: colors.zemin }} behavior={Platform.OS === "ios" ? "padding" : undefined}>
      <ScrollView
        contentContainerStyle={{ paddingTop: insets.top + 8, paddingHorizontal: SIZE.kenar, paddingBottom: 48, gap: 20 }}
        refreshControl={<RefreshControl refreshing={false} onRefresh={load} tintColor={colors.vurgu} />}
        keyboardShouldPersistTaps="handled"
      >
        <BackHeader />
        {loading ? (
          <ActivityIndicator color={colors.vurgu} style={{ marginTop: 40 }} />
        ) : !ticket ? (
          <Notice tone="hata" text={error ?? "Kayıt bulunamadı ya da görme yetkiniz yok."} />
        ) : (
          <>
            <View style={{ gap: 12 }}>
              <ScreenTitle
                title={ticket.title}
                subtitle={`${KIND_LABEL[ticket.kind]} · ${unitLabel ?? ""}${ticket.location === "ortak" ? " · Ortak alan" : ""}`}
              />
              <View style={{ flexDirection: "row", gap: 8, flexWrap: "wrap" }}>
                <Pill label={STATUS_LABEL[ticket.status]} tone={statusTone(ticket)} />
                {ticket.urgent && <Pill label="Acil" tone="hata" />}
              </View>
              {ticket.description ? <Body>{ticket.description}</Body> : null}
              <Muted>{formatDateTime(ticket.created_at)}</Muted>
            </View>

            <Card>
              <Steps status={ticket.status} />
              {ticket.resolution === "cozuldu" && <Muted style={{ textAlign: "center" }}>Sakin sorunun çözüldüğünü onayladı.</Muted>}
              {ticket.resolution === "devam" && ticket.status !== "tamamlandi" && <Muted style={{ textAlign: "center", color: colors.bekliyor }}>Sakin sorunun devam ettiğini bildirdi.</Muted>}
            </Card>

            {/* Tamamlanan kayıt: sakin onaylar ya da sorun devam ediyor der */}
            {isResident && ticket.status === "tamamlandi" && ticket.resolution !== "cozuldu" && (
              <Card>
                <Body style={{ fontFamily: FONT.kalin }}>Sorununuz çözüldü mü?</Body>
                <Button label="Evet, Çözüldü" icon={CircleCheck} loading={busy} onPress={() => run(() => supabase.rpc("resolve_ticket", { p_ticket_id: ticket.id, p_solved: true, p_body: note || null }))} />
                <Button label="Hayır, Sorun Devam Ediyor" variant="tehlike" icon={CircleAlert} loading={busy} onPress={() => run(() => supabase.rpc("resolve_ticket", { p_ticket_id: ticket.id, p_solved: false, p_body: note || null }))} />
              </Card>
            )}

            {media.length > 0 && (
              <>
                <SectionLabel>FOTOĞRAF / VİDEO</SectionLabel>
                {media.map((m) =>
                  m.deleted_at || !m.url ? (
                    <Muted key={m.id}>{m.kind === "video" ? "Video saklama süresi dolduğu için silindi." : "Dosya açılamadı."}</Muted>
                  ) : m.kind === "foto" ? (
                    <Image key={m.id} source={{ uri: m.url }} style={{ width: "100%", aspectRatio: 4 / 3, borderRadius: 18, backgroundColor: colors.kutuKoyu }} resizeMode="cover" accessibilityLabel="Kayıt fotoğrafı" />
                  ) : (
                    <VideoBox key={m.id} url={m.url} />
                  )
                )}
              </>
            )}

            {!isResident && people.length > 0 && (
              <>
                <SectionLabel>{`${unitLabel ?? w.nom.toLocaleUpperCase("tr-TR")} SAKİNLERİ`}</SectionLabel>
                <ListGroup>
                  {people.map((p) => (
                    <ListRow
                      key={p.id}
                      left={<Avatar path={p.residents?.user_id ? avatars[p.residents.user_id] : null} name={p.residents?.full_name} size={40} />}
                      title={p.residents?.full_name ?? ""}
                      subtitle={RELATION_LABEL[p.relation] ?? p.relation}
                      right={<ContactButtons phone={p.residents?.phone ?? null} />}
                    />
                  ))}
                </ListGroup>
              </>
            )}

            {isStaff && (
              <>
                <SectionLabel>DURUMU DEĞİŞTİR</SectionLabel>
                <View style={{ flexDirection: "row", flexWrap: "wrap", gap: 8 }}>
                  {STATUS_ORDER.filter((s) => s !== ticket.status).map((s) => (
                    <Pressable
                      key={s}
                      accessibilityRole="button"
                      disabled={busy}
                      onPress={() => run(() => supabase.rpc("set_ticket_status", { p_ticket_id: ticket.id, p_status: s, p_body: note.trim() || null }))}
                      style={({ pressed }) => ({ width: "48%", flexGrow: 1, minHeight: 52, borderRadius: 14, alignItems: "center", justifyContent: "center", backgroundColor: s === "tamamlandi" ? colors.basariZemin : colors.kutu, opacity: pressed || busy ? 0.7 : 1 })}
                    >
                      <Text style={{ fontFamily: FONT.kalin, fontSize: 15, color: s === "tamamlandi" ? colors.basari : colors.yazi }}>{s === "tamamlandi" ? "Tamamlandı" : STATUS_LABEL[s]}</Text>
                    </Pressable>
                  ))}
                </View>
                <Muted style={{ marginTop: -8, paddingHorizontal: 4 }}>Aşağıya cevap yazarsanız durumla birlikte sakine gider.</Muted>
              </>
            )}

            {events.length > 0 && (
              <>
                <SectionLabel>GEÇMİŞ</SectionLabel>
                <View style={{ gap: 14, paddingHorizontal: 4 }}>
                  {events.map((e) => {
                    const mine = e.author_role === "sakin";
                    return (
                      <View key={e.id} style={{ flexDirection: "row", gap: 12 }}>
                        <View style={{ width: 10, alignItems: "center", paddingTop: 6 }}>
                          <View style={{ width: 10, height: 10, borderRadius: 5, backgroundColor: mine ? colors.cizgi : colors.vurgu }} />
                        </View>
                        <View style={{ flex: 1, gap: 2 }}>
                          <Text style={{ fontFamily: FONT.kalin, fontSize: 15, color: colors.yazi }}>
                            {e.kind === "durum" && e.status ? (STATUS_LABEL[e.status as keyof typeof STATUS_LABEL] ?? e.status) : e.kind === "sonuc" ? (e.status === "cozuldu" ? "Sorun çözüldü" : "Sorun devam ediyor") : `${e.author_name ?? ROLE_LABEL[e.author_role]}`}
                          </Text>
                          {e.body ? <Body style={{ fontSize: 16 }}>{e.body}</Body> : null}
                          <Muted style={{ fontSize: 14 }}>
                            {e.kind !== "not" ? `${e.author_name ?? ""} (${ROLE_LABEL[e.author_role]}) · ` : `${ROLE_LABEL[e.author_role]} · `}
                            {formatDateTime(e.created_at)}
                          </Muted>
                        </View>
                      </View>
                    );
                  })}
                </View>
              </>
            )}

            <Field
              label={isResident ? "Not yaz" : "Cevap yaz"}
              value={note}
              onChangeText={setNote}
              maxLength={1000}
              multiline
              placeholder={isResident ? "Yönetime iletmek istedikleriniz…" : "Sakine cevabınız (sakin görür)…"}
              style={{ minHeight: 90, textAlignVertical: "top", paddingTop: 14 }}
            />
            {error && <Notice tone="hata" text={error} />}
            <Button label="Gönder" icon={Send} variant="ikincil" disabled={!note.trim()} loading={busy} onPress={() => run(() => supabase.rpc("add_ticket_note", { p_ticket_id: ticket.id, p_body: note }))} />
          </>
        )}
      </ScrollView>
    </KeyboardAvoidingView>
  );
}
