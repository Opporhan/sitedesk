import { useAuth } from "@/auth";
import { DeskLog } from "@/components/desk-log";

// Yönetici: sitede tamir, servis, teknisyen gibi iş için gelenler (içeridekiler ve son 7 gün). Sakinlerin misafirleri görünmez.
export default function ManagerServiceVisits() {
  const { active } = useAuth();
  if (active.kind !== "yonetici") return null;
  return <DeskLog title="Hizmet girişleri" subtitle={active.siteName} siteId={active.siteId} />;
}
