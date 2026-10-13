import { router } from "expo-router";
import { openSitesList } from "@/lib/nav";
import { useCallback, useEffect, useState } from "react";
import { ActivityIndicator, Alert, Pressable, Switch, Text, View } from "react-native";
import { File } from "expo-file-system";
import { Bell, Building2, Camera, Check, Fingerprint, KeyRound, LogOut, Pencil, Plus, Trash2 } from "lucide-react-native";
import { enablePush, pushStatus, sendTestPush } from "@/lib/push";
import { roleKey, roleLabel, useAuth } from "@/auth";
import { callServer, NETWORK_ERROR, supabase } from "@/lib/supabase";
import { pickAvatar } from "@/lib/media";
import { Avatar, forgetAvatar } from "@/components/avatar";
import { Button, Field, ListGroup, ListRow, Muted, Notice, Screen, SectionLabel } from "@/components/ui";
import { Sheet } from "@/components/sheet";
import { FONT, useTheme } from "@/theme";
import { useWords } from "@/lib/words";

// Profil: kişi, rol seçimi (birden çok rolü olan için), parmak izi / yüz tanıma, çıkış, hesabı silme. Tema sağ üstte.
export function ProfileScreen() {
  const w = useWords();
  const { colors } = useTheme();
  const { context, active, roleOptions, setActive, biometric, signOut, session, reloadContext } = useAuth();
  const [push, setPush] = useState<"acik" | "kapali" | "desteklenmiyor">("kapali");
  const [pushMsg, setPushMsg] = useState<{ ok: boolean; text: string } | null>(null);
  const [pushBusy, setPushBusy] = useState(false);
  useEffect(() => {
    pushStatus().then(setPush);
  }, []);
  const [nameEdit, setNameEdit] = useState<string | null>(null);
  const [nameBusy, setNameBusy] = useState(false);
  const [nameError, setNameError] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [deleting, setDeleting] = useState(false);
  const name = context?.full_name || "Adınız";
  const userId = session?.user.id;
  const [avatarPath, setAvatarPath] = useState<string | null>(null);
  const [localAvatar, setLocalAvatar] = useState<string | null>(null);
  const [uploading, setUploading] = useState(false);

  const loadAvatar = useCallback(async () => {
    if (!userId) return;
    const { data } = await supabase.from("profiles").select("avatar_path").eq("user_id", userId).maybeSingle();
    setAvatarPath((data?.avatar_path as string | null) ?? null);
  }, [userId]);
  useEffect(() => {
    loadAvatar();
  }, [loadAvatar]);

  // Resim seç → kare kırp, küçült → depoya yükle → profile kaydet → eskisini sil
  async function changeAvatar(source: "kamera" | "galeri") {
    if (!userId) return;
    setError(null);
    const uri = await pickAvatar(source).catch(() => null);
    if (!uri) return;
    setLocalAvatar(uri);
    setUploading(true);
    try {
      const path = `${userId}/${Date.now()}.jpg`;
      const body = await new File(uri).arrayBuffer();
      const up = await supabase.storage.from("profil").upload(path, body, { contentType: "image/jpeg" });
      if (up.error) throw up.error;
      const { error: e } = await supabase.rpc("set_my_avatar", { p_path: path });
      if (e) throw e;
      if (avatarPath) {
        forgetAvatar(avatarPath);
        await supabase.storage.from("profil").remove([avatarPath]);
      }
      setAvatarPath(path);
    } catch (e) {
      setLocalAvatar(null);
      setError(String((e as Error)?.message ?? "").includes("fetch") ? NETWORK_ERROR : "Resim yüklenemedi. Lütfen tekrar deneyin.");
    } finally {
      setUploading(false);
    }
  }

  async function removeAvatar() {
    if (!avatarPath) return;
    const old = avatarPath;
    const { error: e } = await supabase.rpc("set_my_avatar", { p_path: null });
    if (e) return setError("Resim kaldırılamadı.");
    forgetAvatar(old);
    await supabase.storage.from("profil").remove([old]);
    setAvatarPath(null);
    setLocalAvatar(null);
  }

  function avatarMenu() {
    Alert.alert("Profil resmi", undefined, [
      { text: "Fotoğraf Çek", onPress: () => changeAvatar("kamera") },
      { text: "Galeriden Seç", onPress: () => changeAvatar("galeri") },
      ...(avatarPath ? [{ text: "Resmi Kaldır", style: "destructive" as const, onPress: removeAvatar }] : []),
      { text: "Vazgeç", style: "cancel" as const },
    ]);
  }

  // Kişi kendi adını düzeltir (görevliler ve aynı dairedekiler bu adı görür)
  async function saveName() {
    if (!userId || nameEdit === null) return;
    if (nameEdit.trim().length < 3) return setNameError("Adınızı ve soyadınızı yazın.");
    setNameBusy(true);
    setNameError(null);
    const { error: e } = await supabase.from("profiles").update({ full_name: nameEdit.trim().slice(0, 100) }).eq("user_id", userId);
    setNameBusy(false);
    if (e) return setNameError(e.message.includes("fetch") ? NETWORK_ERROR : "Kaydedilemedi.");
    await reloadContext();
    setNameEdit(null);
  }

  function confirmDelete() {
    Alert.alert("Hesabınız silinsin mi?", "Giriş bilgileriniz silinir ve uygulamaya bir daha bu hesapla giremezsiniz. Bu işlem geri alınamaz.", [
      { text: "Vazgeç", style: "cancel" },
      { text: "Hesabımı Sil", style: "destructive", onPress: deleteAccount },
    ]);
  }

  async function deleteAccount() {
    setDeleting(true);
    setError(null);
    const { data } = await supabase.auth.getSession();
    const r = await callServer("/api/hesap-sil", {}, data.session?.access_token ?? session?.access_token);
    setDeleting(false);
    if (!r.ok) return setError(r.error ?? "Hesap silinemedi.");
    await signOut();
    router.replace("/giris");
  }

  return (
    <Screen title="Profil">
      <View style={{ alignItems: "center", gap: 10 }}>
        <Pressable accessibilityRole="button" accessibilityLabel="Profil resmini değiştir" onPress={avatarMenu} disabled={uploading}>
          <Avatar path={avatarPath} localUri={localAvatar} name={name} size={104} />
          <View style={{ position: "absolute", right: 0, bottom: 0, width: 36, height: 36, borderRadius: 18, backgroundColor: colors.vurgu, alignItems: "center", justifyContent: "center", borderWidth: 3, borderColor: colors.zemin }}>
            {uploading ? <ActivityIndicator size="small" color={colors.vurguYazi} /> : <Camera size={16} color={colors.vurguYazi} />}
          </View>
        </Pressable>
        <View style={{ alignItems: "center", gap: 2 }}>
          <Pressable accessibilityRole="button" accessibilityLabel="Adımı düzelt" onPress={() => { setNameEdit(context?.full_name ?? ""); setNameError(null); }} style={{ flexDirection: "row", alignItems: "center", gap: 8, minHeight: 44 }}>
            <Text style={{ fontFamily: FONT.kalin, fontSize: 21, color: colors.yazi }}>{name}</Text>
            <Pencil size={16} color={colors.yaziSoluk} />
          </Pressable>
          <Muted>{roleLabel(active)}</Muted>
        </View>
      </View>

      {(context?.units.length ?? 0) > 0 && (
        <>
          <SectionLabel>{`${w.Plural.toLocaleUpperCase("tr-TR")}M`}</SectionLabel>
          <ListGroup>
            {context!.units.map((u) => (
              <ListRow key={u.unit_id} title={u.label} subtitle={`${u.site_name} · ${u.relation === "kiraci" ? "Kiracı" : "Malik"}`} />
            ))}
          </ListGroup>
        </>
      )}

      {roleOptions.length > 1 && (
        <>
          <SectionLabel>ROLÜM</SectionLabel>
          <ListGroup>
            {roleOptions.map((r) => {
              const on = roleKey(r) === roleKey(active);
              return (
                <ListRow
                  key={roleKey(r)}
                  title={roleLabel(r)}
                  right={on ? <Check size={20} color={colors.vurgu} /> : undefined}
                  chevron={false}
                  onPress={() => {
                    setActive(r);
                    router.replace("/");
                  }}
                />
              );
            })}
          </ListGroup>
        </>
      )}

      {!context?.platform_admin && (
        <>
          <SectionLabel>SİTELERİM</SectionLabel>
          <ListGroup>
            <ListRow left={<KeyRound size={22} color={colors.vurgu} strokeWidth={1.75} />} title="Siteye Katıl" subtitle="Site koduyla başka bir siteye ya da daireye katılın" onPress={() => router.push("/katil")} />
            {roleOptions.filter((r) => r.kind === "yonetici").length > 1 && (
              <ListRow left={<Building2 size={22} color={colors.vurgu} strokeWidth={1.75} />} title="Bütün Sitelerim" onPress={openSitesList} />
            )}
            {active.kind === "yonetici" && (
              <ListRow left={<Plus size={22} color={colors.vurgu} strokeWidth={1.75} />} title="Yeni Site Ekle" subtitle="Yönettiğiniz yeni bir siteyi açın" onPress={() => router.push("/site-yonetimi/yeni")} />
            )}
          </ListGroup>
        </>
      )}

      {push !== "desteklenmiyor" && (
        <>
          <SectionLabel>BİLDİRİMLER</SectionLabel>
          <ListGroup>
            <ListRow
              left={<Bell size={22} color={push === "acik" ? colors.vurgu : colors.yaziSoluk} strokeWidth={1.75} />}
              title={push === "acik" ? "Bildirimler açık" : "Bildirimler kapalı"}
              subtitle={pushBusy ? "Kontrol ediliyor…" : push === "acik" ? "Deneme bildirimi göndermek için dokunun" : "Açmak için dokunun"}
              chevron={false}
              onPress={async () => {
                if (pushBusy) return;
                setPushBusy(true);
                setPushMsg(null);
                const r = push === "acik" ? await sendTestPush() : await enablePush();
                setPushBusy(false);
                if (r.ok) setPushMsg({ ok: true, text: push === "acik" ? "Deneme bildirimi gönderildi; birkaç saniye içinde gelmeli." : "Bildirimler açıldı." });
                else setPushMsg({ ok: false, text: r.error ?? "Bildirimler açılamadı." });
                setPush(await pushStatus());
              }}
            />
          </ListGroup>
          {pushMsg && <Notice tone={pushMsg.ok ? "basari" : "hata"} text={pushMsg.text} />}
        </>
      )}

      <SectionLabel>GÜVENLİK</SectionLabel>
      <ListGroup>
        {biometric.available ? (
          <ListRow
            left={<Fingerprint size={22} color={colors.vurgu} strokeWidth={1.75} />}
            title="Parmak izi / yüz tanıma"
            subtitle="Uygulama açılırken kimliğiniz doğrulansın"
            right={<Switch value={biometric.enabled} onValueChange={biometric.setEnabled} trackColor={{ true: colors.vurgu, false: colors.cizgi }} accessibilityLabel="Parmak izi veya yüz tanıma" />}
          />
        ) : null}
        <ListRow left={<LogOut size={22} color={colors.yazi} strokeWidth={1.75} />} title="Çıkış Yap" onPress={signOut} chevron={false} />
        <ListRow left={<Trash2 size={22} color={colors.hata} strokeWidth={1.75} />} title={deleting ? "Siliniyor…" : "Hesabımı Sil"} tone="tehlike" onPress={deleting ? undefined : confirmDelete} chevron={false} />
      </ListGroup>
      {error && <Notice tone="hata" text={error} />}

      <Sheet visible={nameEdit !== null} onClose={() => setNameEdit(null)} title="Adım" subtitle="Profil">
        <Field label="Ad soyad" value={nameEdit ?? ""} onChangeText={setNameEdit} autoCapitalize="words" maxLength={100} />
        {nameError && <Notice tone="hata" text={nameError} />}
        <Button label="Kaydet" onPress={saveName} loading={nameBusy} />
      </Sheet>
    </Screen>
  );
}
