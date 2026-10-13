import * as Clipboard from "expo-clipboard";
import { router } from "expo-router";
import { useCallback, useEffect, useState } from "react";
import { KeyboardAvoidingView, Platform, View } from "react-native";
import { ClipboardPaste } from "lucide-react-native";
import { useAuth } from "@/auth";
import { callServer, NETWORK_ERROR, supabase } from "@/lib/supabase";
import { normalizePhone } from "@/lib/phone";
import { Body, Button, Card, Field, Muted, Notice, Screen } from "@/components/ui";
import { FONT } from "@/theme";

type Preview = {
  valid: boolean;
  status: "gecerli" | "kullanildi" | "iptal" | "suresi-doldu";
  code: string;
  role: "sakin" | "danisma" | "yonetici" | "sifre";
  full_name: string;
  phone_last4: string;
  site_name: string;
  unit_label: string | null;
  has_account: boolean;
};

const ROLE_TEXT = { sakin: "Sakin", danisma: "Danışma görevlisi", yonetici: "Yönetici", sifre: "Şifre yenileme" } as const;
const STATUS_TEXT = {
  kullanildi: "Bu kod daha önce kullanılmış. Hesabınız varsa telefon numaranız ve şifrenizle giriş yapın.",
  iptal: "Bu kod iptal edilmiş ya da yerine yenisi gönderilmiş. Yönetiminizden yeni kod isteyin.",
  "suresi-doldu": "Bu kodun süresi dolmuş. Yönetiminizden yeni kod isteyin.",
} as const;
// Panodaki metinden davet kodunu ya da bağlantı anahtarını bulur
const findKey = (text: string) => text.match(/davet\/([a-f0-9]{48})/)?.[1] ?? text.toUpperCase().match(/\b[A-HJ-NP-Z2-9]{8}\b/)?.[0] ?? null;

// Daveti kabul: kodu/bağlantıyı doğrula → telefon + şifre → hesap açılır (ya da var olan hesaba eklenir) → giriş.
// Şifre yenileme kodu da buradan: telefon + yeni şifre → sunucu şifreyi yazar → giriş.
export function InviteAccept({ initialKey }: { initialKey?: string }) {
  const { session, signIn, signOut, reloadContext } = useAuth();
  const [key, setKey] = useState(initialKey ?? "");
  const [preview, setPreview] = useState<Preview | null>(null);
  const [phone, setPhone] = useState("");
  const [password, setPassword] = useState("");
  const [password2, setPassword2] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const lookup = useCallback(async (value: string) => {
    const k = value.trim();
    if (!k) return;
    setBusy(true);
    setError(null);
    const { data, error: e } = await supabase.rpc("invite_preview", { p_key: k });
    setBusy(false);
    if (e) return setError(e.message.includes("fetch") ? NETWORK_ERROR : "Davet kontrol edilemedi. Lütfen tekrar deneyin.");
    if (!data) return setError("Bu kod bulunamadı. Kodu kontrol edin.");
    setPreview(data as Preview);
  }, []);

  useEffect(() => {
    if (initialKey) lookup(initialKey);
  }, [initialKey, lookup]);

  async function paste() {
    const text = await Clipboard.getStringAsync().catch(() => "");
    const found = text ? findKey(text) : null;
    if (!found) return setError("Panoda davet kodu bulunamadı. Kodu elle yazın.");
    setKey(found);
    lookup(found);
  }

  async function accept() {
    if (!preview) return;
    setError(null);
    const p = normalizePhone(phone);
    if (!p || !p.endsWith(preview.phone_last4)) return setError(`Davet edilen telefon numarasını yazın (…${preview.phone_last4} ile biten).`);
    if (password.length < 8) return setError("Şifre en az 8 karakter olmalı.");
    const reset = preview.role === "sifre";
    if ((reset || !preview.has_account) && password !== password2) return setError("Şifreler aynı değil.");
    setBusy(true);
    try {
      if (reset) {
        if (session) await signOut();
        const done = await callServer("/api/sifre", { key: key.trim(), phone: p, password });
        if (!done.ok) return setError(done.error ?? "Şifre yenilenemedi.");
        const loginError = await signIn(p, password);
        if (loginError) return setError(loginError);
        router.replace("/");
        return;
      }
      // Başka bir hesapla açık oturum varsa önce kapatılır (davet bu telefona ait)
      if (session) await signOut();
      let created: { ok: boolean; status?: number; error?: string } | null = null;
      if (!preview.has_account) {
        created = await callServer("/api/davet", { key: key.trim(), phone: p, password });
        // 409: hesap zaten açılmış (ör. önceki deneme yarıda kaldı) → aynı şifreyle girmeyi dene
        if (!created.ok && created.status !== 409) return setError(created.error ?? "Hesap açılamadı.");
      }
      const loginError = await signIn(p, password);
      if (loginError) return setError(preview.has_account || created?.status === 409 ? `${loginError} Mevcut şifrenizi yazın.` : loginError);
      const { error: e } = await supabase.rpc("accept_invite", { p_key: key.trim() });
      if (e) return setError(e.message.includes("fetch") ? NETWORK_ERROR : "Davet hesabınıza eklenemedi. Lütfen tekrar deneyin.");
      await reloadContext();
      router.replace("/");
    } finally {
      setBusy(false);
    }
  }

  return (
    <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === "ios" ? "padding" : undefined}>
      <Screen title={preview?.role === "sifre" ? "Şifre yenileme" : "Davet"}>
        {!preview ? (
          <>
            <Muted>WhatsApp&apos;tan gelen mesajdaki 8 haneli davet ya da şifre yenileme kodunu yazın.</Muted>
            <Field label="Kod" value={key} onChangeText={(t) => setKey(/^[a-f0-9]{9,}$/i.test(t.trim()) ? t.toLowerCase() : t.toUpperCase())} autoCapitalize="characters" autoCorrect={false} maxLength={60} placeholder="ÖRN. K7M3PQ2X" onSubmitEditing={() => lookup(key)} />
            {error && <Notice tone="hata" text={error} />}
            <Button label="Devam" onPress={() => lookup(key)} loading={busy} />
            <Button label="Panodan Yapıştır" variant="ikincil" icon={ClipboardPaste} onPress={paste} />
            <Button label="Geri" variant="ikincil" onPress={() => (router.canGoBack() ? router.back() : router.replace("/giris"))} />
          </>
        ) : !preview.valid ? (
          <>
            <Notice tone="bekliyor" text={STATUS_TEXT[preview.status as keyof typeof STATUS_TEXT] ?? "Bu davet geçersiz."} />
            <Button label="Giriş Ekranına Dön" variant="ikincil" onPress={() => router.replace("/giris")} />
          </>
        ) : (
          <>
            <Card>
              <Body style={{ fontFamily: FONT.kalin }}>Merhaba {preview.full_name}</Body>
              <Muted>
                {preview.site_name} · {ROLE_TEXT[preview.role]}
                {preview.unit_label ? ` · ${preview.unit_label}` : ""}
              </Muted>
            </Card>
            {preview.role === "sifre" ? (
              preview.has_account ? (
                <Muted>Telefon numaranızı yazın ve yeni şifrenizi belirleyin.</Muted>
              ) : (
                <Notice tone="bekliyor" text="Bu numarayla hesap bulunamadı. Yönetiminizden davet isteyin." />
              )
            ) : preview.has_account ? (
              <Notice tone="bilgi" text="Bu telefon numarasıyla hesabınız var. Şifrenizle devam edin; davet hesabınıza eklenir. Şifrenizi unuttuysanız yönetiminizden şifre yenileme kodu isteyin." />
            ) : (
              <Muted>Telefon numaranızı yazın ve bir şifre belirleyin. Sonraki girişlerde bu numara ve şifreyi kullanacaksınız.</Muted>
            )}
            {(preview.role !== "sifre" || preview.has_account) && (
              <>
                <Field label="Telefon numaranız" value={phone} onChangeText={setPhone} keyboardType="phone-pad" autoComplete="tel" placeholder={`…${preview.phone_last4} ile biten numara`} />
                {(() => {
                  const fresh = preview.role === "sifre" || !preview.has_account;
                  return (
                    <>
                      <Field label={fresh ? "Yeni şifre (en az 8 karakter)" : "Şifreniz"} value={password} onChangeText={setPassword} secureTextEntry textContentType={fresh ? "newPassword" : "password"} />
                      {fresh && <Field label="Yeni şifre (tekrar)" value={password2} onChangeText={setPassword2} secureTextEntry textContentType="newPassword" />}
                    </>
                  );
                })()}
                {error && <Notice tone="hata" text={error} />}
                <View style={{ gap: 12 }}>
                  <Button label={preview.role === "sifre" ? "Şifremi Yenile ve Gir" : preview.has_account ? "Giriş Yap ve Katıl" : "Hesabımı Oluştur"} onPress={accept} loading={busy} />
                </View>
              </>
            )}
          </>
        )}
      </Screen>
    </KeyboardAvoidingView>
  );
}
