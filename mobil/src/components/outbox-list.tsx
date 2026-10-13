import { Text } from "react-native";
import { CloudOff } from "lucide-react-native";
import { useOutbox } from "@/outbox";
import { ListGroup, ListRow, SectionLabel } from "@/components/ui";
import { FONT, useTheme } from "@/theme";

// Telefonda bekleyen (henüz gönderilemeyen) kayıtlar: dokununca tekrar dener; takılan kayıttan vazgeçilebilir
export function OutboxList() {
  const { colors } = useTheme();
  const { drafts, sending, retry, discard } = useOutbox();
  if (!drafts.length) return null;
  return (
    <>
      <SectionLabel>GÖNDERİLECEK</SectionLabel>
        <ListGroup>
          {drafts.map((d) => {
            const isSending = sending === d.clientId;
            return (
              <ListRow
                key={d.clientId}
                left={<CloudOff size={20} color={colors.bekliyor} strokeWidth={1.75} />}
                title={d.title}
                subtitle={isSending ? "Gönderiliyor…" : `${d.lastError ?? "Sırada"} · Tekrar denemek için dokunun`}
                right={
                  // Kayıt açılmadıysa her zaman; açıldı ama dosyalar 3 kez gönderilemediyse dosyalardan vazgeçilebilir (kayıt kalır)
                  !isSending && (!d.ticketId || d.attempts >= 3) ? (
                    <Text
                      accessibilityRole="button"
                      onPress={() => discard(d.clientId)}
                      style={{ fontFamily: FONT.orta, fontSize: 15, color: colors.hata, paddingHorizontal: 12, minHeight: 44, textAlignVertical: "center", lineHeight: 44 }}
                    >
                      {d.ticketId ? "Dosyaları Gönderme" : "Vazgeç"}
                    </Text>
                  ) : undefined
                }
                onPress={isSending ? undefined : retry}
                chevron={false}
              />
            );
          })}
        </ListGroup>
    </>
  );
}
