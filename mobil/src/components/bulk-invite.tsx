import { useCallback, useEffect, useMemo, useState } from "react";
import { Linking, Text, View } from "react-native";
import { FileSpreadsheet, MessageCircle, SkipForward, Users } from "lucide-react-native";
import * as DocumentPicker from "expo-document-picker";
import { File } from "expo-file-system";
import { NETWORK_ERROR, supabase, WEB_URL } from "@/lib/supabase";
import { formatPhone } from "@/lib/phone";
import { parseBulk, type BulkRow, type BulkUnit } from "@/lib/bulk-parse";
import { useWords } from "@/lib/words";
import { inviteMessage } from "@/components/invite-form";
import { Body, Button, Card, Field, ListGroup, ListRow, Muted, Notice, Pill, SectionLabel } from "@/components/ui";
import { FONT, useTheme } from "@/theme";

// Excel (.xlsx), CSV ya da PDF dosyasını seçtirir: kapalı geçici depoya yüklenir, sunucuda satırlara çevrilir ve hemen silinir
async function pickListFile(): Promise<{ text?: string; error?: string } | null> {
  const picked = await DocumentPicker.getDocumentAsync({ type: "*/*", copyToCacheDirectory: true, multiple: false });
  if (picked.canceled || !picked.assets?.[0]) return null;
  const asset = picked.assets[0];
  if ((asset.size ?? 0) > 10 * 1024 * 1024) return { error: "Dosya çok büyük (en fazla 10 MB)." };
  try {
    const { data } = await supabase.auth.getSession();
    const uid = data.session?.user.id;
    if (!uid) return { error: "Oturum bulunamadı. Yeniden giriş yapın." };
    const ext = (asset.name.split(".").pop() ?? "dosya").toLowerCase().replace(/[^a-z0-9]/g, "").slice(0, 8) || "dosya";
    const path = `${uid}/${Date.now()}-${Math.random().toString(36).slice(2, 8)}.${ext}`;
    const body = await new File(asset.uri).arrayBuffer();
    const up = await supabase.storage.from("listeler").upload(path, body, { contentType: asset.mimeType ?? "application/octet-stream", upsert: false });
    if (up.error) return { error: up.error.message.includes("fetch") ? NETWORK_ERROR : "Dosya yüklenemedi. Tekrar deneyin." };
    const res = await fetch(`${WEB_URL}/api/liste-oku`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${data.session?.access_token ?? ""}` },
      body: JSON.stringify({ path, name: asset.name }),
    });
    const out = (await res.json().catch(() => ({}))) as { text?: string; error?: string };
    return res.ok ? { text: out.text ?? "" } : { error: out.error ?? "Dosya okunamadı." };
  } catch {
    return { error: NETWORK_ERROR };
  }
}

type Pending = { id: string; code: string; token: string; full_name: string; phone: string; unit_id: string | null };

function useUnits(siteId: string) {
  const [units, setUnits] = useState<BulkUnit[]>([]);
  useEffect(() => {
    supabase
      .from("blocks")
      .select("name, units(id, no)")
      .eq("site_id", siteId)
      .then(({ data }) => setUnits(((data ?? []) as { name: string; units: { id: string; no: string }[] }[]).flatMap((b) => b.units.map((u) => ({ id: u.id, block: b.name, no: u.no })))));
  }, [siteId]);
  return units;
}

// Toplu davet: Excel'den kopyalanan liste → önizleme (hatalar kırmızı) → tek seferde davet → WhatsApp turu
export function BulkInvite({ siteId, siteName, onCreated }: { siteId: string; siteName: string; onCreated: () => void }) {
  const w = useWords();
  const units = useUnits(siteId);
  const [text, setText] = useState("");
  const [rows, setRows] = useState<BulkRow[] | null>(null);
  const [busy, setBusy] = useState(false);
  const [reading, setReading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<string | null>(null);
  const good = (rows ?? []).filter((r) => !r.error);
  const bad = (rows ?? []).filter((r) => r.error);

  function preview(source = text) {
    setError(null);
    setDone(null);
    const parsed = parseBulk(source, units, w.Nom);
    if (!parsed.length) return setError("Listede okunacak satır yok. Excel'den satırları kopyalayıp buraya yapıştırın.");
    setRows(parsed);
  }

  // Tek dokunuş: dosyayı seç → okunur → doğrudan önizleme
  async function fromFile() {
    setError(null);
    setDone(null);
    setReading(true);
    const r = await pickListFile();
    setReading(false);
    if (!r) return;
    if (r.error) return setError(r.error);
    setText(r.text ?? "");
    preview(r.text ?? "");
  }

  async function create() {
    setBusy(true);
    setError(null);
    const { data, error: e } = await supabase.rpc("create_invites_bulk", {
      p_site_id: siteId,
      p_rows: good.map((r) => ({ unit_id: r.unitId, full_name: r.name, phone: r.phone, relation: r.relation })),
    });
    setBusy(false);
    if (e) return setError(e.message.includes("fetch") ? NETWORK_ERROR : e.code === "SD040" ? "Bir seferde en fazla 1000 kişi davet edilebilir." : "Davetler oluşturulamadı. Listeyi kontrol edip tekrar deneyin.");
    const res = (data ?? []) as { status: string }[];
    const made = res.filter((r) => r.status === "davet").length;
    const already = res.length - made;
    setDone(`${made} davet hazır${already ? `, ${already} kişi zaten uygulamada` : ""}. Şimdi aşağıdaki WhatsApp turuyla gönderin.`);
    setRows(null);
    setText("");
    onCreated();
  }

  return (
    <>
      {done && <Notice tone="basari" text={done} />}
      {!rows ? (
        <Card>
          <Body style={{ fontFamily: FONT.kalin }}>Listeden toplu davet</Body>
          <Muted>{`Sakin listesinde ${w.nom}, ad soyad, telefon ve isteğe bağlı malik/kiracı sütunları olsun. Sütun sırası önemli değil; malik/kiracı yazmazsanız malik sayılır.`}</Muted>
          <Button label="Excel, CSV ya da PDF Dosyası Seç" icon={FileSpreadsheet} loading={reading} onPress={fromFile} />
          <Muted style={{ textAlign: "center" }}>ya da satırları kopyalayıp aşağıya yapıştırın</Muted>
          <Field
            label="Liste"
            value={text}
            onChangeText={setText}
            multiline
            autoCapitalize="none"
            autoCorrect={false}
            placeholder={"A-1   Ayşe Kaya   0532 123 45 67   Malik\nA-2   Mehmet Demir   0533 765 43 21   Kiracı"}
            style={{ minHeight: 160, textAlignVertical: "top", paddingTop: 14 }}
          />
          {error && <Notice tone="hata" text={error} />}
          <Button label="Önizle" variant="ikincil" disabled={!text.trim()} onPress={() => preview()} />
        </Card>
      ) : (
        <>
          <View style={{ flexDirection: "row", gap: 8, flexWrap: "wrap" }}>
            <Pill label={`${good.length} kişi hazır`} tone="basari" />
            {bad.length > 0 && <Pill label={`${bad.length} satır hatalı`} tone="hata" />}
          </View>
          {bad.length > 0 && (
            <>
              <SectionLabel>HATALI SATIRLAR (DAVET EDİLMEZ)</SectionLabel>
              <ListGroup>
                {bad.map((r) => (
                  <ListRow key={r.line} title={`${r.line}. satır: ${r.error}`} subtitle={r.raw} tone="tehlike" />
                ))}
              </ListGroup>
            </>
          )}
          {good.length > 0 && (
            <>
              <SectionLabel>DAVET EDİLECEKLER</SectionLabel>
              <ListGroup>
                {good.map((r) => (
                  <ListRow key={r.line} title={`${r.unitLabel} · ${r.name}`} subtitle={`${formatPhone(r.phone!)} · ${r.relation === "kiraci" ? "Kiracı" : "Malik"}`} />
                ))}
              </ListGroup>
            </>
          )}
          {error && <Notice tone="hata" text={error} />}
          <Button label={`${good.length} Kişiyi Davet Et`} icon={Users} disabled={!good.length} loading={busy} onPress={create} />
          <Button label="Listeyi Düzelt" variant="ikincil" onPress={() => setRows(null)} />
        </>
      )}
    </>
  );
}

// WhatsApp turu: gönderilmeyi bekleyen davetler sırayla; her dokunuşta bir kişinin hazır mesajı açılır ve "gönderildi" işaretlenir
export function InviteTour({ siteId, siteName, refreshKey }: { siteId: string; siteName: string; refreshKey: number }) {
  const { colors } = useTheme();
  const units = useUnits(siteId);
  const [list, setList] = useState<Pending[]>([]);
  const [sentNow, setSentNow] = useState(0);

  const load = useCallback(async () => {
    const { data } = await supabase
      .from("invites")
      .select("id, code, token, full_name, phone, unit_id")
      .eq("site_id", siteId)
      .eq("role", "sakin")
      .is("used_at", null)
      .is("cancelled_at", null)
      .is("sent_at", null)
      .gt("expires_at", new Date().toISOString())
      .order("created_at")
      .limit(1000);
    setList((data ?? []) as Pending[]);
  }, [siteId]);
  useEffect(() => {
    load();
  }, [load, refreshKey]);

  const label = useMemo(() => new Map(units.map((u) => [u.id, `${u.block}-${u.no}`])), [units]);
  if (!list.length) return null;
  const next = list[0];
  const total = list.length + sentNow;

  async function send() {
    const msg = inviteMessage({ code: next.code, token: next.token, name: next.full_name, phone: next.phone, label: label.get(next.unit_id ?? "") ?? "" }, siteName, 30);
    Linking.openURL(`https://wa.me/${next.phone}?text=${encodeURIComponent(msg)}`).catch(() => {});
    await supabase.rpc("mark_invite_sent", { p_invite_id: next.id });
    setList((l) => l.slice(1));
    setSentNow((n) => n + 1);
  }

  return (
    <Card>
      <View style={{ flexDirection: "row", alignItems: "center", justifyContent: "space-between", gap: 8 }}>
        <Body style={{ fontFamily: FONT.kalin }}>WhatsApp turu</Body>
        <Text style={{ fontFamily: FONT.orta, fontSize: 14, color: colors.yaziSoluk, fontVariant: ["tabular-nums"] }}>{`${list.length} davet bekliyor`}</Text>
      </View>
      <View style={{ height: 8, borderRadius: 4, backgroundColor: colors.kutuKoyu, overflow: "hidden" }}>
        <View style={{ width: `${total ? (sentNow / total) * 100 : 0}%`, height: 8, backgroundColor: colors.vurgu }} />
      </View>
      <View style={{ gap: 2, paddingVertical: 4 }}>
        <Muted>Sıradaki</Muted>
        <Text style={{ fontFamily: FONT.cokKalin, fontSize: 20, color: colors.yazi }}>{next.full_name}</Text>
        <Muted>{`${label.get(next.unit_id ?? "") ?? ""} · ${formatPhone(next.phone)}`}</Muted>
      </View>
      <Button label="WhatsApp'ta Gönder" icon={MessageCircle} onPress={send} />
      {list.length > 1 && (
        <Button
          label="Bu Kişiyi Sona Al"
          icon={SkipForward}
          variant="metin"
          onPress={() => setList((l) => [...l.slice(1), l[0]])}
        />
      )}
      <Muted>WhatsApp açılınca Gönder&apos;e basıp uygulamaya dönün, sonra sıradakine geçin. Kaldığınız yer kaydedilir.</Muted>
    </Card>
  );
}
