"use client";

import { useEffect, useState } from "react";
import { Check, Copy } from "lucide-react";

// Davet kodu: sayfa açılınca panoya kopyalanmaya çalışılır (uygulama ilk açılışta panodan okuyabilsin); düğmeyle de kopyalanır
export function CopyCode({ code }: { code: string }) {
  const [copied, setCopied] = useState(false);
  const copy = () =>
    navigator.clipboard
      ?.writeText(code)
      .then(() => setCopied(true))
      .catch(() => {});
  useEffect(() => {
    copy();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  return (
    <div className="flex flex-col items-center gap-3">
      <p className="font-mono text-3xl font-bold tracking-[0.3em]">{code}</p>
      <button
        type="button"
        onClick={copy}
        className="inline-flex h-11 items-center gap-2 rounded-lg border px-4 font-medium hover:bg-muted focus-visible:outline-none focus-visible:ring-3 focus-visible:ring-ring/50"
      >
        {copied ? <Check className="size-4" aria-hidden /> : <Copy className="size-4" aria-hidden />}
        {copied ? "Kopyalandı" : "Kodu kopyala"}
      </button>
    </div>
  );
}
