import { Alert, Linking, Platform } from "react-native";
import AsyncStorage from "@react-native-async-storage/async-storage";
import Constants from "expo-constants";
import * as Device from "expo-device";
import { Notifications } from "@/lib/notifications";
import { supabase } from "@/lib/supabase";

// Uygulama açıkken gelen bildirim de üstte görünsün
Notifications?.setNotificationHandler({
  handleNotification: async () => ({ shouldShowBanner: true, shouldShowList: true, shouldPlaySound: true, shouldSetBadge: false }),
});

const ASKED_KEY = "sitedesk-bildirim-soruldu";
let lastToken: string | null = null;

const projectId = () =>
  (Constants.expoConfig?.extra as { eas?: { projectId?: string } } | undefined)?.eas?.projectId ?? Constants.easConfig?.projectId ?? null;

export type PushResult = { ok: boolean; error?: string };

// Bildirim kimliğini al ve veritabanına kaydet (izin verilmişse)
async function saveToken(): Promise<PushResult> {
  try {
    const token = (await Notifications!.getExpoPushTokenAsync({ projectId: projectId()! })).data;
    const { error } = await supabase.rpc("register_push_token", { p_token: token, p_platform: Platform.OS === "ios" ? "ios" : "android" });
    if (error) return { ok: false, error: "Bildirim kaydı sunucuya yazılamadı. İnternetinizi kontrol edip tekrar deneyin." };
    lastToken = token;
    return { ok: true };
  } catch (e) {
    const msg = String((e as Error)?.message ?? e);
    return { ok: false, error: /network|fetch|timeout|SERVICE_NOT_AVAILABLE/i.test(msg) ? "İnternet bağlantısı yok gibi görünüyor; tekrar deneyin." : "Bildirim kimliği alınamadı. Telefonu yeniden başlatıp tekrar deneyin." };
  }
}

async function ensureChannel() {
  if (Platform.OS === "android") {
    await Notifications!.setNotificationChannelAsync("default", { name: "SiteDesk", importance: Notifications!.AndroidImportance.HIGH, sound: "default" }).catch(() => {});
  }
}

// Girişten sonra kendiliğinden: izin varsa kaydolur; yoksa nedenini Türkçe anlatıp bir kez sorar (sonra Profil › Bildirimler'den açılır)
export async function registerForPush(roleText: string): Promise<void> {
  try {
    if (!Notifications || !Device.isDevice || !projectId()) return; // Expo Go (Android), simülatör ya da proje henüz Expo hesabına bağlanmadı
    await ensureChannel();
    let { status, canAskAgain } = await Notifications.getPermissionsAsync();
    if (status !== "granted") {
      const asked = await AsyncStorage.getItem(ASKED_KEY).catch(() => null);
      if (asked || !canAskAgain) return;
      await AsyncStorage.setItem(ASKED_KEY, "1").catch(() => {});
      const go = await new Promise<boolean>((resolve) =>
        Alert.alert("Bildirimler", roleText, [
          { text: "Şimdi değil", style: "cancel", onPress: () => resolve(false) },
          { text: "İzin ver", onPress: () => resolve(true) },
        ])
      );
      if (!go) return;
      ({ status } = await Notifications.requestPermissionsAsync());
      if (status !== "granted") return;
    }
    await saveToken();
  } catch {
    // Bildirim alınamaması uygulamayı durdurmaz
  }
}

// Profil › Bildirimler: şu an açık mı?
export async function pushStatus(): Promise<"acik" | "kapali" | "desteklenmiyor"> {
  if (!Notifications || !Device.isDevice || !projectId()) return "desteklenmiyor";
  const { status } = await Notifications.getPermissionsAsync().catch(() => ({ status: "denied" as const }));
  if (status !== "granted") return "kapali";
  if (!lastToken) await saveToken(); // açılışta kayıt henüz bitmemiş olabilir
  return lastToken ? "acik" : "kapali";
}

// Profil › "Bildirimleri aç": izni ister (verilmemişse ayarlara yönlendirir) ve telefonu kaydeder; sonucu söyler
export async function enablePush(): Promise<PushResult> {
  if (!Notifications || !Device.isDevice || !projectId()) return { ok: false, error: "Bildirimler bu sürümde kullanılamıyor (Expo Go ya da emülatör)." };
  await ensureChannel();
  let { status, canAskAgain } = await Notifications.getPermissionsAsync();
  if (status !== "granted") {
    if (!canAskAgain) {
      Linking.openSettings().catch(() => {});
      return { ok: false, error: "Bildirim izni kapalı. Açılan ayarlarda SiteDesk için bildirimlere izin verin, sonra tekrar deneyin." };
    }
    ({ status } = await Notifications.requestPermissionsAsync());
    if (status !== "granted") return { ok: false, error: "Bildirim izni verilmedi." };
  }
  return saveToken();
}

// Kendi telefonuna deneme bildirimi (kayıt doğru mu?)
export async function sendTestPush(): Promise<PushResult> {
  if (!lastToken) return { ok: false, error: "Önce bildirimleri açın." };
  try {
    const res = await fetch("https://exp.host/--/api/v2/push/send", {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({ to: lastToken, title: "SiteDesk", body: "Deneme bildirimi: bildirimler çalışıyor.", sound: "default", channelId: "default", priority: "high" }),
    });
    const out = (await res.json().catch(() => ({}))) as { data?: { status?: string; message?: string } };
    return out.data?.status === "ok" ? { ok: true } : { ok: false, error: `Gönderilemedi: ${out.data?.message ?? res.status}` };
  } catch {
    return { ok: false, error: "İnternet bağlantısı yok gibi görünüyor." };
  }
}

// Çıkışta bu telefon artık bu hesabın bildirimlerini almasın
// (kilit ekranından çıkışta kayıt henüz yapılmamış olabilir: izin varsa telefonun kimliği yeniden alınır)
export async function unregisterPush(): Promise<void> {
  let token = lastToken;
  if (!token && Notifications && Device.isDevice && projectId()) {
    const { status } = await Notifications.getPermissionsAsync().catch(() => ({ status: "denied" as const }));
    if (status === "granted") token = (await Notifications.getExpoPushTokenAsync({ projectId: projectId()! }).catch(() => null))?.data ?? null;
  }
  if (!token) return;
  await supabase.from("push_tokens").delete().eq("token", token);
  lastToken = null;
}
