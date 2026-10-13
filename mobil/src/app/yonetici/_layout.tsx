import { ClipboardList, UserPlus, UserRound, Wrench } from "lucide-react-native";
import { RoleTabs } from "@/components/role-tabs";

// Yönetici: Kayıtlar · Hizmet (tamir/servis girişleri) · Kişiler · Profil. Kargoyu ve sakinlerin misafirlerini sadece danışma ve sakin görür.
export default function ManagerLayout() {
  return (
    <RoleTabs
      kind="yonetici"
      tabs={[
        { name: "index", title: "Kayıtlar", icon: ClipboardList },
        { name: "hizmet", title: "Hizmet", icon: Wrench },
        { name: "kisiler", title: "Kişiler", icon: UserPlus },
        { name: "profil", title: "Profil", icon: UserRound },
      ]}
    />
  );
}
