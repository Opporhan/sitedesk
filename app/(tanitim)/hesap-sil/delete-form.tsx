"use client";

import { useState } from "react";
import { createClient } from "@supabase/supabase-js";
import { Button } from "@/components/ui/button";

// "0532 123 45 67" → "905321234567" (uygulamadaki ve veritabanındaki kuralla aynı)
function normalizePhone(input: string): string | null {
  const d = input.replace(/\D/g, "");
  if (/^5\d{9}$/.test(d)) return `90${d}`;
  if (/^0\d{10}$/.test(d)) return `9${d}`;
  if (/^90\d{10}$/.test(d)) return d;
  return null;
}

export function DeleteAccountForm() {
  const [phone, setPhone] = useState("");
  const [password, setPassword] = useState("");
  const [sure, setSure] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    const p = normalizePhone(phone);
    if (!p) return setError("Telefon numaranızı 0532 123 45 67 gibi yazın.");
    if (!password) return setError("Şifrenizi yazın.");
    if (!sure) return setError("Silme işlemini onaylayın.");
    setBusy(true);
    try {
      // Oturum tarayıcıda saklanmaz; sadece bu işlem için açılır
      const supabase = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!, { auth: { persistSession: false } });
      const { data, error: loginError } = await supabase.auth.signInWithPassword({ email: `tel-${p}@sitedesk.invalid`, password });
      if (loginError || !data.session) return setError(loginError?.code === "invalid_credentials" ? "Telefon numarası veya şifre hatalı." : "Giriş yapılamadı. Lütfen tekrar deneyin.");
      const res = await fetch("/api/hesap-sil", { method: "POST", headers: { Authorization: `Bearer ${data.session.access_token}` } });
      const body = (await res.json().catch(() => ({}))) as { error?: string };
      if (!res.ok) return setError(body.error ?? "Hesap silinemedi. Lütfen tekrar deneyin.");
      setDone(true);
    } catch {
      setError("Bağlantı kurulamadı. İnternetinizi kontrol edip tekrar deneyin.");
    } finally {
      setBusy(false);
    }
  }

  if (done)
    return (
      <div className="rounded-xl bg-odendi-zemin p-4 text-odendi">
        <strong>Hesabınız silindi.</strong> Uygulama telefonunuzda yüklüyse onu da kaldırabilirsiniz.
      </div>
    );

  const input = "h-12 w-full rounded-lg border border-input bg-card px-3 text-base outline-none focus-visible:ring-3 focus-visible:ring-ring/50";
  return (
    <form onSubmit={submit} className="flex flex-col gap-4 rounded-2xl border border-border bg-card p-5">
      <label className="flex flex-col gap-1.5">
        <span className="font-medium">Telefon numaranız</span>
        <input className={input} value={phone} onChange={(e) => setPhone(e.target.value)} inputMode="tel" autoComplete="tel" placeholder="0532 123 45 67" />
      </label>
      <label className="flex flex-col gap-1.5">
        <span className="font-medium">Şifreniz</span>
        <input className={input} type="password" value={password} onChange={(e) => setPassword(e.target.value)} autoComplete="current-password" />
      </label>
      <label className="flex items-start gap-3">
        <input type="checkbox" className="mt-1 size-5" checked={sure} onChange={(e) => setSure(e.target.checked)} />
        <span>Hesabımın kalıcı olarak silineceğini ve bu işlemin geri alınamayacağını anladım.</span>
      </label>
      {error && (
        <p role="alert" className="rounded-lg bg-borc-zemin p-3 text-borc">
          {error}
        </p>
      )}
      <Button type="submit" variant="destructive" size="lg" disabled={busy} className="h-12 text-base">
        {busy ? "Siliniyor…" : "Hesabımı kalıcı olarak sil"}
      </Button>
    </form>
  );
}
