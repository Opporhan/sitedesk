import { useAuth } from "@/auth";

// Site türüne göre kelimeler: villa sitesinde "villa", apartmanda "daire" (Türkçe ekleriyle; ek elle eklenmez)
export type UnitWords = {
  nom: string; // daire / villa
  Nom: string; // Daire / Villa
  plural: string; // daireler
  Plural: string; // Daireler
  PluralAcc: string; // Daireleri
  acc: string; // daireyi
  dat: string; // daireye
  loc: string; // dairede
  poss: string; // (A-1) dairesi
  possGen: string; // (A-1) dairesinin
  mine: string; // Dairem
  yourDat: string; // dairenize
};

const DAIRE: UnitWords = { nom: "daire", Nom: "Daire", plural: "daireler", Plural: "Daireler", PluralAcc: "Daireleri", acc: "daireyi", dat: "daireye", loc: "dairede", poss: "dairesi", possGen: "dairesinin", mine: "Dairem", yourDat: "dairenize" };
const VILLA: UnitWords = { nom: "villa", Nom: "Villa", plural: "villalar", Plural: "Villalar", PluralAcc: "Villaları", acc: "villayı", dat: "villaya", loc: "villada", poss: "villası", possGen: "villasının", mine: "Villam", yourDat: "villanıza" };

export const unitWords = (siteType?: string | null): UnitWords => (siteType === "villa" ? VILLA : DAIRE);
export const unitTypeOf = (siteType?: string | null) => (siteType === "villa" ? "villa" : "daire");

// Açık role göre: görevli → sitenin türü; sakin → (ilk) sitesinin türü
export function useWords(): UnitWords {
  const { active, context } = useAuth();
  if (active.kind === "yonetici" || active.kind === "danisma") return unitWords(active.siteType);
  return unitWords(context?.units[0]?.site_type);
}
