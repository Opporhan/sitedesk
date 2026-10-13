import { router, useLocalSearchParams } from "expo-router";
import { useState } from "react";
import { KeyboardAvoidingView, Platform } from "react-native";
import { useAuth } from "@/auth";
import { callServer } from "@/lib/supabase";
import { normalizePhone } from "@/lib/phone";
import { BackHeader, Button, Field, Muted, Notice, Screen } from "@/components/ui";

// Davetsiz kayıt (uygulama ücretsiz): ad, cep telefonu, şifre → hesap açılır → amaca göre site koduyla katılma ya da kendi sitesini açma
export default function SignUp() {
  const { amac } = useLocalSearchParams<{ amac?: string }>();
  const { signIn } = useAuth();
  const toSite = amac === "site";
  const [name, setName] = useState("");
  const [phone, setPhone] = useState("");
  const [password, setPassword] = useState("");
  const [password2, setPassword2] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const next = () => router.replace(toSite ? "/site-yonetimi/yeni" : "/katil");

  async function submit() {
    setError(null);
    const p = normalizePhone(phone);
    if (name.trim().length < 3) return setError("Adınızı ve soyadınızı yazın.");
    if (!p || !p.startsWith("905")) return setError("Cep telefonu numaranızı 0532 123 45 67 gibi yazın.");
    if (password.length < 8) return setError("Şifre en az 8 karakter olmalı.");
    if (password !== password2) return setError("Şifreler aynı değil.");
    setBusy(true);
    try {
      const r = await callServer("/api/kayit", { fullName: name.trim(), phone: p, password });
      // Hesap zaten varsa (ör. önceki deneme yarıda kaldı) aynı şifreyle girmeyi dene
      if (!r.ok && r.status !== 409) return setError(r.error ?? "Hesap açılamadı.");
      const loginError = await signIn(p, password);
      if (loginError) return setError(r.ok ? loginError : (r.error ?? loginError));
      next();
    } finally {
      setBusy(false);
    }
  }

  return (
    <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === "ios" ? "padding" : undefined}>
      <Screen title={toSite ? "Sitemi Ekle" : "Siteme Katıl"} subtitle="Önce hesabınızı açın" header={<BackHeader />}>
        <Muted>
          {toSite
            ? "Sitenizin yöneticisiyseniz hesabınızı açın, sonra sitenizi ve dairelerini ekleyin. Sakinleri site koduyla ya da davetle çağırırsınız."
            : "Hesabınızı açın, sonra yönetiminizin paylaştığı site kodunu yazıp dairenizi seçin. Yönetim onaylayınca girersiniz."}
        </Muted>
        <Field label="Ad soyad" value={name} onChangeText={setName} autoCapitalize="words" maxLength={100} />
        <Field label="Cep telefonu" value={phone} onChangeText={setPhone} keyboardType="phone-pad" autoComplete="tel" placeholder="0532 123 45 67" />
        <Field label="Şifre (en az 8 karakter)" value={password} onChangeText={setPassword} secureTextEntry textContentType="newPassword" />
        <Field label="Şifre (tekrar)" value={password2} onChangeText={setPassword2} secureTextEntry textContentType="newPassword" />
        {error && <Notice tone="hata" text={error} />}
        <Button label="Hesabımı Aç ve Devam Et" onPress={submit} loading={busy} />
        <Muted style={{ textAlign: "center" }}>Bundan sonra bu telefon numarası ve şifreyle girersiniz.</Muted>
        <Button label="Hesabım Var, Giriş Yap" variant="metin" onPress={() => router.replace("/giris")} />
      </Screen>
    </KeyboardAvoidingView>
  );
}
