import { openSitesList } from "@/lib/nav";
import { useAuth } from "@/auth";
import { StaffTickets } from "@/components/staff-tickets";
import { Pressable, Text } from "react-native";
import { ChevronLeft } from "lucide-react-native";
import { FONT, useTheme } from "@/theme";

// Yönetici: açık kayıtlar (acil üstte, sonra en eski), filtreler, bu ayın özeti. Birden çok sitesi olana üstte "Sitelerim".
export default function ManagerRecords() {
  const { active, roleOptions, context } = useAuth();
  const { colors } = useTheme();
  if (active.kind !== "yonetici") return null;
  const many = !context?.platform_admin && roleOptions.filter((r) => r.kind === "yonetici").length > 1;
  return (
    <StaffTickets
      siteId={active.siteId}
      siteName={active.siteName}
      showSummary
      header={
        many ? (
          // Sol üstte, başparmakla kolay basılacak geniş alan
          <Pressable
            accessibilityRole="button"
            onPress={openSitesList}
            hitSlop={8}
            style={({ pressed }) => ({ alignSelf: "flex-start", flexDirection: "row", alignItems: "center", gap: 4, minHeight: 44, paddingRight: 16, marginLeft: -6, opacity: pressed ? 0.6 : 1 })}
          >
            <ChevronLeft size={24} color={colors.vurgu} />
            <Text style={{ fontFamily: FONT.kalin, fontSize: 16, color: colors.vurgu }}>Bütün Sitelerim</Text>
          </Pressable>
        ) : undefined
      }
    />
  );
}
