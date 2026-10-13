import { Redirect, router } from "expo-router";
import { useState } from "react";
import { KeyboardAvoidingView, Platform, ScrollView, Text, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { Building2 } from "lucide-react-native";
import { useAuth } from "@/auth";
import { Button, Field, Muted, Notice, ThemeToggle } from "@/components/ui";
import { FONT, SIZE, useTheme } from "@/theme";

// Giriş: telefon numarası + şifre (sistem yöneticisi e-postayla da girebilir)
export default function LoginScreen() {
  const { colors } = useTheme();
  const insets = useSafeAreaInsets();
  const { session, signIn } = useAuth();
  const [login, setLogin] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  if (session) return <Redirect href="/" />;

  async function submit() {
    setBusy(true);
    setError(null);
    const err = await signIn(login, password);
    setBusy(false);
    if (err) setError(err);
    else router.replace("/");
  }

  return (
    <KeyboardAvoidingView style={{ flex: 1, backgroundColor: colors.zemin }} behavior={Platform.OS === "ios" ? "padding" : undefined}>
      <ScrollView contentContainerStyle={{ flexGrow: 1, paddingTop: insets.top + 8, paddingBottom: insets.bottom + 24, paddingHorizontal: SIZE.kenar, gap: 20 }} keyboardShouldPersistTaps="handled">
        <View style={{ alignItems: "flex-end" }}>
          <ThemeToggle />
        </View>

        <View style={{ alignItems: "center", gap: 14, paddingTop: 24, paddingBottom: 12 }}>
          <View style={{ width: 72, height: 72, borderRadius: 22, backgroundColor: colors.vurgu, alignItems: "center", justifyContent: "center" }}>
            <Building2 size={36} color={colors.vurguYazi} strokeWidth={1.75} />
          </View>
          <Text style={{ fontFamily: FONT.cokKalin, fontSize: 30, letterSpacing: -0.5, color: colors.yazi }}>SiteDesk</Text>
          <Muted style={{ textAlign: "center" }}>Arıza, talep, kargo ve ziyaretçi; tek uygulamada.</Muted>
        </View>

        <Field label="Telefon numarası" value={login} onChangeText={setLogin} placeholder="0532 123 45 67" keyboardType="phone-pad" autoComplete="tel" textContentType="telephoneNumber" autoCapitalize="none" />
        <Field label="Şifre" value={password} onChangeText={setPassword} secureTextEntry autoComplete="password" textContentType="password" onSubmitEditing={submit} />
        {error && <Notice tone="hata" text={error} />}
        <Button label="Giriş Yap" onPress={submit} loading={busy} />

        <View style={{ flex: 1 }} />
        <View style={{ alignItems: "center", gap: 4 }}>
          <Muted style={{ textAlign: "center" }}>İlk kez mi giriyorsunuz?</Muted>
          <Button label="Siteme Katıl (Sakin)" variant="ikincil" onPress={() => router.push({ pathname: "/kaydol", params: { amac: "katil" } })} />
          <Muted style={{ textAlign: "center", fontSize: 14, marginBottom: 8 }}>Yöneticinizin paylaştığı site koduyla; yönetici onaylayınca girersiniz.</Muted>
          <Button label="Sitemi Ekle (Yönetici)" variant="ikincil" onPress={() => router.push({ pathname: "/kaydol", params: { amac: "site" } })} />
          <Muted style={{ textAlign: "center", fontSize: 14, marginBottom: 8 }}>Siteniz uygulamada yoksa kendiniz kurun.</Muted>
          <Button label="Davet veya Şifre Kodum Var" variant="metin" onPress={() => router.push("/davet")} />
          <Muted style={{ textAlign: "center", fontSize: 14, marginBottom: 8 }}>Size gönderilen davet ile onay beklemeden hemen girersiniz.</Muted>
          <Muted style={{ textAlign: "center", fontSize: 14 }}>Şifrenizi unuttuysanız yönetiminizden şifre yenileme kodu isteyin.</Muted>
        </View>
      </ScrollView>
    </KeyboardAvoidingView>
  );
}
