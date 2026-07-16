"use client";

import { useEffect, useState } from "react";
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
  // 保育業務メニューは機能フラグが有効な施設が1つでもある場合のみ表示する(既定OFF)。
  const [showChildcare, setShowChildcare] = useState(false);

  useEffect(() => {
    const supabase = createClient();
    supabase.rpc("fetch_my_childcare_offices").then(({ data, error }) => {
      if (!error && (data ?? []).length > 0) {
        setShowChildcare(true);
      }
    });
  }, []);

  const navItems = showChildcare
    ? [...NAV_ITEMS, { href: "/childcare/attendance", label: "保育業務" }]
    : NAV_ITEMS;

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
          {navItems.map((item) => {
            const isActive = item.href === "/childcare/attendance"
              ? pathname.startsWith("/childcare")
              : pathname === item.href;
            return (
              <Link
                key={item.href}
                href={item.href}
                className={`rounded-lg px-3 py-1.5 text-sm font-medium transition ${
                  isActive ? "bg-sky-50 text-sky-700" : "text-slate-500 hover:bg-slate-50"
                }`}
              >
                {item.label}
              </Link>
            );
          })}
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
