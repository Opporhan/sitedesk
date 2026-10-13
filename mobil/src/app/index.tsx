import { Redirect } from "expo-router";
import { ActivityIndicator, View } from "react-native";
import { useAuth } from "@/auth";
import { Button, Notice } from "@/components/ui";
import { useTheme } from "@/theme";

// Ana kapı: giriş yoksa giriş ekranı, sonra kişinin rolüne göre ekran (kilit bütün ekranların üstünde: components/lock-screen.tsx)
export default function Gate() {
  const { colors } = useTheme();
  const { ready, session, context, contextError, active, roleOptions, sitePicked, reloadContext, signOut } = useAuth();

  if (!ready) return <View style={{ flex: 1, backgroundColor: colors.zemin }} />;
  if (!session) return <Redirect href="/giris" />;
  if (!context) {
    return (
      <View style={{ flex: 1, backgroundColor: colors.zemin, justifyContent: "center", padding: 16, gap: 12 }}>
        {contextError ? (
          <>
            <Notice tone="hata" text={contextError} />
            <Button label="Tekrar Dene" onPress={reloadContext} />
            <Button label="Çıkış Yap" variant="ikincil" onPress={signOut} />
          </>
        ) : (
          <ActivityIndicator color={colors.vurgu} size="large" />
        )}
      </View>
    );
  }
  // Birden çok siteyi yöneten kişi uygulamayı açınca önce bütün sitelerini görür
  const managed = roleOptions.filter((r) => r.kind === "yonetici").length;
  if (active.kind === "yonetici" && managed > 1 && !context.platform_admin && !sitePicked) return <Redirect href="/siteler" />;
  if (active.kind === "yonetici") return <Redirect href="/yonetici" />;
  if (active.kind === "danisma") return <Redirect href="/danisma" />;
  if (active.kind === "sakin") return <Redirect href="/sakin" />;
  if (active.kind === "platform") return <Redirect href="/platform" />;
  return <Redirect href="/rol-yok" />;
}
