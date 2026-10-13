import { Alert, Linking, Platform } from "react-native";
import * as ImagePicker from "expo-image-picker";
import { ImageManipulator, SaveFormat } from "expo-image-manipulator";
import { File } from "expo-file-system";

// Seçilen / çekilen dosya (yüklemeden önce telefonda küçültülmüş)
export type PickedMedia = { uri: string; kind: "foto" | "video"; size: number; durationMs: number | null; mime: string; ext: string };

export const MAX_PHOTOS = 5;
export const MAX_VIDEO_SECONDS = 30;
const MAX_BYTES = 50 * 1024 * 1024; // depo sınırı

// İzin ilk gerektiği anda, nedenini söyleyen Türkçe cümleyle istenir; reddedildiyse Ayarlar'a yönlendirilir
export async function ensurePermission(kind: "kamera" | "galeri"): Promise<boolean> {
  // Android'de galeri için izin gerekmez: sistemin fotoğraf seçicisi kullanılır, uygulama sadece seçilen dosyayı görür
  // (Google Play geniş galeri iznini istemiyor).
  if (kind === "galeri" && Platform.OS === "android") return true;
  const current = kind === "kamera" ? await ImagePicker.getCameraPermissionsAsync() : await ImagePicker.getMediaLibraryPermissionsAsync();
  if (current.granted) return true;
  const why =
    kind === "kamera"
      ? "Arızanın fotoğrafını veya videosunu çekebilmeniz için SiteDesk'in kameraya erişmesi gerekiyor."
      : "Kayda fotoğraf veya video ekleyebilmeniz için SiteDesk'in galerinize erişmesi gerekiyor. Sadece seçtiğiniz dosyalar gönderilir.";
  if (!current.canAskAgain) {
    Alert.alert("İzin gerekiyor", `${why} Telefonun Ayarlar bölümünden izin verebilirsiniz.`, [
      { text: "Vazgeç", style: "cancel" },
      { text: "Ayarları aç", onPress: () => Linking.openSettings() },
    ]);
    return false;
  }
  const go = await new Promise<boolean>((resolve) =>
    Alert.alert(kind === "kamera" ? "Kamera izni" : "Galeri izni", why, [
      { text: "Vazgeç", style: "cancel", onPress: () => resolve(false) },
      { text: "Devam", onPress: () => resolve(true) },
    ])
  );
  if (!go) return false;
  const asked = kind === "kamera" ? await ImagePicker.requestCameraPermissionsAsync() : await ImagePicker.requestMediaLibraryPermissionsAsync();
  return asked.granted;
}

// Fotoğraf: uzun kenar en fazla 1600 px, JPEG, sıkıştırılmış
async function shrinkPhoto(asset: ImagePicker.ImagePickerAsset): Promise<PickedMedia> {
  const longest = Math.max(asset.width || 0, asset.height || 0);
  const ctx = ImageManipulator.manipulate(asset.uri);
  if (longest > 1600) ctx.resize(asset.width >= asset.height ? { width: 1600 } : { height: 1600 });
  const rendered = await ctx.renderAsync();
  const saved = await rendered.saveAsync({ compress: 0.7, format: SaveFormat.JPEG });
  return { uri: saved.uri, kind: "foto", size: new File(saved.uri).size || 0, durationMs: null, mime: "image/jpeg", ext: "jpg" };
}

// Video: en fazla 30 sn, iPhone'da orta kalitede kaydedilir/dışa aktarılır (gerçek sıkıştırma deneme sürümünde eklenecek)
function checkVideo(asset: ImagePicker.ImagePickerAsset): PickedMedia | string {
  const ms = asset.duration ?? 0;
  if (ms > (MAX_VIDEO_SECONDS + 0.5) * 1000) return `Video en fazla ${MAX_VIDEO_SECONDS} saniye olabilir (seçtiğiniz ${Math.round(ms / 1000)} saniye). Daha kısa bir video seçin.`;
  const size = asset.fileSize ?? (new File(asset.uri).size || 0);
  if (size > MAX_BYTES) return "Video çok büyük (50 MB'tan fazla). Daha kısa bir video çekin.";
  const mov = (asset.mimeType ?? "").includes("quicktime") || asset.uri.toLowerCase().endsWith(".mov");
  return { uri: asset.uri, kind: "video", size, durationMs: ms || null, mime: mov ? "video/quicktime" : "video/mp4", ext: mov ? "mov" : "mp4" };
}

// Kameradan fotoğraf ya da video çek
export async function captureMedia(kind: "foto" | "video"): Promise<PickedMedia | string | null> {
  if (!(await ensurePermission("kamera"))) return null;
  const result = await ImagePicker.launchCameraAsync(
    kind === "foto"
      ? { mediaTypes: ["images"], quality: 0.8 }
      : { mediaTypes: ["videos"], videoMaxDuration: MAX_VIDEO_SECONDS, videoQuality: ImagePicker.UIImagePickerControllerQualityType.Medium }
  );
  if (result.canceled || !result.assets[0]) return null;
  return kind === "foto" ? shrinkPhoto(result.assets[0]) : checkVideo(result.assets[0]);
}

// Galeriden seç: birden çok fotoğraf ya da tek video
export async function pickFromLibrary(photoSlots: number, allowVideo: boolean): Promise<PickedMedia[] | string | null> {
  if (!(await ensurePermission("galeri"))) return null;
  const result = await ImagePicker.launchImageLibraryAsync({
    mediaTypes: allowVideo ? ["images", "videos"] : ["images"],
    allowsMultipleSelection: photoSlots > 1,
    selectionLimit: Math.max(1, photoSlots),
    quality: 0.8,
    videoExportPreset: ImagePicker.VideoExportPreset.MediumQuality,
  });
  if (result.canceled || !result.assets.length) return null;
  const videos = result.assets.filter((a) => a.type === "video");
  const photos = result.assets.filter((a) => a.type !== "video");
  if (videos.length && (photos.length || videos.length > 1)) return "En fazla 5 fotoğraf ya da 1 video ekleyebilirsiniz; ikisi birlikte olmaz.";
  if (videos.length) {
    const v = checkVideo(videos[0]);
    return typeof v === "string" ? v : [v];
  }
  return Promise.all(photos.slice(0, photoSlots).map(shrinkPhoto));
}

// Profil resmi: kameradan ya da galeriden, telefonun kendi kırpma ekranıyla KARE seçilir; 512 px JPEG'e küçültülür
export async function pickAvatar(source: "kamera" | "galeri"): Promise<string | null> {
  if (!(await ensurePermission(source))) return null;
  const options: ImagePicker.ImagePickerOptions = { mediaTypes: ["images"], allowsEditing: true, aspect: [1, 1], quality: 0.9 };
  const result = source === "kamera" ? await ImagePicker.launchCameraAsync(options) : await ImagePicker.launchImageLibraryAsync(options);
  if (result.canceled || !result.assets[0]) return null;
  const a = result.assets[0];
  // Kırpma ekranı olmayan durumlarda da kare olsun: ortadan kare kesilir
  const side = Math.min(a.width || 0, a.height || 0);
  const ctx = ImageManipulator.manipulate(a.uri);
  if (side && a.width !== a.height) ctx.crop({ originX: Math.round((a.width - side) / 2), originY: Math.round((a.height - side) / 2), width: side, height: side });
  ctx.resize({ width: 512, height: 512 });
  const saved = await (await ctx.renderAsync()).saveAsync({ compress: 0.75, format: SaveFormat.JPEG });
  return saved.uri;
}
