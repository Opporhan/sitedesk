import "server-only";
import { createClient } from "@supabase/supabase-js";

// Gizli anahtarla çalışır, bütün güvenlik kurallarını atlar.
// SADECE sunucuda ve sadece gerekli işlerde (davet göndermek gibi) kullan.
export function createAdminClient() {
  return createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.SUPABASE_SECRET_KEY!, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}
