@AGENTS.md

# SiteDesk

Villa ve apartman siteleri için **telefon uygulaması** (Expo / React Native, klasör `mobil/`, kendi kuralları `mobil/AGENTS.md`) ve küçük bir **web sitesi** (Next.js, Vercel). Konu: sakin – danışma – yönetim arasında **arıza/talep/şikâyet, kargo ve ziyaretçi** takibi. Arayüz tamamen Türkçedir.

- **Uygulama tamamen ücretsiz** (kullanıcı kararı 12.10.2026): para işi yok — aidat, ödeme, kasa, bütçe, fiyat, deneme süresi, uygulama içi satın alma eklenmez.
- Giriş: herkes **telefon + şifre** (SMS yok; telefon numarası doğrulanmaz). Sistem yöneticisi e-postayla da girer.
- Önce **Android** (Google Play), iPhone sonra. Mağazaya yükleme kullanıcının Play Console hesabını bekliyor.
- Gerçek siteye dokunulmaz; her şey demo sitelerinde denenir.
- 06.10.2026'da sıfırdan başlandı; eski web sürümü git etiketi **`eski-surum-2026-10-06`** (yeniden kullanmadan önce kullanıcıya sor).

---

## 1. Kullanıcıyla çalışma kuralları (EN ÖNEMLİ)

Kullanıcı kod bilmiyor. Bu kurallar her şeyin önündedir:

- **Türkçe ve kısa anlat.** Teknik terim gerekiyorsa bir cümleyle ne olduğunu açıkla.
- **Sadece istenen adımı yap.** Bitince dur. Sonraki adıma kendiliğinden geçme, "şunu da yaptım" deme.
- **Emin değilsen tahmin etme, sor.** Özellikle iş kuralları (para, yetki, kim neyi görür) konusunda asla varsayım yapma. Soruyu seçenekli ve sade sor.
- **GitHub'a / uzak sunucuya hiçbir şey gönderme.** `git push`, `git remote add`, `gh` komutları YASAK. Sadece yerel git.
  - **GitHub istisnası (kullanıcı kararı, 13.10.2026; kâr amacı yok, portföy):** proje herkese açık **`github.com/Opporhan/sitedesk`** deposunda (MIT lisansı) ve Android APK'sı oradaki Releases'te. Gönderim SADECE geçmişi temiz kopyadan yapılır: `~/Desktop/SiteDesk-github` (bu klasörün eski geçmişinde kişisel bilgi var, ASLA gönderilmez; `.claude/` ve `skills-lock.json` da gönderilmez). Her gönderim ve yeni sürüm (release) öncesi kullanıcıya sorulur.
  - **Vercel istisnası (kullanıcı onayı, 01.10.2026):** web sitesi **Vercel CLI ile doğrudan Vercel'e** yayınlanır. Gönderilmeyenler `.vercelignore`'da (`.env*`, `scripts`, `supabase`…). Vercel'deki ortam değişkenleri: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_SECRET_KEY`, `CRON_SECRET`, `BACKUP_KEY`, `BLOB_READ_WRITE_TOKEN`; `SUPABASE_ACCESS_TOKEN` asla girmez. `BACKUP_KEY` hiçbir yere (git, log, rapor) yazılmaz. Canlıya alma **her seferinde kullanıcının onayıyla** yapılır (aşağıdaki "Önce sor" kuralı).
- **Önce sor (kullanıcı kararı, 02.10.2026; her zaman geçerli):** Veritabanında değişiklik yapmadan (migration uygulamak, kalıcı veri yazan/silen komut çalıştırmak) ve canlıya almadan (Vercel) **önce kullanıcıya sor**: ne değişecek ve geri alınabilir mi, **tek cümleyle** söyle; **onayı bekle**. Onay gelmeden uygulama. Kendini geri alan testler (`npm run db:test`) ve sadece okuyan sorgular bu kuralın dışındadır. Bir onay sadece sorulan değişiklik için geçerlidir.
- **Her adım bitince:**
  1. Türkçe **5 maddelik özet** yaz (ne yapıldı, nasıl denenir, varsa dikkat edilecek şey).
  2. Yerel **commit** at. Commit mesajı Türkçe ve kısa: `geri tuşu: siteden Bütün Sitelerim ekranına döner` gibi.
- **Bağımsız denetim (kullanıcı kararı, 12.10.2026; her zaman geçerli):** her kod değişikliğinden sonra (uygulama, web, migration, test, betik) **kendiliğinden** bağımsız bir alt ajan (subagent) başlatılır. Alt ajan kodu yazmaz, sadece inceler: değişen dosyaları ve `git diff`'i **güvenlik, hata ve mimari** açıdan denetler ve açıkça "ONAY" ya da "RET + bulgular" der. Sıra: kodu yaz → testler → alt ajan denetimi → bulgu varsa düzelt ve yeniden denetlet → **ONAY gelince** commit, canlıya alma ve özet. Alt ajan onay vermeden görev tamamlandı sayılmaz; özette denetim sonucu da yazılır. Sadece belge/metin değişikliklerinde (ör. CLAUDE.md) gerekmez.
- Bir şey çalışmıyorsa veya test başarısızsa bunu açıkça söyle, gizleme.
- **Yeni paket eklemeden önce de sor (kullanıcı kararı, 02.10.2026):** paketi kurmadan (`npm install`) önce **neden gerektiğini** söyle ve **onayı bekle**; "önce kurup sonra onaya sunmak" yok. Projeye eklenmeyen geçici deneme araçları da (ör. `npm i --no-save`) önceden söylenir.

---

## 2. Teknoloji

| Katman | Seçim | Not |
|---|---|---|
| Telefon uygulaması | Expo SDK 57, React Native, expo-router (yazılı rotalar), TypeScript | `mobil/src/app/` ekranlar; paket kurmak `npx expo install`; `mobil/.npmrc` `legacy-peer-deps=true` (EAS derlemesi için şart) |
| Derleme | EAS (Expo hesabı `orhan2`, paket `com.sitedesk.app`) | `mobil/eas.json`: `preview` = APK (deneme), `production` = AAB (mağaza). `npx --yes eas-cli@latest build -p android --profile preview --non-interactive --no-wait` |
| Bildirim | expo-notifications + Firebase (FCM, proje `sitedesk-cb068`, `mobil/google-services.json`) | Veritabanı `pg_net` ile Expo'ya gönderir (`notify_users`); Expo Go'da Android bildirimi yok → APK ile denenir |
| Web | Next.js (App Router, sadece sayfalar + API yolları; Server Action yok) + Tailwind | Renkler `app/globals.css`'te tek tema (bej); tek shadcn bileşeni `components/ui/button.tsx`; ikon lucide |
| Veritabanı + Giriş | Supabase (Postgres, Auth, RLS, Storage, pg_cron, pg_net) | Uygulama doğrudan `@supabase/supabase-js` (herkese açık anahtar + kullanıcı oturumu); web sunucusu gizli anahtarla (`lib/supabase/admin.ts`) |
| Yayın | Vercel (CLI, GitHub yok, bölge `fra1`) | `npx vercel@latest deploy --prod --yes` — her seferinde kullanıcı onayıyla; bazen bir kez hata verir, tekrar denenir |

- **Sıfır maliyet kuralı:** ücretli servis kullanılmaz (Supabase/Vercel/Expo/Firebase ücretsiz planları); gerekirse önce kullanıcıya sor.
- Uygulamada gizli anahtar olmaz; `mobil/.env.local` ve `eas.json` sadece herkese açık değerler.

---

## 3. Şu anki yapı

### Roller ve kim neyi görür (hepsi veritabanında, RLS ve fonksiyonlarla)
- **Sakin:** sadece kendi dairesi/villası; kayıt, kargo ve ziyaretçide **taşındığı günden sonrakiler** (`resident_can_see`; ziyaretçide son 30 gün, dairede kiracı varken malik ziyaretçiyi görmez). Komşunun profilini/telefonunu göremez.
- **Danışma:** sitenin kayıtları, kargo, ziyaretçi (misafir + hizmet), sakinlerin adı/telefonu. Davet edemez, davetleri görmez.
- **Yönetici:** sitenin kayıtları, kişiler, davetler; ziyaretçide **sadece hizmet** (tamir/servis) girişleri; **kargo ve sakinlerin misafirlerini görmez**. Başka yönetici davet eder/çıkarır; kendisini ve **kurucu yöneticiyi** (`sites.created_by`) çıkaramaz.
- **Sistem yöneticisi** (`platform_admins`, kullanıcı): her sitede yönetici yetkisinde (kargo hariç), siteleri açar/kapatır (`active`), "yönetici gözüyle bak". Kapalı sitede kimse (sistem yöneticisi hariç) bir şey göremez.
- Uygulama işlem geçmişini (`audit_log`) okuyamaz; geçmişe davet kodu yazılmaz, kargo/ziyaretçi yazılmaz, 1 yılda silinir.

### Hesap ve siteye katılma
- **Davetle:** yönetici sakini/danışmayı/yöneticiyi davet eder (`create_invite`, 7 gün; toplu davet `create_invites_bulk` 30 gün) → WhatsApp'tan bağlantı + 8 haneli kod → uygulamada "Davet veya Şifre Kodum Var" → `/api/davet` hesabı açar → kişi kendi oturumuyla `accept_invite`. Sakin daveti açılınca kişi rehbere "uygulamada değil" olarak girer.
- **Kendi kaydıyla:** "Siteme Katıl (Sakin)" / "Sitemi Ekle (Yönetici)" → `/api/kayit` (aynı internet adresinden saatte en fazla 20; adresin gizli anahtarlı özeti 1 gün, `allow_signup`). Herkes site açabilir (`create_site`, günde 3, açan kurucu yönetici olur). Sakin 6 haneli site koduyla (`sites.join_code`) katılma isteği gönderir (`request_join`), yönetici onaylar (`decide_join`). **Rehberde (davet edilmiş) numara site koduyla katılamaz** (`SD063`), davetle girer.
- **Numara kapma:** SMS olmadığı için biri başkasının numarasıyla önceden hesap açabilir; gerçek kişi davet gelince "hesabınız var" hatası alır. Otomatik geri alma YOK (kötüye kullanılabiliyordu, denetim 13.10.2026); böyle bir durumda hesabı sistem yöneticisi elle düzeltir.
- **Şifre yenileme:** yönetici (sakin/danışma için) ya da sistem yöneticisi (yönetici için) kod açar (`create_password_reset`, 24 saat) → `/api/sifre` → kişinin bütün oturumları kapanır (açık erişim anahtarı en geç 1 saatte düşer), "Şifreniz yenilendi" bildirimi gider ve eski telefonların bildirim kaydı silinir (`password_changed`). Herhangi bir sitede yönetici olanın şifresini sadece sistem yöneticisi yeniler.
- Hesap silme: uygulamada Profil › Hesabımı Sil ya da web `/hesap-sil` (`/api/hesap-sil`; sistem yöneticisi silinemez).

### Veritabanı (migration'lar `supabase/migrations/`, en günceli en son dosya)
Başlıca tablolar: `sites` (`type`, `active`, `is_demo`, `join_code`, `created_by`, `video_keep_months`), `blocks`, `units`, `residents` (sakin rehberi, telefon sitede tek), `unit_residents` (`relation` malik/kiraci, `started_on`, `ended_on`), `memberships` (yonetici/danisma), `invites` (rol sakin/danisma/yonetici/sifre, `sent_at`), `join_requests`, `profiles` (ad, telefon, `avatar_path`), `tickets` (tür ariza/talep/sikayet, yer daire/ortak, acil, durum alindi→inceleniyor→yapiliyor→tamamlandi, `client_id`), `ticket_events`, `ticket_media` (en fazla 5 foto ya da 1 video ≤30 sn), `packages`, `visitors` (`kind` misafir/hizmet), `push_tokens`, `audit_log`, `signup_attempts`, `platform_admins`.
- Dosya depoları (hepsi kapalı): `kayitlar` (`{site}/{kayıt}/…`, 10 dk bağlantı), `profil` (`{user}/…`), `listeler` (toplu davet dosyası, okununca silinir).
- Zamanlanmış işler (pg_cron): `ziyaretci-temizlik` (1 yıldan eski ziyaretçi), `gecmis-temizlik` (1 yıldan eski işlem geçmişi).
- **Testler** `supabase/tests/*.sql` (`npm run db:test`; her dosya sonunda her şeyi geri alır). `guvenlik_testi` genel kuralları veritabanından okur: **yeni tablo eklenince o tabloya testte bir "kurban" satırı ve gerekirse izin listesine kaydı eklenmezse test KALIR.** Yeni iş kuralı = yeni test.

### Telefon uygulaması (`mobil/src`)
- `app/index.tsx` kapı (giriş → kilit → role göre). Roller: `sakin/` (Kayıtlarım · Kargo · Profil), `danisma/` (Kargo · Ziyaretçi · Arıza · Profil), `yonetici/` (Kayıtlar · Hizmet · Kişiler · Profil; Kişiler: Davet/Sakinler/Görevliler/Daireler), `platform/` (Siteler · Profil; `site-yonetimi/[id]`). Birden çok site yöneten açılışta `siteler.tsx` (Bütün Sitelerim) görür; bu liste hep ekran yığınının altındadır (`lib/nav.ts`).
- Ortak: `components/ui.tsx`, `theme.tsx`, `lib/words.ts` (villa/daire kelimeleri), `outbox.tsx` + `components/outbox-list.tsx` (zayıf internette giden kutusu, hesaba bağlı), `lib/push.ts` (Profil › Bildirimler), `components/lock-screen.tsx` (parmak izi; 5 dk arka planda kalınca tekrar).
- **Düğme yazıları Baş Harfleri Büyük** (kullanıcı kararı 13.10.2026): "Giriş Yap", "Teslim Et", "Siteme Katıl (Sakin)"; bağlaçlar küçük ("Davet veya Şifre Kodum Var").
- Deneme: APK derlenir (Expo Go'da bildirim yok). Demo hesapları (şifreler kodda yazmaz, sadece `.env.local` `DEMO_*_SIFRE`; `scripts/demo-mobil.mjs` yoksa rastgele üretir): yönetici 0500 000 01 01, danışma …01 02, sakin A-1 …01 03. Demo siteleri: Demo Sitesi, Demo Villa Sitesi, Demo Rezidans (`scripts/demo-mobil.mjs`, `scripts/demo-siteler.mjs`). Demo hesaplarında "Hesabımı Sil"e basılmaz.

### Web (`app/`, Vercel: https://sitedesk-sooty.vercel.app)
- Sayfalar: `/tanitim` (ana sayfa; ekranlar `components/app-mockups.tsx` ile çizilir), `/gizlilik` (KVKK, TASLAK), `/destek`, `/hesap-sil`, `/magaza` (sadece kullanıcı için, arama motorlarına kapalı), `/davet/<anahtar>`. Geliştirici adı/e-posta/il/adres `lib/legal.ts` (boşken [köşeli parantez], `reviewed:false` iken "Taslak").
- API: `/api/davet`, `/api/kayit`, `/api/sifre`, `/api/hesap-sil`, `/api/liste-oku` (Excel/CSV/PDF → metin, `lib/sheet-text.ts`), `/api/durum`.
- Gece işleri (Vercel Cron, `CRON_SECRET`): `/api/gorev/yedek` 01:00 UTC (şifreli bulut yedeği, Vercel Blob, 14 gün; deneme `node --env-file=.env.local scripts/cloud-restore-test.mjs`), `/api/gorev/temizlik` 02:00 (video saklama süresi, sahipsiz dosyalar), `/api/gorev/saglik` 05:00 (sorun varsa sistem yöneticisine bildirim).

---

## 4. Geliştirme kuralları

- Veritabanı değişiklikleri **sadece migration dosyasıyla**; önce kuru deneme (migration + testler tek işlemde, geri alınır), sonra kullanıcı onayıyla `npm run db:migrate`, ardından `npm run db:test`. Salt okuyan sorgu serbest.
- Commit öncesi: web `npm run lint` + `npm run build`; uygulama `cd mobil && npx tsc --noEmit` (mobilde `npm run lint` dosyaları yok sayıyor, güvenilmez).
- Yedek: `npm run yedek` (`scripts/backup.mjs`, iCloud Drive › SiteDesk Yedekler; Mac'te haftalık otomatik; şifresiz — Mac'te kalır).
- `.env.local` git'e girmez. Yorum az ve Türkçe; kod isimleri İngilizce, adresler Türkçe.
- Tasarım: mobil öncelikli, dokunma alanı en az 44px, kontrast en az 4.5:1, boş durum mesajı, emoji ikon yok.

---

## 5. Biçimlendirme (Türkçe)

- Tarih/saat her zaman **Türkiye saatiyle** (`Europe/Istanbul`): uygulamada `mobil/src/lib/format.ts` (`todayTR`, `monthStartTR`), `mobil/src/lib/uuid.ts` (`formatTime`, `isTodayTR`), `mobil/src/lib/tickets.ts` (`formatDateTime`). Tarih `30.09.2026`, tarih-saat `30.09.2026 14:05`. Kütüphane eklenmez, `Intl` kullanılır.
- Sayı kolonlarında `tabular-nums` (web) / `fontVariant: ["tabular-nums"]` (uygulama).
- Bütün metinler Türkçe ve doğru karakterle (ş, ğ, ı, İ, ç, ö, ü). Büyük harfe çevirirken `toLocaleUpperCase("tr-TR")`; plaka ve kod gibi ASCII alanlarda `toUpperCase()`.
- Beklenmedik hatada (çoğunlukla bağlantı) İngilizce teknik yazı gösterilmez: uygulamada `NETWORK_ERROR`, web'de `app/error.tsx` ("Şu an bağlantı kurulamıyor… Bilgileriniz güvende" + Tekrar dene).
