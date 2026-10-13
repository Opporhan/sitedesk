import { router } from "expo-router";

// "Bütün Sitelerim" her zaman ekran yığınının en altına konur: siteye girip geri gelince (geri tuşu, kaydırma) hep bu listeye dönülür,
// eski ekranlar birikmez ve rol değişse de döngü olmaz
export function openSitesList() {
  if (router.canDismiss()) router.dismissAll();
  router.replace("/siteler");
}
