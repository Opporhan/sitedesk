import { router, useFocusEffect } from "expo-router";
import { useCallback, useState } from "react";
import { Building2, Plus } from "lucide-react-native";
import { NETWORK_ERROR, supabase } from "@/lib/supabase";
import { formatBytes } from "@/lib/format";
import { Button, EmptyState, ListGroup, ListRow, Notice, Pill, Screen } from "@/components/ui";

type SiteStat = {
  site_id: string;
  name: string;
  active: boolean;
  is_demo: boolean;
  units: number;
  residents_with_app: number;
  staff: number;
  open_tickets: number;
  storage_bytes: number;
};

// Sistem yöneticisi: bütün siteler, durumları, sayıları ve dosya deposu kullanımı
export default function PlatformSites() {
  const [sites, setSites] = useState<SiteStat[]>([]);
  const [live, setLive] = useState<Record<string, { urgent_open: number }>>({});
  const [error, setError] = useState<string | null>(null);

  useFocusEffect(
    useCallback(() => {
      // Her sitenin acil kaydı (Sitelerim ile aynı sayı; kargoyu sadece danışma ve sakin görür)
      supabase.rpc("my_sites_overview").then(({ data }) => {
        const rows = (data ?? []) as { site_id: string; urgent_open: number }[];
        setLive(Object.fromEntries(rows.map((r) => [r.site_id, r])));
      });
      supabase.rpc("platform_site_stats").then(({ data, error: e }) => {
        if (e) setError(e.message.includes("fetch") ? NETWORK_ERROR : "Siteler alınamadı.");
        else {
          setError(null);
          setSites((data ?? []) as SiteStat[]);
        }
      });
    }, [])
  );

  const total = sites.reduce((s, x) => s + Number(x.storage_bytes), 0);

  return (
    <Screen title="Siteler" subtitle={`Dosya deposu: ${formatBytes(total)} / 1 GB (ücretsiz plan)`}>
      <Button label="Yeni Site" icon={Plus} onPress={() => router.push("/site-yonetimi/yeni")} />
      {error && <Notice tone="hata" text={error} />}
      {sites.length === 0 && !error ? (
        <EmptyState icon={Building2} title="Henüz site yok" text="Yeni site açıp yöneticisini davet edin." />
      ) : (
        <ListGroup>
          {sites.map((s) => {
            return (
              <ListRow
                key={s.site_id}
                title={`${s.name}${s.is_demo ? " (demo)" : ""}`}
                subtitle={`${s.units} villa/daire · ${s.residents_with_app} sakin · ${s.open_tickets} açık kayıt${live[s.site_id]?.urgent_open ? ` (${live[s.site_id].urgent_open} acil)` : ""}`}
                right={<Pill label={s.active ? "Aktif" : "Kapalı"} tone={s.active ? "basari" : "hata"} />}
                onPress={() => router.push({ pathname: "/site-yonetimi/[id]", params: { id: s.site_id } })}
              />
            );
          })}
        </ListGroup>
      )}
    </Screen>
  );
}
