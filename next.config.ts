import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Günlük bulut yedeği tablo yapısını da içerir: migration dosyaları o adresle birlikte yayına girer
  outputFileTracingIncludes: {
    "/api/gorev/yedek": ["./supabase/migrations/*.sql"],
  },
};

export default nextConfig;
