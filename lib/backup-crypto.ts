import { createCipheriv, createDecipheriv, randomBytes } from "node:crypto";
import { gunzipSync, gzipSync } from "node:zlib";

// Yedek dosyası biçimi: "SDB1" + 12 bayt IV + 16 bayt doğrulama etiketi + AES-256-GCM ile şifrelenmiş gzip.
// Anahtar (BACKUP_KEY, 32 bayt, base64) olmadan dosya okunamaz; anahtar kaybolursa yedek açılamaz.
const MAGIC = Buffer.from("SDB1");

function keyOf(base64: string | undefined): Buffer {
  const key = Buffer.from(base64 ?? "", "base64");
  if (key.length !== 32) throw new Error("BACKUP_KEY tanımlı değil veya 32 bayt değil");
  return key;
}

export function encryptBackup(plain: Buffer, keyBase64: string | undefined): Buffer {
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", keyOf(keyBase64), iv);
  const body = Buffer.concat([cipher.update(gzipSync(plain)), cipher.final()]);
  return Buffer.concat([MAGIC, iv, cipher.getAuthTag(), body]);
}

export function decryptBackup(file: Buffer, keyBase64: string | undefined): Buffer {
  if (!file.subarray(0, 4).equals(MAGIC)) throw new Error("Bu bir SiteDesk yedek dosyası değil");
  const decipher = createDecipheriv("aes-256-gcm", keyOf(keyBase64), file.subarray(4, 16));
  decipher.setAuthTag(file.subarray(16, 32));
  return gunzipSync(Buffer.concat([decipher.update(file.subarray(32)), decipher.final()]));
}
