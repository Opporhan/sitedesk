"use client";

import { useEffect } from "react";
import { RefreshCw, WifiOff } from "lucide-react";
import { Button } from "@/components/ui/button";

// Beklenmedik hata (çoğunlukla bağlantı): teknik İngilizce yazı yerine sade Türkçe sayfa
export default function ErrorPage({ error, retry }: { error: Error & { digest?: string }; retry: () => void }) {
  useEffect(() => {
    console.error(error);
  }, [error]);

  return (
    <main className="mx-auto flex w-full max-w-md flex-1 flex-col items-center justify-center gap-4 px-4 py-16 text-center">
      <WifiOff className="size-10 text-muted-foreground" aria-hidden />
      <h1 className="text-xl font-semibold">Şu an bağlantı kurulamıyor</h1>
      <p className="text-muted-foreground">
        Bilgileriniz güvende; yarım kalan bir kayıt oluşmaz. İnternet bağlantınızı kontrol edip birazdan tekrar deneyin.
      </p>
      <Button type="button" onClick={() => retry()} className="h-11 gap-2 px-4">
        <RefreshCw className="size-4" aria-hidden />
        Tekrar dene
      </Button>
      {error.digest && <p className="text-xs text-muted-foreground">Hata kodu: {error.digest}</p>}
    </main>
  );
}
