// Mağaza hazırlık sayfasındaki (/magaza, sadece iç kullanım) geliştirici bilgileri; boş alanlar orada [köşeli parantez] görünür. Herkese açık sayfalarda iletişim GitHub (CONTACT_URL).
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
// İletişim: kişisel e-posta/adres yok; herkes GitHub üzerinden yazar (kullanıcı kararı 13.10.2026)
export const CONTACT_URL = "https://github.com/Opporhan/sitedesk/issues";
export const APK_URL = "https://github.com/Opporhan/sitedesk/releases/latest/download/SiteDesk.apk";
