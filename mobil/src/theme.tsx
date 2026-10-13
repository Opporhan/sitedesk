import { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";
import AsyncStorage from "@react-native-async-storage/async-storage";

// İki tema: bej (varsayılan) ve koyu mavi. Saf beyaz ve saf siyah yok. Renkler web sürümüyle aynı (app/globals.css).
export type ThemeName = "bej" | "mavi";

const PALETTES = {
  bej: {
    zemin: "#f3ede2",
    kutu: "#faf6ef",
    kutuKoyu: "#eae2d4",
    yazi: "#3a322b",
    yaziSoluk: "#675c51",
    cizgi: "#ddd2c2",
    vurgu: "#0f6e66",
    vurguYazi: "#f7f2e9",
    vurguAcik: "#dcebe6",
    hata: "#b42318",
    hataZemin: "#f5ddd6",
    basari: "#1c7442",
    basariZemin: "#dceadb",
    bekliyor: "#9a5300",
    bekliyorZemin: "#f4e4c6",
    bilgi: "#1d5aa6",
    bilgiZemin: "#dce5f1",
  },
  mavi: {
    zemin: "#141f36",
    kutu: "#1b2843",
    kutuKoyu: "#24334f",
    yazi: "#e7e2d8",
    yaziSoluk: "#aeb5c3",
    cizgi: "#30405f",
    vurgu: "#56b8aa",
    vurguYazi: "#0f1a2c",
    vurguAcik: "#1f3d45",
    hata: "#f2948a",
    hataZemin: "#3a2533",
    basari: "#7ccb98",
    basariZemin: "#1e3a37",
    bekliyor: "#e9bb6a",
    bekliyorZemin: "#3a3326",
    bilgi: "#93bbf0",
    bilgiZemin: "#203556",
  },
} as const;

export type Colors = { [K in keyof (typeof PALETTES)["bej"]]: string };

// Yazı tipi: Inter (Türkçe harflerle). Ağırlık başına ayrı dosya.
export const FONT = { normal: "Inter_400Regular", orta: "Inter_500Medium", kalin: "Inter_600SemiBold", cokKalin: "Inter_700Bold" } as const;

// Ölçüler: kenar boşluğu ve gövde yazısı
export const SIZE = { kenar: 16, yazi: 17 } as const;

const STORAGE_KEY = "sitedesk-tema"; // web ile aynı ad

type ThemeContextValue = { name: ThemeName; colors: Colors; setTheme: (t: ThemeName) => void; ready: boolean };
const ThemeContext = createContext<ThemeContextValue | null>(null);

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const [name, setName] = useState<ThemeName>("bej");
  const [ready, setReady] = useState(false);

  // Seçilen tema telefonda hatırlanır; okunamazsa bej kalır
  useEffect(() => {
    AsyncStorage.getItem(STORAGE_KEY)
      .then((saved) => {
        if (saved === "bej" || saved === "mavi") setName(saved);
      })
      .catch(() => {})
      .finally(() => setReady(true));
  }, []);

  const setTheme = useCallback((t: ThemeName) => {
    setName(t);
    AsyncStorage.setItem(STORAGE_KEY, t).catch(() => {});
  }, []);

  const value = useMemo(() => ({ name, colors: PALETTES[name], setTheme, ready }), [name, setTheme, ready]);
  return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>;
}

export function useTheme() {
  const ctx = useContext(ThemeContext);
  if (!ctx) throw new Error("useTheme, ThemeProvider içinde kullanılmalı");
  return ctx;
}
