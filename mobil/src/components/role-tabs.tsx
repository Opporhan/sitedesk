import { Redirect, Tabs } from "expo-router";
import { View } from "react-native";
import type { LucideIcon } from "lucide-react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { useAuth, type ActiveRole } from "@/auth";
import { FONT, useTheme } from "@/theme";

// Rol ekranlarının ortak alt menüsü. Giriş yoksa ya da açık rol bu değilse ana kapıya döner.
export function RoleTabs({ kind, tabs }: { kind: ActiveRole["kind"]; tabs: { name: string; title: string; icon: LucideIcon }[] }) {
  const { colors } = useTheme();
  const insets = useSafeAreaInsets();
  const { session, active } = useAuth();
  // Kilit burada kontrol edilmez: kilit ekranı her şeyin üstünde durur (app/_layout.tsx). Burada da yönlendirirsek ana kapıyla sonsuz döngü olur.
  if (!session || active.kind !== kind) return <Redirect href="/" />;

  return (
    <Tabs
      screenOptions={{
        headerShown: false,
        tabBarActiveTintColor: colors.vurgu,
        tabBarInactiveTintColor: colors.yaziSoluk,
        // Üst köşeleri yuvarlak, hafif gölgeli menü; seçili sekmenin simgesi yuvarlak renkli bir şeklin içinde
        tabBarStyle: {
          backgroundColor: colors.kutu,
          borderTopWidth: 0,
          borderTopLeftRadius: 24,
          borderTopRightRadius: 24,
          height: 72 + insets.bottom,
          paddingTop: 10,
          paddingBottom: insets.bottom + 8,
          position: "absolute",
          shadowColor: "#2b1f14",
          shadowOpacity: 0.08,
          shadowRadius: 16,
          shadowOffset: { width: 0, height: -4 },
          elevation: 12,
        },
        tabBarLabelStyle: { fontFamily: FONT.kalin, fontSize: 12, marginTop: 4 },
        sceneStyle: { backgroundColor: colors.zemin, paddingBottom: 72 + insets.bottom },
      }}
    >
      {tabs.map((t) => (
        <Tabs.Screen key={t.name} name={t.name} options={{ title: t.title, tabBarIcon: ({ color, focused }) => (
              <View style={{ width: 60, height: 32, borderRadius: 16, alignItems: "center", justifyContent: "center", backgroundColor: focused ? colors.vurguAcik : "transparent" }}>
                <t.icon size={22} color={color} strokeWidth={focused ? 2.25 : 1.75} />
              </View>
            ) }} />
      ))}
    </Tabs>
  );
}
