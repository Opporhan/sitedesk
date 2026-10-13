import { useState } from "react";
import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
  type PressableProps,
  type TextInputProps,
  type TextProps,
} from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { router } from "expo-router";
import { ChevronLeft, ChevronRight, Eye, EyeOff, Moon, Sun, type LucideIcon } from "lucide-react-native";
import { FONT, SIZE, useTheme } from "@/theme";

// Tasarım ilkeleri: sade ve ferah; kutu içinde kutu yok; tek vurgu rengi; yazılar her yerde rahat okunur (en az 14 px);
// listeler gruplu ve düz; ikincil seçimler alttan açılan panelde.

// ---------- Ekran iskeleti ----------

export function Screen({
  title,
  subtitle,
  header,
  footer,
  children,
}: {
  title: string;
  subtitle?: string;
  header?: React.ReactNode;
  footer?: React.ReactNode; // altta sabit duran ana düğme
  children: React.ReactNode;
}) {
  const { colors } = useTheme();
  const insets = useSafeAreaInsets();
  return (
    <View style={{ flex: 1, backgroundColor: colors.zemin }}>
      <ScrollView
        contentContainerStyle={{ paddingTop: insets.top + 8, paddingHorizontal: SIZE.kenar, paddingBottom: footer ? 120 : 40, gap: 20 }}
        keyboardShouldPersistTaps="handled"
      >
        {header}
        <ScreenTitle title={title} subtitle={subtitle} />
        {children}
      </ScrollView>
      {footer && <View style={{ position: "absolute", left: SIZE.kenar, right: SIZE.kenar, bottom: 16 }}>{footer}</View>}
    </View>
  );
}

export function ScreenTitle({ title, subtitle }: { title: string; subtitle?: string }) {
  const { colors } = useTheme();
  return (
    <View style={{ flexDirection: "row", alignItems: "flex-start", gap: 8, paddingTop: 8 }}>
      <View style={{ flex: 1, gap: 4 }}>
        {subtitle && <Text style={{ fontFamily: FONT.orta, fontSize: 15, color: colors.yaziSoluk }}>{subtitle}</Text>}
        <Text accessibilityRole="header" style={{ fontFamily: FONT.cokKalin, fontSize: 30, lineHeight: 36, letterSpacing: -0.5, color: colors.yazi }}>
          {title}
        </Text>
      </View>
      <ThemeToggle />
    </View>
  );
}

// ---------- Yazı ----------

export function Body({ style, ...props }: TextProps) {
  const { colors } = useTheme();
  return <Text {...props} style={[{ fontFamily: FONT.normal, fontSize: SIZE.yazi, lineHeight: 24, color: colors.yazi }, style]} />;
}

export function Muted({ style, ...props }: TextProps) {
  const { colors } = useTheme();
  return <Text {...props} style={[{ fontFamily: FONT.normal, fontSize: 15, lineHeight: 21, color: colors.yaziSoluk }, style]} />;
}

// Bölüm başlığı: küçük, sakin, listenin hemen üstünde
export function SectionLabel({ children }: { children: string }) {
  const { colors } = useTheme();
  return (
    <View style={{ marginBottom: -8, paddingHorizontal: 4 }}>
      <Text style={{ fontFamily: FONT.kalin, fontSize: 14, letterSpacing: 0.3, color: colors.yaziSoluk }}>{children}</Text>
    </View>
  );
}

// ---------- Kutular ve listeler ----------

export function Card({ children }: { children: React.ReactNode }) {
  const { colors } = useTheme();
  return <View style={[styles.card, { backgroundColor: colors.kutu, padding: 18 }]}>{children}</View>;
}

// Gruplu liste: tek kutu, satırlar ince çizgiyle ayrılır (her satır ayrı kart değil)
export function ListGroup({ children }: { children: React.ReactNode }) {
  const { colors } = useTheme();
  const items = (Array.isArray(children) ? children.flat() : [children]).filter(Boolean);
  return (
    <View style={{ borderRadius: 18, backgroundColor: colors.kutu, overflow: "hidden" }}>
      {items.map((child, i) => (
        <View key={i}>
          {/* Ayırıcı çizgi soldan içeride başlar; satırın kendisi kaymaz (bütün satırlar aynı hizada) */}
          {i > 0 && <View style={{ position: "absolute", top: 0, left: 18, right: 0, height: StyleSheet.hairlineWidth, backgroundColor: colors.cizgi }} />}
          {child}
        </View>
      ))}
    </View>
  );
}

export function ListRow({
  title,
  subtitle,
  left,
  right,
  onPress,
  chevron = !!onPress,
  tone,
}: {
  title: string;
  subtitle?: string;
  left?: React.ReactNode;
  right?: React.ReactNode;
  onPress?: () => void;
  chevron?: boolean;
  tone?: "tehlike";
}) {
  const { colors } = useTheme();
  const content = (
    <View style={{ flexDirection: "row", alignItems: "center", gap: 14, minHeight: 60, paddingVertical: 12, paddingLeft: 18, paddingRight: 14 }}>
      {left}
      <View style={{ flex: 1, gap: 3 }}>
        <Text numberOfLines={2} style={{ fontFamily: FONT.kalin, fontSize: 16, lineHeight: 21, color: tone === "tehlike" ? colors.hata : colors.yazi }}>
          {title}
        </Text>
        {subtitle ? (
          <Text numberOfLines={2} style={{ fontFamily: FONT.normal, fontSize: 14, lineHeight: 19, color: colors.yaziSoluk }}>
            {subtitle}
          </Text>
        ) : null}
      </View>
      {right}
      {chevron && <ChevronRight size={20} color={colors.yaziSoluk} />}
    </View>
  );
  if (!onPress) return content;
  return (
    <Pressable accessibilityRole="button" onPress={onPress} style={({ pressed }) => ({ backgroundColor: pressed ? colors.kutuKoyu : "transparent" })}>
      {content}
    </Pressable>
  );
}

// Tek durum rozeti (satır başına en fazla bir tane)
export function Pill({ label, tone = "notr" }: { label: string; tone?: "notr" | "bilgi" | "basari" | "bekliyor" | "hata" }) {
  const { colors } = useTheme();
  const map = {
    notr: [colors.kutuKoyu, colors.yaziSoluk],
    bilgi: [colors.bilgiZemin, colors.bilgi],
    basari: [colors.basariZemin, colors.basari],
    bekliyor: [colors.bekliyorZemin, colors.bekliyor],
    hata: [colors.hataZemin, colors.hata],
  } as const;
  const [bg, fg] = map[tone];
  return (
    <View style={{ backgroundColor: bg, borderRadius: 999, paddingHorizontal: 10, paddingVertical: 4, alignSelf: "flex-start" }}>
      <Text numberOfLines={1} style={{ fontFamily: FONT.kalin, fontSize: 13, color: fg }}>
        {label}
      </Text>
    </View>
  );
}

// Boş durum: sade simge + başlık + kısa açıklama
export function EmptyState({ icon: Icon, title, text }: { icon: LucideIcon; title: string; text: string }) {
  const { colors } = useTheme();
  return (
    <View style={{ alignItems: "center", gap: 10, paddingVertical: 40, paddingHorizontal: 24 }}>
      <View style={{ width: 64, height: 64, borderRadius: 32, backgroundColor: colors.vurguAcik, alignItems: "center", justifyContent: "center" }}>
        <Icon size={28} color={colors.vurgu} strokeWidth={1.75} />
      </View>
      <Text style={{ fontFamily: FONT.kalin, fontSize: 18, color: colors.yazi, textAlign: "center" }}>{title}</Text>
      <Muted style={{ textAlign: "center", maxWidth: 300 }}>{text}</Muted>
    </View>
  );
}

// ---------- Seçimler ----------

// Ekran genişliğinde, kaydırmasız seçim çubuğu (2–4 seçenek)
export function Segmented<T extends string>({ value, options, onChange }: { value: T; options: { key: T; label: string }[]; onChange: (v: T) => void }) {
  const { colors } = useTheme();
  return (
    <View accessibilityRole="tablist" style={{ flexDirection: "row", backgroundColor: colors.kutuKoyu, borderRadius: 14, padding: 4, gap: 4 }}>
      {options.map((o) => {
        const on = value === o.key;
        return (
          <Pressable
            key={o.key}
            accessibilityRole="tab"
            accessibilityState={{ selected: on }}
            onPress={() => onChange(o.key)}
            style={{ flex: 1, minHeight: 44, borderRadius: 11, alignItems: "center", justifyContent: "center", paddingHorizontal: 4, backgroundColor: on ? colors.kutu : "transparent" }}
          >
            <Text numberOfLines={1} adjustsFontSizeToFit minimumFontScale={0.85} style={{ fontFamily: on ? FONT.kalin : FONT.orta, fontSize: 15, color: on ? colors.yazi : colors.yaziSoluk }}>
              {o.label}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
}

// Eşit kutulu ızgara: genişliği ölçer, sığan kadar sütun açar (telefonda 4, tablette daha fazla); son satırdaki kutular büyümez
export function Grid({ minItemWidth = 76, gap = 8, children }: { minItemWidth?: number; gap?: number; children: React.ReactNode }) {
  const [width, setWidth] = useState(0);
  const items = (Array.isArray(children) ? children.flat() : [children]).filter(Boolean);
  const columns = width ? Math.max(2, Math.floor((width + gap) / (minItemWidth + gap))) : 4;
  const itemWidth = width ? (width - gap * (columns - 1)) / columns : 0;
  return (
    <View onLayout={(e) => setWidth(Math.floor(e.nativeEvent.layout.width))} style={{ flexDirection: "row", flexWrap: "wrap", gap }}>
      {width > 0 &&
        items.map((child, i) => (
          <View key={i} style={{ width: itemWidth }}>
            {child}
          </View>
        ))}
    </View>
  );
}

// Seçim kutusu (ör. tür, daire); seçili olan vurgu rengiyle
export function Choice({ label, selected, icon: Icon, style, ...props }: Omit<PressableProps, "style"> & { label: string; selected: boolean; icon?: LucideIcon; style?: object }) {
  const { colors } = useTheme();
  return (
    <Pressable
      accessibilityRole="radio"
      accessibilityState={{ selected }}
      {...props}
      style={({ pressed }) => [
        styles.choice,
        { backgroundColor: selected ? colors.vurguAcik : colors.kutu, borderColor: selected ? colors.vurgu : "transparent", opacity: pressed ? 0.8 : 1 },
        style,
      ]}
    >
      {Icon && <Icon size={22} color={selected ? colors.vurgu : colors.yaziSoluk} strokeWidth={1.75} />}
      <Text numberOfLines={1} adjustsFontSizeToFit minimumFontScale={0.8} style={{ fontFamily: selected ? FONT.kalin : FONT.orta, fontSize: 16, color: colors.yazi }}>
        {label}
      </Text>
    </Pressable>
  );
}

// ---------- Form ----------

// Etiketli yazı alanı; hata mesajı alanın hemen altında. Şifre alanında sağda göz: dokununca şifre görünür/gizlenir.
export function Field({ label, error, secureTextEntry, style, ...props }: TextInputProps & { label: string; error?: string | null }) {
  const { colors } = useTheme();
  const [visible, setVisible] = useState(false);
  const [focused, setFocused] = useState(false);
  const Icon = visible ? EyeOff : Eye;
  return (
    <View style={{ gap: 8 }}>
      <Text style={{ fontFamily: FONT.orta, fontSize: 15, color: colors.yaziSoluk, paddingHorizontal: 4 }}>{label}</Text>
      <View style={{ justifyContent: "center" }}>
        <TextInput
          placeholderTextColor={colors.yaziSoluk}
          accessibilityLabel={label}
          autoCapitalize={secureTextEntry ? "none" : props.autoCapitalize}
          autoCorrect={secureTextEntry ? false : props.autoCorrect}
          onFocus={() => setFocused(true)}
          onBlur={() => setFocused(false)}
          {...props}
          secureTextEntry={secureTextEntry && !visible}
          style={[
            styles.input,
            { backgroundColor: colors.kutu, borderColor: error ? colors.hata : focused ? colors.vurgu : "transparent", color: colors.yazi, fontFamily: FONT.normal },
            secureTextEntry ? { paddingRight: 52 } : null,
            style,
          ]}
        />
        {secureTextEntry && (
          <Pressable
            accessibilityRole="button"
            accessibilityLabel={visible ? "Şifreyi gizle" : "Şifreyi göster"}
            onPress={() => setVisible((v) => !v)}
            hitSlop={4}
            style={{ position: "absolute", right: 4, width: 44, height: 44, alignItems: "center", justifyContent: "center" }}
          >
            <Icon size={22} color={colors.yaziSoluk} />
          </Pressable>
        )}
      </View>
      {!!error && <Text style={{ fontFamily: FONT.normal, fontSize: 14, color: colors.hata, paddingHorizontal: 4 }}>{error}</Text>}
    </View>
  );
}

// Düğme: ana (dolu vurgu), ikincil (yumuşak zemin), tehlike (kırmızımsı), metin (sadece yazı). İşlem sürerken pasif + dönen gösterge.
export function Button({
  label,
  loading,
  variant = "ana",
  icon: Icon,
  disabled,
  ...props
}: PressableProps & { label: string; loading?: boolean; variant?: "ana" | "ikincil" | "tehlike" | "metin"; icon?: LucideIcon }) {
  const { colors } = useTheme();
  const bg = variant === "ana" ? colors.vurgu : variant === "tehlike" ? colors.hataZemin : variant === "ikincil" ? colors.kutuKoyu : "transparent";
  const fg = variant === "ana" ? colors.vurguYazi : variant === "tehlike" ? colors.hata : variant === "metin" ? colors.vurgu : colors.yazi;
  const off = disabled || loading;
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityState={{ disabled: !!off, busy: !!loading }}
      disabled={off}
      {...props}
      style={({ pressed }) => [styles.button, { backgroundColor: bg, opacity: off ? 0.5 : pressed ? 0.85 : 1 }]}
    >
      {loading ? <ActivityIndicator color={fg} /> : Icon ? <Icon size={20} color={fg} strokeWidth={2} /> : null}
      <Text numberOfLines={1} style={{ fontFamily: FONT.kalin, fontSize: 17, color: fg }}>
        {label}
      </Text>
    </Pressable>
  );
}

// Uyarı / bilgi kutusu (renk + metin; sadece renge güvenilmez)
export function Notice({ tone = "bilgi", text }: { tone?: "bilgi" | "hata" | "basari" | "bekliyor"; text: string }) {
  const { colors } = useTheme();
  const map = {
    bilgi: [colors.bilgiZemin, colors.bilgi],
    hata: [colors.hataZemin, colors.hata],
    basari: [colors.basariZemin, colors.basari],
    bekliyor: [colors.bekliyorZemin, colors.bekliyor],
  } as const;
  const [bg, fg] = map[tone];
  return (
    <View accessibilityRole="alert" style={{ backgroundColor: bg, borderRadius: 14, paddingVertical: 14, paddingHorizontal: 16 }}>
      <Text style={{ fontFamily: FONT.orta, fontSize: 15, lineHeight: 21, color: fg }}>{text}</Text>
    </View>
  );
}

// ---------- Üst köşe ----------

// Geri düğmesi (alt menüsü olmayan ekranlarda)
export function BackHeader({ label = "Geri" }: { label?: string }) {
  const { colors } = useTheme();
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={label}
      hitSlop={8}
      onPress={() => (router.canGoBack() ? router.back() : router.replace("/"))}
      style={{ flexDirection: "row", alignItems: "center", gap: 2, minHeight: 44, alignSelf: "flex-start", marginLeft: -6, marginBottom: -16 }}
    >
      <ChevronLeft size={24} color={colors.vurgu} />
      <Text style={{ fontFamily: FONT.orta, fontSize: 17, color: colors.vurgu }}>{label}</Text>
    </Pressable>
  );
}

// Sağ üstte küçük tema düğmesi: bej ↔ koyu mavi (seçim telefonda hatırlanır)
export function ThemeToggle() {
  const { name, colors, setTheme } = useTheme();
  const dark = name === "mavi";
  const Icon = dark ? Sun : Moon;
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={dark ? "Bej temaya geç" : "Koyu mavi temaya geç"}
      hitSlop={6}
      onPress={() => setTheme(dark ? "bej" : "mavi")}
      style={({ pressed }) => ({ width: 40, height: 40, borderRadius: 20, alignItems: "center", justifyContent: "center", backgroundColor: pressed ? colors.kutuKoyu : "transparent" })}
    >
      <Icon size={20} color={colors.yaziSoluk} strokeWidth={1.75} />
    </Pressable>
  );
}

const styles = StyleSheet.create({
  card: { borderRadius: 18, gap: 14 },
  input: { minHeight: 54, borderWidth: 1.5, borderRadius: 14, paddingHorizontal: 16, fontSize: SIZE.yazi },
  button: { minHeight: 54, borderRadius: 14, flexDirection: "row", alignItems: "center", justifyContent: "center", gap: 8, paddingHorizontal: 18 },
  choice: { flex: 1, minHeight: 54, borderWidth: 1.5, borderRadius: 14, alignItems: "center", justifyContent: "center", gap: 6, paddingHorizontal: 10, paddingVertical: 10 },
});
