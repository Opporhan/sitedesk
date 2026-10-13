import { useEffect, useState } from "react";
import { View } from "react-native";
import { Fingerprint } from "lucide-react-native";
import { useAuth } from "@/auth";
import { Body, Button, Muted, Screen } from "@/components/ui";
import { FONT, useTheme } from "@/theme";

// Kilit: uygulama açılırken ve 5 dakikadan uzun arka planda kaldıktan sonra parmak izi / yüz tanıma istenir.
// Bütün ekranların ÜSTÜNDE durur (bildirimden açılan ekran da dahil); kilit açılınca kişi kaldığı ekrana döner.
export function LockScreen() {
  const { colors } = useTheme();
  const { unlock, signOut } = useAuth();
  const [busy, setBusy] = useState(false);

  async function tryUnlock() {
    setBusy(true);
    await unlock();
    setBusy(false);
  }
  useEffect(() => {
    tryUnlock();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <View style={{ position: "absolute", top: 0, left: 0, right: 0, bottom: 0, backgroundColor: colors.zemin, zIndex: 100 }}>
      <Screen title="SiteDesk">
        <View style={{ alignItems: "center", gap: 12, paddingVertical: 24 }}>
          <Fingerprint size={56} color={colors.vurgu} />
          <Body style={{ fontFamily: FONT.kalin, textAlign: "center" }}>Devam etmek için kimliğinizi doğrulayın</Body>
          <Muted style={{ textAlign: "center" }}>Parmak izi, yüz tanıma ya da telefonunuzun şifresi.</Muted>
        </View>
        <Button label="Kilidi Aç" onPress={tryUnlock} loading={busy} />
        <Button label="Şifreyle Gir" variant="ikincil" onPress={signOut} />
      </Screen>
    </View>
  );
}
