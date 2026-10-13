# SiteDesk

**Türkçe** · [English](#english)

Apartman ve villa siteleri için ücretsiz bir telefon uygulaması: **sakin, danışma (güvenlik/resepsiyon) ve site yönetimi** arasında arıza-talep, kargo ve ziyaretçi takibi. Arayüz tamamen Türkçedir.

**Canlı tanıtım:** https://sitedesk-sooty.vercel.app
**Android uygulamasını indir:** [Releases](../../releases/latest) sayfasındaki `SiteDesk.apk` dosyası (Google Play'de değil; telefonda "bilinmeyen kaynaklardan yükleme" izni ister). Uygulamada **"Sitemi Ekle (Yönetici)"** ile kendi deneme sitenizi kurup yönetici olarak deneyebilirsiniz; kendi cep numaranızı kullanın (SMS ile doğrulanmaz). iPhone sürümü şu an yok.

## Ne yapar?

| Rol | Neler yapabilir |
|---|---|
| **Sakin** | Arıza, talep ya da şikâyet açar; en fazla 5 fotoğraf ya da 30 saniyelik video ekler; durumunu adım adım izler; iş bitince "çözüldü / devam ediyor" der. Kargosu danışmaya gelince ve kaydı güncellenince bildirim alır. |
| **Danışma** | Gelen kargoyu tek dokunuşla kaydeder, teslim eder, sakine hatırlatır. Ziyaretçi girişini (misafir ya da tamir/servis) ve çıkışını yazar. Sakin adına kayıt açar. |
| **Yönetici** | Bütün kayıtları tek listede görür (acil olanlar önde), cevap yazar, durum değiştirir. Sakinleri site koduyla, WhatsApp davetiyle ya da Excel/CSV/PDF listesinden toplu ekler. Birden çok siteyi tek ekrandan yönetir. |

## Öne çıkanlar

- **Yetki kuralları veritabanında:** "Kim neyi görür" kuralları uygulamada değil, PostgreSQL'in satır düzeyi güvenliğinde (RLS) ve yetkili fonksiyonlarda. Sakin sadece kendi dairesini, yeni taşınan sakin sadece kendi döneminin kayıtlarını görür; yönetici sakinlerin misafirlerini ve kargolarını göremez.
- **Otomatik güvenlik testleri:** 18 test dosyasında 227 kontrol. Genel güvenlik testi kuralları veritabanından okur: yeni eklenen bir tablo, testte karşılığı yazılmazsa test kendiliğinden kalır. Önemli değişiklikler ayrıca bağımsız bir yapay zekâ denetçisine incelettirildi.
- **Zayıf internette kayıp yok:** Kayıt ve fotoğraflar telefonda bir "giden kutusunda" bekler, bağlantı gelince kendiliğinden gönderilir; aynı kayıt iki kez oluşmaz.
- **Bildirimler:** Expo + Firebase üzerinden; veritabanı tetikleyicileri doğrudan gönderir.
- **SMS'siz giriş:** Telefon numarası + şifre; WhatsApp ile davet ya da site koduyla katılma ve yönetici onayı.
- **Kişisel veriye saygı:** Ziyaretçi kayıtları ve işlem geçmişi 1 yılda, tamamlanan kayıtların videoları 6 ayda kendiliğinden silinir; her gece şifreli (AES-256-GCM) yedek alınır.
- **Sıfır maliyet:** Supabase, Vercel, Expo ve Firebase'in ücretsiz planlarıyla çalışır.

## Teknoloji

| Katman | Kullanılan |
|---|---|
| Telefon uygulaması | Expo SDK 57, React Native, expo-router, TypeScript |
| Veritabanı ve giriş | Supabase: PostgreSQL, Auth, Storage, RLS, pg_cron, pg_net |
| Web sitesi ve sunucu işleri | Next.js (App Router), Tailwind CSS, Vercel (cron, Blob) |
| Bildirim | expo-notifications, Firebase Cloud Messaging |
| Derleme | EAS Build (Android APK/AAB) |

## Proje yapısı

```
mobil/                 Telefon uygulaması (Expo)
  src/app/             Ekranlar: sakin/, danisma/, yonetici/, platform/, kayit/, davet/ …
  src/components/      Ortak parçalar (liste, sayfa, davet, giden kutusu …)
  src/lib/             Bildirim, biçimlendirme, toplu liste okuma …
app/                   Web: tanıtım, gizlilik, destek, hesap silme sayfaları ve API yolları
lib/                   Sunucu tarafı: yedek, temizlik, sağlık raporu, Excel/PDF okuma
supabase/migrations/   Veritabanı (tablolar, kurallar, fonksiyonlar)
supabase/tests/        Yetki ve güvenlik testleri
scripts/               Veritabanı aracı, yedek, demo kurulumu
```

## Kendi bilgisayarınızda çalıştırma

1. Bir Supabase projesi açın; `.env.example` dosyasını `.env.local` olarak kopyalayıp değerleri doldurun.
2. `npm install` → `npm run db:migrate` (veritabanını kurar) → `npm run db:test` (testleri çalıştırır).
3. Demo sitesi ve deneme hesapları için: `node --env-file=.env.local scripts/demo-mobil.mjs` (şifreler `.env.local`'a yazılır). Kendinizi sistem yöneticisi yapmak için `supabase/sistem_yoneticisi.sql` içindeki e-postayı değiştirip `npm run db:run supabase/sistem_yoneticisi.sql`. Web sitesindeki gece işleri (yedek, temizlik) için ayrıca `CRON_SECRET`, `BACKUP_KEY`, `BLOB_READ_WRITE_TOKEN` gerekir.
4. Uygulama: `cd mobil && npm install`, `mobil/.env.local` içine `EXPO_PUBLIC_SUPABASE_URL`, `EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY`, `EXPO_PUBLIC_WEB_URL` yazın, sonra `npx expo start`. Bildirimler için APK derlemek gerekir (`eas build -p android --profile preview`).

## Nasıl geliştirildi?

Ürün fikri, iş kuralları ("kim neyi görür", sitelerdeki gerçek işleyiş) ve bütün kararlar bana ait. Kodun tamamı yapay zekâ (Claude Code) ile, adım adım ve her adımda benim onayımla yazıldı. Önemli değişiklikler, kodu yazandan bağımsız ikinci bir yapay zekâ denetçisine güvenlik, hata ve mimari açısından incelettirildi.

---

<a id="english"></a>

## English

A free mobile app for residential complexes in Turkey (apartment blocks and villa estates). It handles **maintenance requests, parcels and visitors** between **residents, the front desk (security/reception) and the management**. The UI is in Turkish.

**Live landing page:** https://sitedesk-sooty.vercel.app
**Download the Android app:** `SiteDesk.apk` on the [Releases](../../releases/latest) page (not on Google Play; Android will ask to allow installing from unknown sources). Use **"Sitemi Ekle (Yönetici)"** ("Add my site") in the app to create your own test site and try it as a manager. Sign-up expects a Turkish mobile number (05xx…), which is not verified by SMS — please use your own. There is no iPhone version yet.

### What it does

| Role | Capabilities |
|---|---|
| **Resident** | Opens a fault, request or complaint with up to 5 photos or a 30-second video, follows its status step by step, and marks it "solved / still a problem". Gets a push notification when a parcel arrives or a ticket is updated. |
| **Front desk** | Logs incoming parcels in one tap, hands them over, reminds the resident. Records visitor entries (guest or repair/service) and exits. Opens tickets on behalf of residents. |
| **Manager** | Sees all tickets in one list (urgent first), replies, changes status. Onboards residents via a site code, WhatsApp invites, or bulk import from an Excel/CSV/PDF list. Manages several sites from one screen. |

### Highlights

- **Authorization lives in the database:** who-sees-what is enforced by PostgreSQL row-level security and security-definer functions, not by the app. Residents only see their own unit; a new tenant doesn't see the previous tenant's tickets; managers can't see residents' guests or parcels.
- **Automated security tests:** 227 checks in 18 SQL test files. The generic security test reads its rules from the database catalog, so a new table without matching test data makes the suite fail. Significant changes were also reviewed by an independent AI reviewer.
- **Offline-tolerant:** tickets and photos wait in an on-device outbox and are sent when the connection returns; idempotent client IDs prevent duplicates.
- **Push notifications:** Expo + Firebase, sent straight from database triggers via pg_net.
- **No SMS:** phone number + password; onboarding via WhatsApp invite links or a site code with manager approval.
- **Privacy by default:** visitor logs and the audit log are deleted after 1 year, videos of closed tickets after 6 months; nightly encrypted (AES-256-GCM) backups.
- **Zero running cost:** runs on the free tiers of Supabase, Vercel, Expo and Firebase.

### Tech stack

| Layer | Technology |
|---|---|
| Mobile app | Expo SDK 57, React Native, expo-router, TypeScript |
| Database & auth | Supabase: PostgreSQL, Auth, Storage, RLS, pg_cron, pg_net |
| Website & server jobs | Next.js (App Router), Tailwind CSS, Vercel (cron, Blob) |
| Notifications | expo-notifications, Firebase Cloud Messaging |
| Builds | EAS Build (Android APK/AAB) |

### Running it locally

1. Create a Supabase project; copy `.env.example` to `.env.local` and fill in the values.
2. `npm install` → `npm run db:migrate` (sets up the database) → `npm run db:test` (runs the tests).
3. Demo site and test accounts: `node --env-file=.env.local scripts/demo-mobil.mjs` (passwords are written to `.env.local`). To make yourself platform admin, put your email in `supabase/sistem_yoneticisi.sql` and run `npm run db:run supabase/sistem_yoneticisi.sql`. The website's nightly jobs (backup, cleanup) also need `CRON_SECRET`, `BACKUP_KEY` and `BLOB_READ_WRITE_TOKEN`.
4. App: `cd mobil && npm install`, put `EXPO_PUBLIC_SUPABASE_URL`, `EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY` and `EXPO_PUBLIC_WEB_URL` in `mobil/.env.local`, then `npx expo start`. Push notifications need a development/APK build (`eas build -p android --profile preview`).

### How it was built

The product idea, the business rules (who sees what, how residential complexes actually operate) and every decision are mine. All of the code was written with an AI coding assistant (Claude Code), step by step, with my approval at each step. Significant changes were reviewed by a second, independent AI reviewer for security, bugs and architecture.

---

## Lisans / License

MIT — bkz. / see [LICENSE](LICENSE).
