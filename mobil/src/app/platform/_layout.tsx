import { Building2, UserRound } from "lucide-react-native";
import { RoleTabs } from "@/components/role-tabs";

// Sistem yöneticisi (platform): Siteler · Profil
export default function PlatformLayout() {
  return (
    <RoleTabs
      kind="platform"
      tabs={[
        { name: "index", title: "Siteler", icon: Building2 },
        { name: "profil", title: "Profil", icon: UserRound },
      ]}
    />
  );
}
