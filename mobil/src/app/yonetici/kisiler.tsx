import { useAuth } from "@/auth";
import { PeopleManager } from "@/components/people-manager";
import { Screen } from "@/components/ui";

export default function ManagerPeople() {
  const { active } = useAuth();
  if (active.kind !== "yonetici") return null;
  return (
    <Screen title="Kişiler" subtitle={active.siteName}>
      <PeopleManager siteId={active.siteId} siteName={active.siteName} siteType={active.siteType} />
    </Screen>
  );
}
