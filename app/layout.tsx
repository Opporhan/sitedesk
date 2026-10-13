import type { Metadata, Viewport } from "next";
import { Inter } from "next/font/google";
import "./globals.css";

const inter = Inter({
  variable: "--font-sans",
  subsets: ["latin", "latin-ext"],
});

export const metadata: Metadata = {
  title: "SiteDesk",
  description: "Site sakinleri, danışma ve yönetim için arıza, talep, kargo ve ziyaretçi takibi.",
};

export const viewport: Viewport = {
  themeColor: "#0f6e66", // vurgu rengi (app/globals.css --vurgu)
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="tr" data-theme="bej" className={`${inter.variable} h-full antialiased`}>
      {/* Tarayıcı eklentileri <body>'ye stil ekleyebiliyor; sadece bu etiketin özellik farkını yok say */}
      <body className="min-h-full flex flex-col" suppressHydrationWarning>
        {children}
      </body>
    </html>
  );
}
