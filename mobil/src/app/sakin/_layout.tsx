import { ClipboardList, Package, UserRound } from "lucide-react-native";
import { RoleTabs } from "@/components/role-tabs";

// Sakin: Kayıtlarım · Kargo (kargolarım + ziyaretçilerim) · Profil
export default function ResidentLayout() {
  return (
    <RoleTabs
      kind="sakin"
      tabs={[
        { name: "index", title: "Kayıtlarım", icon: ClipboardList },
        { name: "kargo", title: "Kargo", icon: Package },
        { name: "profil", title: "Profil", icon: UserRound },
      ]}
    />
  );
}
