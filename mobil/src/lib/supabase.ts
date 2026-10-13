import { createClient } from "@supabase/supabase-js";
import * as SecureStore from "expo-secure-store";
import { AppState } from "react-native";

// Uygulamada sadece herkese açık olabilecek anahtarlar bulunur (adres + "publishable" anahtar). Gizli anahtar sunucuda kalır.
const url = process.env.EXPO_PUBLIC_SUPABASE_URL!;
const key = process.env.EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY!;

// Oturum telefonda şifreli saklanır (iPhone: Keychain, Android: Keystore). Bazı iPhone sürümleri ~2 KB üstü değeri reddettiği için
// değer parçalara bölünür.
const CHUNK = 1800;
const chunkKey = (k: string, i: number) => `${k.replace(/[^A-Za-z0-9._-]/g, "_")}.${i}`;

const secureStorage = {
  async getItem(k: string): Promise<string | null> {
    const count = await SecureStore.getItemAsync(chunkKey(k, 0));
    if (count === null) return null;
    const parts: string[] = [];
    for (let i = 1; i <= Number(count); i++) {
      const part = await SecureStore.getItemAsync(chunkKey(k, i));
      if (part === null) return null;
      parts.push(part);
    }
    return parts.join("");
  },
  async setItem(k: string, value: string): Promise<void> {
    await this.removeItem(k);
    const parts = value.match(new RegExp(`[\\s\\S]{1,${CHUNK}}`, "g")) ?? [""];
    for (let i = 0; i < parts.length; i++) await SecureStore.setItemAsync(chunkKey(k, i + 1), parts[i]);
    await SecureStore.setItemAsync(chunkKey(k, 0), String(parts.length));
  },
  async removeItem(k: string): Promise<void> {
    const count = await SecureStore.getItemAsync(chunkKey(k, 0));
    for (let i = 1; i <= Number(count ?? 0); i++) await SecureStore.deleteItemAsync(chunkKey(k, i));
    await SecureStore.deleteItemAsync(chunkKey(k, 0));
  },
};

export const supabase = createClient(url, key, {
  auth: { storage: secureStorage, autoRefreshToken: true, persistSession: true, detectSessionInUrl: false },
});

// Uygulama öndeyken oturum kendiliğinden yenilenir (uzun süre açık kalsın)
AppState.addEventListener("change", (state) => {
  if (state === "active") supabase.auth.startAutoRefresh();
  else supabase.auth.stopAutoRefresh();
});

export const WEB_URL = process.env.EXPO_PUBLIC_WEB_URL ?? "https://sitedesk-sooty.vercel.app";

// Sunucudaki işlemler (davetle hesap açma, hesap silme): gizli anahtar gerektiren işler orada yapılır
export async function callServer(path: string, body: unknown, accessToken?: string): Promise<{ ok: boolean; status?: number; error?: string }> {
  try {
    const res = await fetch(`${WEB_URL}${path}`, {
      method: "POST",
      headers: { "Content-Type": "application/json", ...(accessToken ? { Authorization: `Bearer ${accessToken}` } : {}) },
      body: JSON.stringify(body),
    });
    const data = (await res.json().catch(() => ({}))) as { error?: string };
    return res.ok ? { ok: true, status: res.status } : { ok: false, status: res.status, error: data.error ?? "Bir sorun oluştu. Lütfen tekrar deneyin." };
  } catch {
    return { ok: false, error: NETWORK_ERROR };
  }
}

export const NETWORK_ERROR = "İnternet bağlantısı yok gibi görünüyor. Bağlantınızı kontrol edip tekrar deneyin.";
