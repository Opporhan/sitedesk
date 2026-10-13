import { useAuth } from "@/auth";
import { StaffTickets } from "@/components/staff-tickets";

// Danışma: sitenin arıza ve talepleri; açar, not yazar, sakin adına yeni kayıt açar
export default function DeskTickets() {
  const { active } = useAuth();
  if (active.kind !== "danisma") return null;
  return <StaffTickets siteId={active.siteId} siteName={active.siteName} showSummary={false} title="Arıza ve Talepler" />;
}
