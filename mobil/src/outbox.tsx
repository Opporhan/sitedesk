import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from "react";
import { AppState } from "react-native";
import AsyncStorage from "@react-native-async-storage/async-storage";
import * as Network from "expo-network";
import { Directory, File, Paths } from "expo-file-system";
import { supabase } from "@/lib/supabase";
import type { PickedMedia } from "@/lib/media";
import type { TicketKind, TicketLocation } from "@/lib/tickets";
import { useAuth } from "@/auth";
import { uuid } from "@/lib/uuid";

// Giden kutusu: zayıf internette kayıt kaybolmaz. Kayıt ve dosyaları önce telefonda saklanır, sonra sırayla gönderilir;
// bağlantı gelince ya da uygulama öne gelince kendiliğinden tekrar denenir. Her kaydın kendi kimliği (clientId) olduğu için
// tekrar gönderimde ikinci kayıt açılmaz, aynı dosya ikinci kez eklenmez. Her kayıt açan hesaba aittir: aynı telefonda
// başka hesapla girilirse o kişinin kayıtları gönderilmez ve görünmez (hesabı geri gelince gönderilir).
export type Draft = {
  clientId: string;
  userId?: string;
  siteId: string;
  unitId: string;
  unitLabel: string;
  kind: TicketKind;
  location: TicketLocation;
  title: string;
  description: string;
  urgent: boolean;
  media: (PickedMedia & { localUri: string; path?: string; uploaded?: boolean; registered?: boolean })[];
  ticketId?: string;
  createdAt: string;
  attempts: number;
  lastError?: string;
};

type OutboxValue = {
  drafts: Draft[];
  sending: string | null;
  online: boolean;
  enqueue: (d: Omit<Draft, "clientId" | "userId" | "createdAt" | "attempts" | "media"> & { media: PickedMedia[] }) => Promise<void>;
  retry: () => void;
  discard: (clientId: string) => Promise<void>;
  lastSent: number; // liste yenilensin diye
};

const KEY = "sitedesk-giden";
const OutboxContext = createContext<OutboxValue | null>(null);
const dir = () => new Directory(Paths.document, "giden");
async function save(drafts: Draft[]) {
  await AsyncStorage.setItem(KEY, JSON.stringify(drafts)).catch(() => {});
}

// Hata mesajını kullanıcıya anlaşılır hale getirir; ağ hatası "bekliyor" sayılır
function explain(e: unknown): string {
  const msg = String((e as { message?: string })?.message ?? e);
  if (/fetch|network|timed out|internet/i.test(msg)) return "Bağlantı bekleniyor";
  if (/SD010|çok fazla/i.test(msg)) return "Bugün çok fazla kayıt açtınız; yarın tekrar deneyin.";
  if (/SD011/.test(msg)) return "En fazla 5 fotoğraf ya da 1 video eklenebilir.";
  return "Gönderilemedi, tekrar denenecek";
}

async function sendDraft(d: Draft, update: (d: Draft) => Promise<void>) {
  if (!d.ticketId) {
    const { data, error } = await supabase.rpc("create_ticket", {
      p_client_id: d.clientId,
      p_unit_id: d.unitId,
      p_kind: d.kind,
      p_location: d.location,
      p_title: d.title,
      p_description: d.description || null,
      p_urgent: d.urgent,
    });
    if (error) throw error;
    d.ticketId = data as string;
    await update(d);
  }
  for (let i = 0; i < d.media.length; i++) {
    const m = d.media[i];
    m.path = m.path ?? `${d.siteId}/${d.ticketId}/${d.clientId}-${i + 1}.${m.ext}`;
    if (!m.uploaded) {
      const body = await new File(m.localUri).arrayBuffer();
      const { error } = await supabase.storage.from("kayitlar").upload(m.path, body, { contentType: m.mime, upsert: false });
      // Daha önce yüklenmiş (bağlantı yarıda kesilmişti) → yüklendi say
      if (error && !/exists|duplicate/i.test(error.message)) throw error;
      m.uploaded = true;
      await update(d);
    }
    if (!m.registered) {
      const { error } = await supabase.rpc("add_ticket_media", { p_ticket_id: d.ticketId, p_path: m.path, p_kind: m.kind, p_size: m.size || 1, p_duration_ms: m.durationMs });
      if (error) throw error;
      m.registered = true;
      await update(d);
    }
  }
}

export function OutboxProvider({ children }: { children: React.ReactNode }) {
  const userId = useAuth().session?.user.id;
  const mine = useCallback((d: Draft) => !d.userId || d.userId === userId, [userId]);
  const [drafts, setDrafts] = useState<Draft[]>([]);
  const [sending, setSending] = useState<string | null>(null);
  const [online, setOnline] = useState(true);
  const [lastSent, setLastSent] = useState(0);
  const running = useRef(false);
  const ref = useRef<Draft[]>([]);

  const persist = useCallback(async (next: Draft[]) => {
    ref.current = next;
    setDrafts([...next]);
    await save(next);
  }, []);

  const flush = useCallback(async () => {
    if (running.current || !userId) return;
    running.current = true;
    try {
      for (const d of ref.current.filter(mine)) {
        if (!ref.current.some((x) => x.clientId === d.clientId)) continue; // bu arada vazgeçildi
        setSending(d.clientId);
        try {
          await sendDraft(d, async (u) => persist(ref.current.map((x) => (x.clientId === u.clientId ? u : x))));
          // Gönderildi: telefondaki kopyaları sil
          for (const m of d.media) {
            try {
              new File(m.localUri).delete();
            } catch {}
          }
          await persist(ref.current.filter((x) => x.clientId !== d.clientId));
          setLastSent(Date.now());
        } catch (e) {
          const why = explain(e);
          await persist(ref.current.map((x) => (x.clientId === d.clientId ? { ...x, attempts: x.attempts + 1, lastError: why } : x)));
          if (why === "Bağlantı bekleniyor") break; // internet yoksa sıradakileri de bekletir
        }
      }
    } finally {
      setSending(null);
      running.current = false;
    }
  }, [persist, userId, mine]);

  // Açılışta bekleyenleri yükle; internet gelince ve uygulama öne gelince tekrar dene
  useEffect(() => {
    AsyncStorage.getItem(KEY)
      .then((raw) => {
        ref.current = raw ? (JSON.parse(raw) as Draft[]) : [];
        setDrafts(ref.current);
        flush();
      })
      .catch(() => {});
    const net = Network.addNetworkStateListener((s) => {
      const up = !!s.isConnected && s.isInternetReachable !== false;
      setOnline(up);
      if (up) flush();
    });
    Network.getNetworkStateAsync().then((s) => setOnline(!!s.isConnected && s.isInternetReachable !== false)).catch(() => {});
    const app = AppState.addEventListener("change", (s) => s === "active" && flush());
    return () => {
      net.remove();
      app.remove();
    };
  }, [flush]);

  const enqueue = useCallback<OutboxValue["enqueue"]>(
    async (input) => {
      const clientId = uuid();
      const folder = dir();
      if (!folder.exists) folder.create({ intermediates: true });
      // Dosyalar telefonda kalıcı bir klasöre kopyalanır (seçim önbelleği silinse de gönderim yarım kalmasın)
      const media: Draft["media"] = [];
      for (let i = 0; i < input.media.length; i++) {
        const m = input.media[i];
        const target = new File(folder, `${clientId}-${i + 1}.${m.ext}`);
        await Promise.resolve(new File(m.uri).copy(target));
        media.push({ ...m, localUri: target.uri });
      }
      const draft: Draft = { ...input, media, clientId, userId, createdAt: new Date().toISOString(), attempts: 0 };
      await persist([...ref.current, draft]);
      flush();
    },
    [flush, persist, userId]
  );

  const discard = useCallback(
    async (clientId: string) => {
      const d = ref.current.find((x) => x.clientId === clientId);
      for (const m of d?.media ?? []) {
        try {
          new File(m.localUri).delete();
        } catch {}
      }
      await persist(ref.current.filter((x) => x.clientId !== clientId));
    },
    [persist]
  );

  const value = useMemo(() => ({ drafts: drafts.filter(mine), sending, online, enqueue, retry: flush, discard, lastSent }), [drafts, mine, sending, online, enqueue, flush, discard, lastSent]);
  return <OutboxContext.Provider value={value}>{children}</OutboxContext.Provider>;
}

export function useOutbox() {
  const ctx = useContext(OutboxContext);
  if (!ctx) throw new Error("useOutbox, OutboxProvider içinde kullanılmalı");
  return ctx;
}
