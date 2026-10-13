import { useFonts } from "expo-font";
import { router, Stack } from "expo-router";
import { Notifications } from "@/lib/notifications";
import { useEffect, useRef, useState } from "react";
import { StatusBar } from "expo-status-bar";
import { View } from "react-native";
import { Inter_400Regular } from "@expo-google-fonts/inter/400Regular";
import { Inter_500Medium } from "@expo-google-fonts/inter/500Medium";
import { Inter_600SemiBold } from "@expo-google-fonts/inter/600SemiBold";
import { Inter_700Bold } from "@expo-google-fonts/inter/700Bold";
import { ThemeProvider, useTheme } from "@/theme";
import { AuthProvider, useAuth } from "@/auth";
import { LockScreen } from "@/components/lock-screen";
import { OutboxProvider } from "@/outbox";

// Bildirime dokununca ilgili ekran açılır (kayıt ya da kargo); uygulama kapalıyken dokunulduysa da.
// Giriş yapılmamışsa açılmaz; kilitliyse ekran kilidin arkasında açılır, içerik kilit açılınca görünür.
function useNotificationTaps() {
  const { ready, session } = useAuth();
  const [last, setLast] = useState<{ id: string; url: unknown } | null>(null);
  const handled = useRef<string | null>(null);
  useEffect(() => {
    if (!Notifications) return;
    const take = (r: { notification: { request: { identifier: string; content: { data?: Record<string, unknown> } } } } | null) =>
      r && setLast({ id: r.notification.request.identifier, url: r.notification.request.content.data?.url });
    Notifications.getLastNotificationResponseAsync().then(take).catch(() => {});
    const sub = Notifications.addNotificationResponseReceivedListener(take);
    return () => sub.remove();
  }, []);
  useEffect(() => {
    if (!ready || !session || !last || handled.current === last.id) return;
    handled.current = last.id;
    Notifications?.clearLastNotificationResponseAsync?.().catch(() => {}); // uygulama yeniden açılınca aynı bildirim tekrar açılmasın
    if (typeof last.url === "string" && last.url.startsWith("/")) router.push(last.url as never);
  }, [last, ready, session]);
}

function Root() {
  useNotificationTaps();
  const { session, locked } = useAuth();
  const { name, colors, ready } = useTheme();
  const [fontsLoaded, fontError] = useFonts({ Inter_400Regular, Inter_500Medium, Inter_600SemiBold, Inter_700Bold });
  // Yazı tipi ve tema hazır olana kadar sadece zemin rengi (renk sıçraması olmasın)
  if (!ready || !(fontsLoaded || fontError)) return <View style={{ flex: 1, backgroundColor: colors.zemin }} />;

  return (
    <>
      <StatusBar style={name === "mavi" ? "light" : "dark"} />
      <Stack screenOptions={{ headerShown: false, contentStyle: { backgroundColor: colors.zemin } }} />
      {session && locked && <LockScreen />}
    </>
  );
}

export default function RootLayout() {
  return (
    <ThemeProvider>
      <AuthProvider>
        <OutboxProvider>
          <Root />
        </OutboxProvider>
      </AuthProvider>
    </ThemeProvider>
  );
}
