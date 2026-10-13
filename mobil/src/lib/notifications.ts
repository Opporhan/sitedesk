import Constants, { ExecutionEnvironment } from "expo-constants";
import { Platform } from "react-native";

// Telefon bildirimi modülü. Expo Go, Android'de bildirimi desteklemiyor (SDK 53+) ve modül yüklenince hata ekranı çıkarıyor;
// orada modül hiç yüklenmez (null). Gerçek uygulamada (mağaza / deneme sürümü) normal çalışır.
type NotificationsModule = typeof import("expo-notifications");
const inExpoGoAndroid = Platform.OS === "android" && Constants.executionEnvironment === ExecutionEnvironment.StoreClient;

// eslint-disable-next-line @typescript-eslint/no-require-imports
export const Notifications: NotificationsModule | null = inExpoGoAndroid ? null : (require("expo-notifications") as NotificationsModule);
