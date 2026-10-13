import { useLocalSearchParams } from "expo-router";
import { InviteAccept } from "@/components/invite-accept";

// Davet bağlantısı uygulamayı buraya açar: sitedesk://davet/<anahtar>
export default function InviteLinkScreen() {
  const { key } = useLocalSearchParams<{ key: string }>();
  return <InviteAccept initialKey={key} />;
}
