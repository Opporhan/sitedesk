import { DoorOpen, Package, UserRound, Wrench } from "lucide-react-native";
import { RoleTabs } from "@/components/role-tabs";

// Danışma: Kargo · Ziyaretçi · Arıza · Profil (kişi ekleme sadece yönetimde)
export default function DeskLayout() {
  return (
    <RoleTabs
      kind="danisma"
      tabs={[
        { name: "index", title: "Kargo", icon: Package },
        { name: "ziyaretci", title: "Ziyaretçi", icon: DoorOpen },
        { name: "ariza", title: "Arıza", icon: Wrench },
        { name: "profil", title: "Profil", icon: UserRound },
      ]}
    />
  );
}
