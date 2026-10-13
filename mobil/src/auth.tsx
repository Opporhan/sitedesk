import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from "react";
import { AppState } from "react-native";
import AsyncStorage from "@react-native-async-storage/async-storage";
import * as LocalAuthentication from "expo-local-authentication";
import type { Session } from "@supabase/supabase-js";
import { NETWORK_ERROR, supabase } from "@/lib/supabase";
import { loginIdentifier } from "@/lib/phone";
import { registerForPush, unregisterPush } from "@/lib/push";

// Giriş yapan kişinin rolleri (veritabanı: my_context)
export type StaffRole = { role: "yonetici" | "danisma"; site_id: string; site_name: string; site_type: string };
export type ResidentUnit = { unit_id: string; site_id: string; site_name: string; site_type: string; label: string; type: "daire" | "villa"; relation: string };
export type UserContext = { platform_admin: boolean; full_name: string | null; staff: StaffRole[]; units: ResidentUnit[]; closed_sites: string[]; pending_joins: { site_name: string; label: string }[] };

// Uygulamada açık olan rol: kişi birden çok rol taşıyabilir (ör. bir sitede yönetici, başka sitede sakin)
export type ActiveRole = { kind: "yonetici" | "danisma"; siteId: string; siteName: string; siteType: string } | { kind: "sakin" } | { kind: "platform" } | { kind: "yok" };

type AuthValue = {
  ready: boolean;
  session: Session | null;
  context: UserContext | null;
  contextError: string | null;
  locked: boolean;
  active: ActiveRole;
  roleOptions: ActiveRole[];
  setActive: (r: ActiveRole) => void;
  sitePicked: boolean; // bu açılışta site seçildi mi (birden çok siteyi yöneten önce "Sitelerim"i görür)
  signIn: (login: string, password: string) => Promise<string | null>;
  signOut: () => Promise<void>;
  reloadContext: () => Promise<void>;
  unlock: () => Promise<boolean>;
  biometric: { available: boolean; enabled: boolean; setEnabled: (v: boolean) => void };
};

const AuthContext = createContext<AuthValue | null>(null);
const ROLE_KEY = "sitedesk-rol";
const BIO_KEY = "sitedesk-biyometri";
const RELOCK_MS = 5 * 60 * 1000;

function roleKey(r: ActiveRole) {
  return r.kind === "yonetici" || r.kind === "danisma" ? `${r.kind}:${r.siteId}` : r.kind;
}

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [ready, setReady] = useState(false);
  const [session, setSession] = useState<Session | null>(null);
  const [context, setContext] = useState<UserContext | null>(null);
  const [adminSites, setAdminSites] = useState<{ id: string; name: string; type: string }[]>([]);
  const [contextError, setContextError] = useState<string | null>(null);
  const [locked, setLocked] = useState(false);
  const [savedRole, setSavedRole] = useState<string | null>(null);
  const [sitePicked, setSitePicked] = useState(false);
  const [bioAvailable, setBioAvailable] = useState(false);
  const [bioEnabled, setBioEnabledState] = useState(true);
  const firstSession = useRef(true);

  const reloadContext = useCallback(async () => {
    setContextError(null);
    const { data, error } = await supabase.rpc("my_context");
    if (error) {
      setContextError(error.message.includes("fetch") ? NETWORK_ERROR : "Bilgileriniz alınamadı. Lütfen tekrar deneyin.");
      return;
    }
    const ctx = data as UserContext;
    setContext(ctx);
    // Sistem yöneticisi her sitede yönetici gibi çalışabilir
    if (ctx.platform_admin) {
      const { data: sites } = await supabase.from("sites").select("id, name, type").order("name");
      setAdminSites(sites ?? []);
    } else setAdminSites([]);
  }, []);

  useEffect(() => {
    (async () => {
      const [hardware, enrolled, savedBio, role] = await Promise.all([
        LocalAuthentication.hasHardwareAsync().catch(() => false),
        LocalAuthentication.isEnrolledAsync().catch(() => false),
        AsyncStorage.getItem(BIO_KEY).catch(() => null),
        AsyncStorage.getItem(ROLE_KEY).catch(() => null),
      ]);
      const available = hardware && enrolled;
      const enabled = savedBio !== "0";
      setBioAvailable(available);
      setBioEnabledState(enabled);
      setSavedRole(role);
      const { data } = await supabase.auth.getSession();
      setSession(data.session);
      // Uygulama açılırken oturum varsa parmak izi / yüz tanıma istenir
      if (data.session && available && enabled) setLocked(true);
      if (data.session) await reloadContext();
      setReady(true);
    })();
    const { data: sub } = supabase.auth.onAuthStateChange((_event, s) => {
      if (firstSession.current) {
        firstSession.current = false;
        return;
      }
      setSession(s);
      if (!s) setContext(null);
    });
    return () => sub.subscription.unsubscribe();
  }, [reloadContext]);

  // Uygulama 5 dakikadan uzun arka planda kaldıysa öne gelince kimlik yeniden sorulur
  const backgroundAt = useRef<number | null>(null);
  useEffect(() => {
    const sub = AppState.addEventListener("change", (state) => {
      if (state === "background") backgroundAt.current = Date.now();
      else if (state === "active") {
        const away = backgroundAt.current ? Date.now() - backgroundAt.current : 0;
        backgroundAt.current = null;
        if (away > RELOCK_MS && session && bioAvailable && bioEnabled) setLocked(true);
      }
    });
    return () => sub.remove();
  }, [session, bioAvailable, bioEnabled]);

  // Giriş yapılıp kilit açılınca telefon bildirimlere kaydolur (izin ilk seferde nedeniyle birlikte sorulur)
  useEffect(() => {
    if (!session || locked || !context) return;
    const resident = context.units.length > 0;
    const staff = context.staff.length > 0 || context.platform_admin;
    const text =
      staff && !resident
        ? "Yeni ve acil arıza kayıtlarında size hemen haber verelim."
        : "Kargonuz gelince, arıza kaydınızın durumu değişince ve yönetim cevap yazınca size haber verelim.";
    registerForPush(text);
  }, [session, locked, context]);

  const roleOptions = useMemo<ActiveRole[]>(() => {
    if (!context) return [];
    // Sistem yöneticisi: önce Platform ekranı, sonra her siteye yönetici gözüyle bakabilir
    const staff: ActiveRole[] = context.platform_admin
      ? [{ kind: "platform" }, ...adminSites.map((s) => ({ kind: "yonetici", siteId: s.id, siteName: s.name, siteType: s.type }) as ActiveRole)]
      : context.staff.map((m) => ({ kind: m.role, siteId: m.site_id, siteName: m.site_name, siteType: m.site_type }));
    // Sistem yöneticisinin kendi danışma üyelikleri de seçilebilir
    if (context.platform_admin)
      for (const m of context.staff.filter((m) => m.role === "danisma")) staff.push({ kind: "danisma", siteId: m.site_id, siteName: m.site_name, siteType: m.site_type });
    return [...staff, ...(context.units.length ? [{ kind: "sakin" } as ActiveRole] : [])];
  }, [context, adminSites]);

  const active = useMemo<ActiveRole>(() => {
    if (!roleOptions.length) return { kind: "yok" };
    return roleOptions.find((r) => roleKey(r) === savedRole) ?? roleOptions[0];
  }, [roleOptions, savedRole]);

  const setActive = useCallback((r: ActiveRole) => {
    const k = roleKey(r);
    setSavedRole(k);
    setSitePicked(true);
    AsyncStorage.setItem(ROLE_KEY, k).catch(() => {});
  }, []);

  const signIn = useCallback(
    async (login: string, password: string) => {
      const id = loginIdentifier(login);
      if ("error" in id) return id.error;
      if (!password) return "Şifrenizi yazın.";
      const { data, error } = await supabase.auth.signInWithPassword({ email: id.email, password });
      if (error) {
        if (error.message.toLowerCase().includes("fetch") || error.name === "AuthRetryableFetchError") return NETWORK_ERROR;
        if (error.code === "invalid_credentials") return "Telefon numarası veya şifre hatalı.";
        if (error.code === "over_request_rate_limit") return "Çok fazla deneme yapıldı. Biraz sonra tekrar deneyin.";
        return "Giriş yapılamadı. Lütfen tekrar deneyin.";
      }
      setSession(data.session);
      setLocked(false);
      await reloadContext();
      return null;
    },
    [reloadContext]
  );

  const signOut = useCallback(async () => {
    await unregisterPush().catch(() => {});
    await supabase.auth.signOut().catch(() => {});
    setSession(null);
    setContext(null);
    setLocked(false);
    setSitePicked(false);
  }, []);

  const unlock = useCallback(async () => {
    const result = await LocalAuthentication.authenticateAsync({
      promptMessage: "SiteDesk'e giriş",
      cancelLabel: "Vazgeç",
      fallbackLabel: "Telefon şifresini kullan",
    });
    if (result.success) setLocked(false);
    return result.success;
  }, []);

  const setEnabled = useCallback((v: boolean) => {
    setBioEnabledState(v);
    AsyncStorage.setItem(BIO_KEY, v ? "1" : "0").catch(() => {});
  }, []);

  const value: AuthValue = {
    ready,
    session,
    context,
    contextError,
    locked,
    active,
    roleOptions,
    setActive,
    sitePicked,
    signIn,
    signOut,
    reloadContext,
    unlock,
    biometric: { available: bioAvailable, enabled: bioEnabled, setEnabled },
  };
  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth, AuthProvider içinde kullanılmalı");
  return ctx;
}

export function roleLabel(r: ActiveRole): string {
  if (r.kind === "yonetici") return `Yönetici · ${r.siteName}`;
  if (r.kind === "danisma") return `Danışma · ${r.siteName}`;
  if (r.kind === "sakin") return "Sakin";
  if (r.kind === "platform") return "Sistem yöneticisi · Bütün siteler";
  return "Rol yok";
}
export { roleKey };
