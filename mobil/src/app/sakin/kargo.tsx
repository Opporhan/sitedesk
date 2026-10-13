import { useAuth } from "@/auth";
import { DeskLog } from "@/components/desk-log";

// Sakin: kendi dairelerinin kargoları ve ziyaretçileri (son 30 gün)
export default function ResidentDesk() {
  const { context } = useAuth();
  const units = context?.units ?? [];
  return <DeskLog title="Kargo ve ziyaretçi" subtitle={units.length === 1 ? `${units[0].label} · ${units[0].site_name}` : undefined} unitIds={units.map((u) => u.unit_id)} />;
}
