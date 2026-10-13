import { NextResponse, type NextRequest } from "next/server";

// Web'de sadece: tanıtım ("Yakında"), davet bağlantısı (/davet/…) ve sunucu adresleri (/api/…). Giriş yok (uygulama telefonda).
export function proxy(request: NextRequest) {
  if (request.nextUrl.pathname === "/") {
    const url = request.nextUrl.clone();
    url.pathname = "/tanitim";
    return NextResponse.rewrite(url);
  }
  return NextResponse.next();
}

export const config = { matcher: ["/"] };
