import { useEffect, useState } from "react";
import { Image, Text, View } from "react-native";
import { supabase } from "@/lib/supabase";
import { FONT, useTheme } from "@/theme";

// Süreli bağlantılar kısa süre hafızada tutulur (her ekranda yeniden istenmesin)
const cache = new Map<string, { url: string; until: number }>();
export function forgetAvatar(path: string | null | undefined) {
  if (path) cache.delete(path);
}

async function signedUrl(path: string): Promise<string | null> {
  const hit = cache.get(path);
  if (hit && hit.until > Date.now()) return hit.url;
  const { data } = await supabase.storage.from("profil").createSignedUrl(path, 3600);
  if (!data?.signedUrl) return null;
  cache.set(path, { url: data.signedUrl, until: Date.now() + 50 * 60 * 1000 });
  return data.signedUrl;
}

export function initialsOf(name: string | null | undefined) {
  return (name ?? "")
    .split(" ")
    .filter(Boolean)
    .slice(0, 2)
    .map((p) => p[0]?.toLocaleUpperCase("tr-TR"))
    .join("");
}

// Yuvarlak profil resmi; resim yoksa baş harfler
export function Avatar({ path, name, size = 44, localUri }: { path?: string | null; name?: string | null; size?: number; localUri?: string | null }) {
  const { colors } = useTheme();
  const [url, setUrl] = useState<string | null>(null);
  useEffect(() => {
    let alive = true;
    setUrl(null);
    if (path && !localUri) signedUrl(path).then((u) => alive && setUrl(u));
    return () => {
      alive = false;
    };
  }, [path, localUri]);
  const src = localUri ?? url;
  return (
    <View style={{ width: size, height: size, borderRadius: size / 2, overflow: "hidden", backgroundColor: colors.vurguAcik, alignItems: "center", justifyContent: "center" }}>
      {src ? (
        <Image source={{ uri: src }} style={{ width: size, height: size }} resizeMode="cover" accessibilityLabel={`${name ?? ""} profil resmi`} />
      ) : (
        <Text style={{ fontFamily: FONT.kalin, fontSize: size * 0.38, color: colors.vurgu }}>{initialsOf(name) || "?"}</Text>
      )}
    </View>
  );
}
