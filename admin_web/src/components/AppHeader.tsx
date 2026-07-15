"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

const NAV_ITEMS = [
  { href: "/attendance", label: "施設別勤怠" },
  { href: "/employees", label: "職員マスタ" },
  { href: "/payroll", label: "給与確定" },
  { href: "/settings", label: "設定" },
];

export function AppHeader() {
  const router = useRouter();
  const pathname = usePathname();

  async function handleLogout() {
    const supabase = createClient();
    await supabase.auth.signOut();
    router.push("/login");
    router.refresh();
  }

  return (
    <header className="flex items-center justify-between border-b border-slate-200 bg-white px-6 py-4">
      <div className="flex items-center gap-6">
        <h1 className="text-lg font-bold text-slate-800">Ohana Works 管理者Web</h1>
        <nav className="flex gap-1">
          {NAV_ITEMS.map((item) => (
            <Link
              key={item.href}
              href={item.href}
              className={`rounded-lg px-3 py-1.5 text-sm font-medium transition ${
                pathname === item.href
                  ? "bg-sky-50 text-sky-700"
                  : "text-slate-500 hover:bg-slate-50"
              }`}
            >
              {item.label}
            </Link>
          ))}
        </nav>
      </div>
      <button
        onClick={handleLogout}
        className="rounded-lg border border-slate-300 px-3 py-1.5 text-sm font-medium text-slate-600 transition hover:bg-slate-50"
      >
        ログアウト
      </button>
    </header>
  );
}
