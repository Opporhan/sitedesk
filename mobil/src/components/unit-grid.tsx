import { useEffect, useState } from "react";
import { Pressable, ScrollView, Text, View } from "react-native";
import { supabase } from "@/lib/supabase";
import { Grid, Muted, Segmented } from "@/components/ui";
import { FONT, useTheme } from "@/theme";
import { useWords } from "@/lib/words";

export type GridUnit = { id: string; label: string };

// Sitenin daireleri eşit boyda büyük düğmeler halinde (ekrana göre sütun sayısı kendiliğinden). Birden çok blokta üstte blok seçimi:
// 2–4 blok yan yana sekme, 5 ve fazlası yana kaydırılan blok düğmeleri; seçilen bloğun daireleri altta.
// counts: düğmenin köşesinde küçük sayı (ör. bekleyen kargo)
export function UnitGrid({ siteId, onPick, counts }: { siteId: string; onPick: (u: GridUnit) => void; counts?: Record<string, number> }) {
  const w = useWords();
  const { colors } = useTheme();
  const [blocks, setBlocks] = useState<{ name: string; units: { id: string; no: string }[] }[]>([]);
  const [block, setBlock] = useState<string>("");
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    supabase
      .from("blocks")
      .select("name, units(id, no)")
      .eq("site_id", siteId)
      .order("name")
      .then(({ data }) => {
        const rows = ((data ?? []) as { name: string; units: { id: string; no: string }[] }[]).map((b) => ({
          name: b.name,
          units: [...b.units].sort((p, q) => p.no.localeCompare(q.no, "tr", { numeric: true })),
        }));
        setBlocks(rows);
        setBlock(rows[0]?.name ?? "");
        setLoaded(true);
      });
  }, [siteId]);

  if (loaded && blocks.length === 0) return <Muted>{`Bu sitede henüz ${w.nom} yok. Yönetici Kişiler › ${w.Plural} bölümünden ekler.`}</Muted>;
  const shown = blocks.length > 1 ? blocks.filter((b) => b.name === block) : blocks;

  return (
    <View style={{ gap: 14 }}>
      {blocks.length > 1 && <BlockPicker blocks={blocks.map((b) => b.name)} value={block} onChange={setBlock} />}
      {shown.map((b) => (
        <View key={b.name} style={{ gap: 14 }}>
          <Grid>
            {b.units.map((u) => {
              const label = `${b.name}-${u.no}`;
              const n = counts?.[u.id] ?? 0;
              return (
                <Pressable
                  key={u.id}
                  accessibilityRole="button"
                  accessibilityLabel={n ? `${label}, ${n} bekleyen` : label}
                  onPress={() => onPick({ id: u.id, label })}
                  style={({ pressed }) => ({ height: 60, borderRadius: 14, paddingHorizontal: 6, alignItems: "center", justifyContent: "center", backgroundColor: pressed ? colors.vurguAcik : colors.kutu })}
                >
                  <Text numberOfLines={1} adjustsFontSizeToFit minimumFontScale={0.7} style={{ fontFamily: FONT.kalin, fontSize: 17, color: colors.yazi, fontVariant: ["tabular-nums"] }}>
                    {label}
                  </Text>
                  {n > 0 && (
                    <View style={{ position: "absolute", top: 4, right: 4, minWidth: 20, height: 20, borderRadius: 10, paddingHorizontal: 5, backgroundColor: colors.vurgu, alignItems: "center", justifyContent: "center" }}>
                      <Text style={{ fontFamily: FONT.kalin, fontSize: 12, color: colors.vurguYazi }}>{n}</Text>
                    </View>
                  )}
                </Pressable>
              );
            })}
          </Grid>
        </View>
      ))}
    </View>
  );
}

// Blok seçimi: 2–4 blok yan yana sekme; 5 ve fazlasında yana kaydırılan düğmeler (seçili olan vurgu renginde)
export function BlockPicker({ blocks, value, onChange }: { blocks: string[]; value: string; onChange: (b: string) => void }) {
  const { colors } = useTheme();
  if (blocks.length <= 4) return <Segmented value={value} onChange={onChange} options={blocks.map((b) => ({ key: b, label: `${b} Blok` }))} />;
  return (
    <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 8, paddingRight: 8 }} style={{ marginHorizontal: -2, flexGrow: 0 }}>
      {blocks.map((b) => {
        const on = b === value;
        return (
          <Pressable
            key={b}
            accessibilityRole="tab"
            accessibilityState={{ selected: on }}
            onPress={() => onChange(b)}
            style={({ pressed }) => ({ minWidth: 76, height: 44, paddingHorizontal: 14, borderRadius: 22, alignItems: "center", justifyContent: "center", backgroundColor: on ? colors.vurgu : pressed ? colors.kutuKoyu : colors.kutu })}
          >
            <Text numberOfLines={1} style={{ fontFamily: on ? FONT.kalin : FONT.orta, fontSize: 15, color: on ? colors.vurguYazi : colors.yazi }}>{`${b} Blok`}</Text>
          </Pressable>
        );
      })}
    </ScrollView>
  );
}
