// Yasal metinlerdeki ve mağaza sayfasındaki bilgiler (tek yer). Boş alanlar sayfada [köşeli parantez] ile görünür.
// UYARI: Metinler TASLAKTIR; yayına almadan önce kullanıcı ve bir hukukçu tarafından gözden geçirilmelidir.
export const LEGAL = {
  owner: "", // Geliştirici / şirket: ad soyad ya da ticari unvan (mağazada da görünür)
  city: "", // İl
  address: "", // Tebligat adresi
  email: "", // Destek ve KVKK başvuruları için e-posta
  updated: "13.10.2026",
  reviewed: false, // hukukçu incelemesinden sonra true yapılır; false iken sayfada "Taslak" uyarısı görünür
};

export const blank = (value: string, label: string) => value || `[${label}]`;
export const WEB = "https://sitedesk-sooty.vercel.app";
// Android uygulaması GitHub'daki son sürümden indirilir (Google Play'de değil; kullanıcı kararı 13.10.2026)
export const APK_URL = "https://github.com/Opporhan/sitedesk/releases/latest/download/SiteDesk.apk";
