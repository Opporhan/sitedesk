import { useCallback, useEffect, useState } from "react";
import { Alert, Linking, Pressable, Text, View } from "react-native";
import { MessageCircle, Phone, Plus } from "lucide-react-native";
import { useAuth } from "@/auth";
import { todayTR } from "@/lib/format";
import { NETWORK_ERROR, supabase } from "@/lib/supabase";
import { formatPhone, normalizePhone } from "@/lib/phone";
import { sendPasswordReset } from "@/lib/reset";
import { unitTypeOf, unitWords } from "@/lib/words";
import { Sheet } from "@/components/sheet";
import { InviteForm } from "@/components/invite-form";
import { BulkInvite, InviteTour } from "@/components/bulk-invite";
import { JoinRequests, SiteCodeCard } from "@/components/join-requests";
import { Avatar } from "@/components/avatar";
import { Body, Button, Card, Choice, Field, Grid, ListGroup, ListRow, Muted, Notice, SectionLabel, Segmented } from "@/components/ui";
import { FONT, useTheme } from "@/theme";

type Section = "davet" | "sakinler" | "danisma" | "daireler";
type UnitRow = { id: string; no: string; block_id: string };
type BlockRow = { id: string; name: string; units: UnitRow[] };
type Link = { id: string; unit_id: string; relation: string; started_on: string; residents: { id: string; full_name: string; phone: string | null; user_id: string | null } | null };
type Desk = { id: string; started_on: string; user_id: string; role: string; profiles: { full_name: string; phone: string | null; avatar_path: string | null } | null };

const RELATION_LABEL: Record<string, string> = { malik: "Malik", kiraci: "Kiracı" };

// Kişiye tek dokunuşla arama ve WhatsApp
export function ContactButtons({ phone }: { phone: string | null }) {
  const { colors } = useTheme();
  if (!phone) return <Muted>Telefon yok</Muted>;
  const btn = { minWidth: 48, minHeight: 48, borderRadius: 24, alignItems: "center" as const, justifyContent: "center" as const, backgroundColor: colors.kutuKoyu };
  return (
    <View style={{ flexDirection: "row", gap: 8 }}>
      <Pressable accessibilityRole="button" accessibilityLabel={`Ara: ${formatPhone(phone)}`} style={btn} onPress={() => Linking.openURL(`tel:+${phone}`)}>
        <Phone size={20} color={colors.vurgu} />
      </Pressable>
      <Pressable accessibilityRole="button" accessibilityLabel="WhatsApp'tan yaz" style={btn} onPress={() => Linking.openURL(`https://wa.me/${phone}`)}>
        <MessageCircle size={20} color={colors.basari} />
      </Pressable>
    </View>
  );
}

// Yönetici › Kişiler: davet, sakinler (bilgi düzeltme, şifre kodu, taşındı), danışma görevlileri, bloklar ve daireler/villalar
export function PeopleManager({ siteId, siteName, siteType }: { siteId: string; siteName: string; siteType: string }) {
  const { colors } = useTheme();
  const w = unitWords(siteType);
  const [inviteMode, setInviteMode] = useState<"tek" | "toplu">("tek");
  const [tourKey, setTourKey] = useState(0);
  const [editing, setEditing] = useState<Link | null>(null);
  const [editName, setEditName] = useState("");
  const [editPhone, setEditPhone] = useState("");
  const [section, setSection] = useState<Section>("davet");
  const [blocks, setBlocks] = useState<BlockRow[]>([]);
  const [links, setLinks] = useState<Link[]>([]);
  const [staff, setStaff] = useState<Desk[]>([]);
  const { session, context } = useAuth();
  const myId = session?.user.id;
  const [founder, setFounder] = useState<string | null>(null);
  const desks = staff.filter((x) => x.role === "danisma");
  const managers = staff.filter((x) => x.role === "yonetici");
  const [avatars, setAvatars] = useState<Record<string, string | null>>({});
  const [error, setError] = useState<string | null>(null);
  const [blockName, setBlockName] = useState("");
  const [unitBlock, setUnitBlock] = useState<string | null>(null);
  const [unitNos, setUnitNos] = useState("");
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    const [b, l, d, st] = await Promise.all([
      supabase.from("blocks").select("id, name, units(id, no, block_id)").eq("site_id", siteId).order("name"),
      supabase.from("unit_residents").select("id, unit_id, relation, started_on, residents(id, full_name, phone, user_id)").eq("site_id", siteId).is("ended_on", null),
      supabase.from("memberships").select("id, started_on, user_id, role, profiles(full_name, phone, avatar_path)").eq("site_id", siteId).in("role", ["danisma", "yonetici"]).is("ended_on", null),
      supabase.from("sites").select("created_by").eq("id", siteId).maybeSingle(),
    ]);
    if (b.error) return setError(b.error.message.includes("fetch") ? NETWORK_ERROR : "Bilgiler alınamadı.");
    setBlocks(((b.data ?? []) as BlockRow[]).map((x) => ({ ...x, units: [...x.units].sort((p, q) => p.no.localeCompare(q.no, "tr", { numeric: true })) })));
    const ls = (l.data ?? []) as unknown as Link[];
    setLinks(ls);
    const ids = ls.map((x) => x.residents?.user_id).filter(Boolean) as string[];
    if (ids.length) {
      const { data: prof } = await supabase.from("profiles").select("user_id, avatar_path").in("user_id", ids);
      setAvatars(Object.fromEntries((prof ?? []).map((x) => [x.user_id as string, x.avatar_path as string | null])));
    }
    setStaff((d.data ?? []) as unknown as Desk[]);
    setFounder((st.data?.created_by as string | null) ?? null);
  }, [siteId]);
  useEffect(() => {
    load();
  }, [load, section]);

  const label = (unitId: string) => {
    for (const b of blocks) for (const u of b.units) if (u.id === unitId) return `${b.name}-${u.no}`;
    return "";
  };

  function confirm(title: string, text: string, onYes: () => Promise<void>) {
    Alert.alert(title, text, [
      { text: "Vazgeç", style: "cancel" },
      { text: "Evet", style: "destructive", onPress: () => onYes() },
    ]);
  }

  async function act(fn: () => PromiseLike<{ error: { message: string; code?: string } | null }>, failText: string) {
    setBusy(true);
    setError(null);
    const { error: e } = await fn();
    setBusy(false);
    if (e) setError(e.message.includes("fetch") ? NETWORK_ERROR : e.code === "23503" ? "Bağlı kayıt ya da kişi var; silinemez." : e.code === "23505" ? "Bu ad ya da telefon zaten kayıtlı." : e.code === "SD020" ? "Uygulama hesabı olan kişinin telefonu değiştirilemez." : failText);
    load();
  }

  // Sakine dokununca: bilgileri düzelt · şifre kodu (hesabı varsa) · taşındı
  function residentMenu(l: Link, unitText: string) {
    const r = l.residents;
    if (!r) return;
    Alert.alert(r.full_name, `${unitText} · ${RELATION_LABEL[l.relation] ?? l.relation}`, [
      {
        text: "Bilgileri Düzelt",
        onPress: () => {
          setEditing(l);
          setEditName(r.full_name);
          setEditPhone(r.phone ? formatPhone(r.phone) : "");
          setError(null);
        },
      },
      ...(r.user_id && r.phone
        ? [{ text: "Şifre Yenileme Kodu Gönder", onPress: async () => setError(await sendPasswordReset(siteId, siteName, r.phone!)) }]
        : []),
      {
        text: "Taşındı",
        style: "destructive" as const,
        onPress: () =>
          confirm("Taşındı mı?", `${r.full_name} artık ${unitText} ${w.possGen} kayıtlarını göremez. Kayıtlar silinmez.`, () =>
            act(() => supabase.rpc("end_residency", { p_unit_resident_id: l.id }), "Erişim kapatılamadı.")
          ),
      },
      { text: "Vazgeç", style: "cancel" as const },
    ]);
  }

  async function saveResident() {
    if (!editing?.residents) return;
    const phone = editPhone.trim() ? normalizePhone(editPhone) : null;
    if (editPhone.trim() && !phone) return setError("Telefonu 0532 123 45 67 gibi yazın.");
    if (editName.trim().length < 3) return setError("Adı ve soyadı yazın.");
    let failed = false;
    await act(async () => {
      const r = await supabase.rpc("update_resident", { p_resident_id: editing.residents!.id, p_full_name: editName.trim(), p_phone: phone });
      failed = !!r.error;
      return r;
    }, "Kaydedilemedi.");
    if (!failed) setEditing(null);
  }

  // "1-12" ya da "1, 2, 5" → numaralar
  function parseNos(text: string): string[] {
    const out: string[] = [];
    for (const part of text.split(",").map((p) => p.trim()).filter(Boolean)) {
      const m = part.match(/^(\d+)\s*-\s*(\d+)$/);
      if (m) for (let i = Number(m[1]); i <= Number(m[2]) && out.length < 300; i++) out.push(String(i));
      else out.push(part.slice(0, 20));
    }
    return [...new Set(out)];
  }

  const SECTIONS: { key: Section; label: string }[] = [
    { key: "davet", label: "Davet" },
    { key: "sakinler", label: "Sakinler" },
    { key: "danisma", label: "Görevliler" },
    { key: "daireler", label: w.Plural },
  ];

  return (
    <>
      <JoinRequests siteId={siteId} onChange={load} />
      <Segmented value={section} onChange={setSection} options={SECTIONS} />
      {error && <Notice tone="hata" text={error} />}

      {section === "danisma" && managers.length > 0 && (
        <>
          <SectionLabel>YÖNETİCİLER</SectionLabel>
          <ListGroup>
            {managers.map((m) => {
              const self = m.user_id === myId;
              // Siteyi açan yöneticinin erişimini sadece sistem yöneticisi kapatır
              const locked = self || (m.user_id === founder && !context?.platform_admin);
              return (
                <ListRow
                  key={m.id}
                  left={<Avatar path={m.profiles?.avatar_path} name={m.profiles?.full_name} size={40} />}
                  title={`${m.profiles?.full_name || "Yönetici"}${self ? " (siz)" : ""}${m.user_id === founder ? " · Kurucu" : ""}`}
                  subtitle={m.profiles?.phone ? formatPhone(m.profiles.phone) : undefined}
                  right={self ? undefined : <ContactButtons phone={m.profiles?.phone ?? null} />}
                  chevron={false}
                  onPress={
                    locked
                      ? undefined
                      : () =>
                          confirm("Yöneticilik kapatılsın mı?", `${m.profiles?.full_name ?? "Bu kişi"} artık bu siteyi yönetemez. Kayıtlar silinmez.`, () =>
                            act(() => supabase.from("memberships").update({ ended_on: todayTR() }).eq("id", m.id), "Erişim kapatılamadı.")
                          )
                  }
                />
              );
            })}
          </ListGroup>
          {managers.length > 1 && <Muted style={{ paddingHorizontal: 4 }}>Bir yöneticinin erişimini kapatmak için adına dokunun. Kendi erişiminizi ve siteyi açan yöneticininkini kapatamazsınız.</Muted>}
          <SectionLabel>DANIŞMA</SectionLabel>
        </>
      )}

      {section === "davet" && (
        <>
          <SiteCodeCard siteId={siteId} siteName={siteName} />
          <InviteTour siteId={siteId} siteName={siteName} refreshKey={tourKey} />
          <Segmented
            value={inviteMode}
            onChange={setInviteMode}
            options={[
              { key: "tek", label: "Tek kişi" },
              { key: "toplu", label: "Listeden toplu" },
            ]}
          />
          {inviteMode === "tek" ? (
            <InviteForm siteId={siteId} siteName={siteName} roles={["sakin", "danisma", "yonetici"]} />
          ) : (
            <BulkInvite
              siteId={siteId}
              siteName={siteName}
              onCreated={() => {
                setTourKey((k) => k + 1);
                load();
              }}
            />
          )}
        </>
      )}

      {section === "sakinler" &&
        (links.length === 0 ? (
          <Muted>Henüz sakin yok. Davet bölümünden sakin davet edin.</Muted>
        ) : (
          blocks
            .flatMap((b) => b.units)
            .filter((u) => links.some((l) => l.unit_id === u.id))
            .map((u) => (
              <View key={u.id} style={{ gap: 14 }}>
                <SectionLabel>{label(u.id)}</SectionLabel>
                <ListGroup>
                  {links
                    .filter((l) => l.unit_id === u.id)
                    .map((l) => (
                      <ListRow
                        key={l.id}
                        left={<Avatar path={l.residents?.user_id ? avatars[l.residents.user_id] : null} name={l.residents?.full_name} size={40} />}
                        title={l.residents?.full_name ?? ""}
                        subtitle={`${RELATION_LABEL[l.relation] ?? l.relation} · ${l.residents?.user_id ? "Uygulamada" : "Uygulamada değil"}`}
                        right={<ContactButtons phone={l.residents?.phone ?? null} />}
                        chevron={false}
                        onPress={() => residentMenu(l, label(u.id))}
                      />
                    ))}
                </ListGroup>
              </View>
            ))
        ))}
      {section === "sakinler" && links.length > 0 && <Muted style={{ paddingHorizontal: 4 }}>Bilgileri düzeltmek, şifre yenileme kodu göndermek ya da taşınanın erişimini kapatmak için adına dokunun.</Muted>}

      {section === "danisma" &&
        (desks.length === 0 ? (
          <Muted>Danışma görevlisi yok. Davet bölümünden "Danışma" seçerek davet edin. Başka bir yönetici eklemek için "Yönetici"yi seçin.</Muted>
        ) : (
          <>
            <ListGroup>
              {desks.map((d) => (
                <ListRow
                  key={d.id}
                  left={<Avatar path={d.profiles?.avatar_path} name={d.profiles?.full_name} size={40} />}
                  title={d.profiles?.full_name || "Danışma görevlisi"}
                  subtitle={d.profiles?.phone ? formatPhone(d.profiles.phone) : undefined}
                  right={<ContactButtons phone={d.profiles?.phone ?? null} />}
                  chevron={false}
                  onPress={() =>
                    Alert.alert(d.profiles?.full_name || "Danışma görevlisi", undefined, [
                      ...(d.profiles?.phone
                        ? [{ text: "Şifre Yenileme Kodu Gönder", onPress: async () => setError(await sendPasswordReset(siteId, siteName, d.profiles!.phone!)) }]
                        : []),
                      {
                        text: "Ayrıldı",
                        style: "destructive" as const,
                        onPress: () =>
                          confirm("Ayrıldı mı?", `${d.profiles?.full_name ?? "Görevli"} artık bu sitenin danışma ekranına giremez.`, () =>
                            act(() => supabase.from("memberships").update({ ended_on: todayTR() }).eq("id", d.id), "Erişim kapatılamadı.")
                          ),
                      },
                      { text: "Vazgeç", style: "cancel" as const },
                    ])
                  }
                />
              ))}
            </ListGroup>
            <Muted style={{ paddingHorizontal: 4 }}>Şifre yenileme kodu göndermek ya da ayrılan görevlinin erişimini kapatmak için adına dokunun.</Muted>
          </>
        ))}

      {section === "daireler" && (
        <>
          <Card>
            <Body style={{ fontFamily: FONT.kalin }}>Blok ekle</Body>
            <Field label="Blok adı" value={blockName} onChangeText={setBlockName} placeholder="Ör. A" autoCapitalize="characters" maxLength={30} />
            <Button
              label="Bloğu Ekle"
              icon={Plus}
              variant="ikincil"
              loading={busy}
              disabled={!blockName.trim()}
              onPress={() =>
                act(async () => {
                  const r = await supabase.from("blocks").insert({ site_id: siteId, name: blockName.trim().toLocaleUpperCase("tr-TR").replace(/\s*BLOK$/, "") });
                  if (!r.error) setBlockName("");
                  return r;
                }, "Blok eklenemedi.")
              }
            />
          </Card>
          {blocks.length > 0 && (
            <Card>
              <Body style={{ fontFamily: FONT.kalin }}>{w.Nom} ekle</Body>
              <View style={{ flexDirection: "row", flexWrap: "wrap", gap: 8 }}>
                {blocks.map((b) => (
                  <View key={b.id} style={{ minWidth: 72 }}>
                    <Choice label={`${b.name} Blok`} selected={unitBlock === b.id} onPress={() => setUnitBlock(b.id)} />
                  </View>
                ))}
              </View>
              <Field label={`${w.Nom} numaraları`} value={unitNos} onChangeText={setUnitNos} placeholder="Ör. 1-12 ya da 1, 2, 5" />
              <Button
                label={`${w.PluralAcc} Ekle`}
                icon={Plus}
                variant="ikincil"
                loading={busy}
                disabled={!unitBlock || !unitNos.trim()}
                onPress={() =>
                  act(async () => {
                    const existing = new Set(blocks.find((b) => b.id === unitBlock)?.units.map((u) => u.no));
                    const rows = parseNos(unitNos).filter((no) => !existing.has(no)).map((no) => ({ site_id: siteId, block_id: unitBlock!, no, type: unitTypeOf(siteType) }));
                    const r = rows.length ? await supabase.from("units").insert(rows) : { error: null };
                    if (!r.error) setUnitNos("");
                    return r;
                  }, `${w.Plural} eklenemedi.`)
                }
              />
            </Card>
          )}
          {blocks.map((b) => (
            <Card key={b.id}>
              <View style={{ flexDirection: "row", alignItems: "center", justifyContent: "space-between", gap: 8 }}>
                <Body style={{ fontFamily: FONT.kalin }}>
                  {b.name} Blok · {b.units.length} {w.nom}
                </Body>
                {b.units.length === 0 && (
                  <Pressable
                    accessibilityRole="button"
                    onPress={() => confirm("Blok silinsin mi?", `${b.name} Blok silinecek.`, () => act(() => supabase.from("blocks").delete().eq("id", b.id), "Blok silinemedi."))}
                    style={{ minHeight: 44, justifyContent: "center", paddingHorizontal: 8 }}
                  >
                    <Text style={{ fontFamily: FONT.orta, fontSize: 15, color: colors.hata }}>Bloğu sil</Text>
                  </Pressable>
                )}
              </View>
              <Grid minItemWidth={56}>
                {b.units.map((u) => (
                  <Pressable
                    key={u.id}
                    accessibilityRole="button"
                    accessibilityLabel={`${b.name}-${u.no} ${w.acc} sil`}
                    onLongPress={() => confirm(`${w.Nom} silinsin mi?`, `${b.name}-${u.no} silinecek. Kişi ya da kayıt bağlıysa silinmez.`, () => act(() => supabase.from("units").delete().eq("id", u.id), `${w.Nom} silinemedi.`))}
                    style={{ height: 44, borderRadius: 10, borderWidth: 1, borderColor: colors.cizgi, alignItems: "center", justifyContent: "center", paddingHorizontal: 4, backgroundColor: colors.kutu }}
                  >
                    <Text numberOfLines={1} adjustsFontSizeToFit minimumFontScale={0.7} style={{ fontFamily: FONT.orta, fontSize: 15, color: colors.yazi, fontVariant: ["tabular-nums"] }}>{u.no}</Text>
                  </Pressable>
                ))}
              </Grid>
              <Muted>{`Silmek için ${w.dat} basılı tutun.`}</Muted>
            </Card>
          ))}
        </>
      )}
      <Sheet visible={!!editing} onClose={() => setEditing(null)} title={editing?.residents?.full_name ?? ""} subtitle="Bilgileri düzelt">
        <Field label="Ad soyad" value={editName} onChangeText={setEditName} autoCapitalize="words" maxLength={100} />
        <Field
          label="Cep telefonu"
          value={editPhone}
          onChangeText={setEditPhone}
          keyboardType="phone-pad"
          placeholder="0532 123 45 67"
          editable={!editing?.residents?.user_id}
        />
        {editing?.residents?.user_id ? <Muted>Uygulama hesabı olan kişinin telefonu giriş numarasıdır, değiştirilemez.</Muted> : null}
        {error && <Notice tone="hata" text={error} />}
        <Button label="Kaydet" onPress={saveResident} loading={busy} />
      </Sheet>
    </>
  );
}
