import * as Clipboard from "expo-clipboard";
import { useCallback, useEffect, useState } from "react";
import { Linking, Pressable, Text, View } from "react-native";
import { Copy, MessageCircle } from "lucide-react-native";
import { NETWORK_ERROR, supabase, WEB_URL } from "@/lib/supabase";
import { normalizePhone } from "@/lib/phone";
import { Body, Button, Card, Choice, Field, Grid, Muted, Notice } from "@/components/ui";
import { FONT, useTheme } from "@/theme";
import { useWords } from "@/lib/words";

type Block = { id: string; name: string; units: { id: string; no: string }[] };
type Invite = { id: string; role: string; full_name: string; created_at: string; used_at: string | null; cancelled_at: string | null; expires_at: string; unit_id: string | null };
export type Created = { code: string; token: string; name: string; phone: string; label: string };
type InviteRole = "sakin" | "danisma" | "yonetici";
const ROLE_CHOICE: Record<InviteRole, string> = { sakin: "Sakin", danisma: "Danışma", yonetici: "Yönetici" };

const RELATIONS = [
  { value: "malik", label: "Malik" },
  { value: "kiraci", label: "Kiracı" },
] as const;

export function inviteMessage(c: Created, siteName: string, validDays = 7) {
  return [
    `Merhaba ${c.name},`,
    "",
    `${siteName} yönetimi sizi SiteDesk uygulamasına davet ediyor${c.label ? ` (${c.label})` : ""}.`,
    "",
    `Bağlantı: ${WEB_URL}/davet/${c.token}`,
    `Davet kodu: ${c.code}`,
    "",
    `Bağlantıya dokunun ya da SiteDesk uygulamasında “Davet veya Şifre Kodum Var” deyip kodu yazın. Davet ${validDays} gün geçerlidir.`,
    "",
    `${siteName} Yönetimi`,
  ].join("\n");
}

// Davet: yönetici sakin, danışma ve yönetici davet eder (danışma davet edemez). WhatsApp'tan gönderilir (SMS yok).
// Ekran iskeleti olmadan döner; çağıran ekran kendi başlığıyla sarar.
export function InviteForm({ siteId, siteName, roles }: { siteId: string; siteName: string; roles: InviteRole[] }) {
  const w = useWords();
  const { colors } = useTheme();
  const [role, setRole] = useState<InviteRole>(roles[0]);
  const [blocks, setBlocks] = useState<Block[]>([]);
  const [unitId, setUnitId] = useState<string | null>(null);
  const [relation, setRelation] = useState<"malik" | "kiraci">("malik");
  const [name, setName] = useState("");
  const [phone, setPhone] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [created, setCreated] = useState<Created | null>(null);
  const [invites, setInvites] = useState<Invite[]>([]);

  const load = useCallback(async () => {
    const [{ data: b }, { data: inv }] = await Promise.all([
      supabase.from("blocks").select("id, name, units(id, no)").eq("site_id", siteId).order("name"),
      supabase.from("invites").select("id, role, full_name, created_at, used_at, cancelled_at, expires_at, unit_id").eq("site_id", siteId).neq("role", "sifre").order("created_at", { ascending: false }).limit(20),
    ]);
    setBlocks(((b ?? []) as Block[]).map((x) => ({ ...x, units: [...x.units].sort((p, q) => p.no.localeCompare(q.no, "tr", { numeric: true })) })));
    setInvites((inv ?? []) as Invite[]);
  }, [siteId]);
  useEffect(() => {
    load();
  }, [load]);

  const unitLabel = (id: string | null) => {
    for (const b of blocks) for (const u of b.units) if (u.id === id) return `${b.name}-${u.no}`;
    return "";
  };

  async function create() {
    setError(null);
    const p = normalizePhone(phone);
    if (role === "sakin" && !unitId) return setError(`${w.Nom.slice(0, 1)}${w.acc.slice(1)} seçin.`);
    if (name.trim().length < 3) return setError("Adı ve soyadı yazın.");
    if (!p) return setError("Telefonu 0532 123 45 67 gibi yazın.");
    setBusy(true);
    const { data, error: e } = await supabase.rpc("create_invite", {
      p_site_id: siteId,
      p_role: role,
      p_full_name: name.trim(),
      p_phone: p,
      p_unit_id: role === "sakin" ? unitId : null,
      p_relation: role === "sakin" ? relation : null,
    });
    setBusy(false);
    if (e) return setError(e.message.includes("fetch") ? NETWORK_ERROR : e.code === "42501" ? "Bu daveti açma yetkiniz yok." : "Davet oluşturulamadı. Lütfen tekrar deneyin.");
    const row = (data as { code: string; token: string }[])[0];
    const c: Created = { code: row.code, token: row.token, name: name.trim(), phone: p, label: role === "sakin" ? unitLabel(unitId) : role === "danisma" ? "Danışma görevlisi" : "Site yöneticisi" };
    setCreated(c);
    setName("");
    setPhone("");
    load();
    // Davet oluşturulur oluşturulmaz WhatsApp açılır (tek dokunuş); "gönderildi" işaretlenir ki WhatsApp turunda tekrar çıkmasın
    Linking.openURL(`https://wa.me/${c.phone}?text=${encodeURIComponent(inviteMessage(c, siteName))}`).catch(() => {});
    const { data: inv } = await supabase.from("invites").select("id").eq("token", c.token).maybeSingle();
    if (inv) supabase.rpc("mark_invite_sent", { p_invite_id: inv.id }).then(() => {});
  }

  async function cancel(id: string) {
    await supabase.rpc("cancel_invite", { p_invite_id: id });
    load();
  }

  const status = (i: Invite) =>
    i.used_at ? { text: "Katıldı", color: colors.basari } : i.cancelled_at ? { text: "İptal", color: colors.yaziSoluk } : new Date(i.expires_at) < new Date() ? { text: "Süresi doldu", color: colors.yaziSoluk } : { text: "Bekliyor", color: colors.bekliyor };

  return (
    <>
      {created && (
        <Card>
          <Body style={{ fontFamily: FONT.kalin }}>Davet hazır: {created.name}</Body>
          <Muted>Davet kodu</Muted>
          <Text selectable style={{ fontFamily: FONT.cokKalin, fontSize: 28, letterSpacing: 3, color: colors.yazi }}>{created.code}</Text>
          <Button label="WhatsApp'ta Gönder" icon={MessageCircle} onPress={() => Linking.openURL(`https://wa.me/${created.phone}?text=${encodeURIComponent(inviteMessage(created, siteName))}`)} />
          <Button label="Mesajı Kopyala" variant="ikincil" icon={Copy} onPress={() => Clipboard.setStringAsync(inviteMessage(created, siteName))} />
        </Card>
      )}

      <Card>
        <Body style={{ fontFamily: FONT.kalin }}>Yeni davet</Body>
        {roles.length > 1 && (
          <View accessibilityRole="radiogroup" style={{ flexDirection: "row", gap: 10 }}>
            {roles.map((r) => (
              <Choice key={r} label={ROLE_CHOICE[r]} selected={role === r} onPress={() => setRole(r)} />
            ))}
          </View>
        )}
        {role === "sakin" &&
          (blocks.length === 0 ? (
            <Notice tone="bekliyor" text={`Bu sitede henüz blok ve ${w.nom} yok. Kişiler › ${w.Plural} bölümünden ekleyin.`} />
          ) : (
            <>
              <Muted>{w.Nom}</Muted>
              {blocks.map((b) => (
                <View key={b.id} style={{ gap: 6 }}>
                  <Text style={{ fontFamily: FONT.kalin, fontSize: 15, color: colors.yaziSoluk }}>{b.name} Blok</Text>
                  <Grid minItemWidth={70}>
                    {b.units.map((u) => {
                      const on = unitId === u.id;
                      return (
                        <Pressable
                          key={u.id}
                          accessibilityRole="radio"
                          accessibilityState={{ selected: on }}
                          accessibilityLabel={`${b.name}-${u.no}`}
                          onPress={() => setUnitId(u.id)}
                          style={{ height: 52, borderRadius: 12, borderWidth: 2, paddingHorizontal: 4, alignItems: "center", justifyContent: "center", borderColor: on ? colors.vurgu : colors.cizgi, backgroundColor: on ? colors.vurguAcik : colors.kutu }}
                        >
                          <Text numberOfLines={1} adjustsFontSizeToFit minimumFontScale={0.7} style={{ fontFamily: on ? FONT.cokKalin : FONT.orta, fontSize: 16, color: colors.yazi }}>{`${b.name}-${u.no}`}</Text>
                        </Pressable>
                      );
                    })}
                  </Grid>
                </View>
              ))}
              <View accessibilityRole="radiogroup" style={{ flexDirection: "row", gap: 8 }}>
                {RELATIONS.map((r) => (
                  <Choice key={r.value} label={r.label} selected={relation === r.value} onPress={() => setRelation(r.value)} />
                ))}
              </View>
            </>
          ))}
        <Field label="Ad soyad" value={name} onChangeText={setName} autoCapitalize="words" />
        <Field label="Cep telefonu" value={phone} onChangeText={setPhone} keyboardType="phone-pad" placeholder="0532 123 45 67" />
        {error && <Notice tone="hata" text={error} />}
        <Button label="Davet Et ve WhatsApp'ta Gönder" icon={MessageCircle} onPress={create} loading={busy} />
      </Card>

      {invites.length > 0 && (
        <Card>
          <Body style={{ fontFamily: FONT.kalin }}>Son davetler</Body>
          {invites.map((i) => {
            const s = status(i);
            const open = !i.used_at && !i.cancelled_at && new Date(i.expires_at) > new Date();
            return (
              <View key={i.id} style={{ flexDirection: "row", alignItems: "center", justifyContent: "space-between", gap: 8, minHeight: 48, borderTopWidth: 1, borderTopColor: colors.cizgi, paddingTop: 8 }}>
                <View style={{ flex: 1 }}>
                  <Body>{i.full_name}</Body>
                  <Muted>
                    {i.role === "sakin" ? unitLabel(i.unit_id) : i.role === "danisma" ? "Danışma" : "Yönetici"} · <Text style={{ color: s.color }}>{s.text}</Text>
                  </Muted>
                </View>
                {open && (
                  <Pressable accessibilityRole="button" onPress={() => cancel(i.id)} style={{ minHeight: 48, justifyContent: "center", paddingHorizontal: 8 }}>
                    <Text style={{ fontFamily: FONT.orta, fontSize: 15, color: colors.hata }}>İptal</Text>
                  </Pressable>
                )}
              </View>
            );
          })}
        </Card>
      )}
    </>
  );
}
