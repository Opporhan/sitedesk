import { useFocusEffect } from "expo-router";
import { useCallback } from "react";
import { AppState } from "react-native";

// Ekran açıkken listeyi güncel tutar: ekrana gelince, uygulama öne gelince ve ekran açık durdukça 30 saniyede bir yeniler
export function useAutoRefresh(load: () => void, everyMs = 30_000) {
  useFocusEffect(
    useCallback(() => {
      load();
      const timer = setInterval(load, everyMs);
      const sub = AppState.addEventListener("change", (s) => s === "active" && load());
      return () => {
        clearInterval(timer);
        sub.remove();
      };
    }, [load, everyMs])
  );
}
