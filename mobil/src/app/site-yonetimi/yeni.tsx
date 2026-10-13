import { Redirect, router } from "expo-router";
import { useState } from "react";
import { KeyboardAvoidingView, Platform, View } from "react-native";
import { useAuth } from "@/auth";
import { NETWORK_ERROR, supabase } from "@/lib/supabase";
import { BackHeader, Button, Choice, Field, Muted, Notice, Screen } from "@/components/ui";

const TYPES = [
  { value: "apartman", label: "Apartman" },
  { value: "villa", label: "Villa" },
  { value: "karisik", label: "Karışık" },
] as const;

// Yeni site (ad, tür, adres). Kayıtlı her kullanıcı açabilir (create_site);
// yönetici açarsa o sitenin yöneticisi olur, site açılır ve doğrudan bloklar/daireler ekranına geçer.
export default function NewSite() {
  const { context, reloadContext, setActive, session } = useAuth();
  const [name, setName] = useState("");
  const [type, setType] = useState<(typeof TYPES)[number]["value"]>("apartman");
  const [address, setAddress] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const isAdmin = !!context?.platform_admin;
  if (!session) return <Redirect href="/giris" />;

  async function save() {
    if (name.trim().length < 2) return setError("Site adını yazın.");
    setBusy(true);
    setError(null);
    const { data, error: e } = await supabase.rpc("create_site", { p_name: name.trim(), p_type: type, p_address: address.trim() || null });
    setBusy(false);
    if (e || !data) return setError(e?.message.includes("fetch") ? NETWORK_ERROR : e?.code === "SD050" ? "Bugün çok fazla site açtınız. Yarın tekrar deneyin." : "Site açılamadı.");
    await reloadContext();
    if (isAdmin) return router.replace({ pathname: "/site-yonetimi/[id]", params: { id: data as string } });
    // Yönetici: yeni sitesine geçer, bloklar ve dairelerle başlar
    setActive({ kind: "yonetici", siteId: data as string, siteName: name.trim(), siteType: type });
    router.replace("/yonetici/kisiler");
  }

  return (
    <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === "ios" ? "padding" : undefined}>
      <Screen title="Yeni site" header={<BackHeader />}>
        <Field label="Site adı" value={name} onChangeText={setName} maxLength={80} />
        <Muted>Site türü</Muted>
        <View accessibilityRole="radiogroup" style={{ flexDirection: "row", gap: 8 }}>
          {TYPES.map((t) => (
            <Choice key={t.value} label={t.label} selected={type === t.value} onPress={() => setType(t.value)} />
          ))}
        </View>
        <Field label="Adres (isteğe bağlı)" value={address} onChangeText={setAddress} maxLength={200} />
        {!isAdmin && <Muted>Siteyi açınca o sitenin yöneticisi siz olursunuz. Sonra Kişiler › Daireler bölümünden blok ve daireleri ekleyin.</Muted>}
        {error && <Notice tone="hata" text={error} />}
        <Button label="Siteyi Aç" onPress={save} loading={busy} />
      </Screen>
    </KeyboardAvoidingView>
  );
}
