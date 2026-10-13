import { KeyboardAvoidingView, Modal, Platform, Pressable, ScrollView, Text, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { X } from "lucide-react-native";
import { FONT, SIZE, useTheme } from "@/theme";

// Alttan açılan panel (ikincil işler için: kargo kaydet, teslim et, ziyaretçi girişi)
export function Sheet({ title, subtitle, visible, onClose, children }: { title: string; subtitle?: string; visible: boolean; onClose: () => void; children: React.ReactNode }) {
  const { colors } = useTheme();
  const insets = useSafeAreaInsets();
  return (
    <Modal transparent visible={visible} animationType="slide" onRequestClose={onClose}>
      <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === "ios" ? "padding" : undefined}>
        <Pressable accessibilityLabel="Kapat" onPress={onClose} style={{ flex: 1, backgroundColor: "rgba(20,15,10,0.45)" }} />
        <View style={{ backgroundColor: colors.zemin, borderTopLeftRadius: 24, borderTopRightRadius: 24, maxHeight: "88%", paddingBottom: insets.bottom + 16 }}>
          <View style={{ alignItems: "center", paddingTop: 10 }}>
            <View style={{ width: 40, height: 5, borderRadius: 3, backgroundColor: colors.cizgi }} />
          </View>
          <View style={{ flexDirection: "row", alignItems: "flex-start", paddingHorizontal: SIZE.kenar, paddingTop: 12, gap: 8 }}>
            <View style={{ flex: 1, gap: 2 }}>
              {subtitle && <Text style={{ fontFamily: FONT.orta, fontSize: 15, color: colors.yaziSoluk }}>{subtitle}</Text>}
              <Text style={{ fontFamily: FONT.cokKalin, fontSize: 24, color: colors.yazi }}>{title}</Text>
            </View>
            <Pressable accessibilityRole="button" accessibilityLabel="Kapat" onPress={onClose} hitSlop={8} style={{ width: 44, height: 44, borderRadius: 20, alignItems: "center", justifyContent: "center", backgroundColor: colors.kutuKoyu }}>
              <X size={20} color={colors.yazi} />
            </Pressable>
          </View>
          <ScrollView contentContainerStyle={{ padding: SIZE.kenar, gap: 16 }} keyboardShouldPersistTaps="handled">
            {children}
          </ScrollView>
        </View>
      </KeyboardAvoidingView>
    </Modal>
  );
}
