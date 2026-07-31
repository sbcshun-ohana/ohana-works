"use client";

import { Suspense, useEffect, useState } from "react";
import Link from "next/link";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { roleDisplayName, type SessionIdentity } from "@/lib/types";

type OfficeOption = { office_id: string; office_name: string };

const NAV_ITEMS = [
  { href: "/attendance", label: "施設別勤怠" },
  { href: "/shifts", label: "シフト管理" },
  { href: "/employees", label: "職員マスタ" },
  { href: "/notices", label: "お知らせ" },
  { href: "/payroll", label: "給与確定" },
  { href: "/settings", label: "設定" },
  { href: "/feature-flags", label: "機能フラグ" },
];

// useSearchParams はビルド時の静的プリレンダーで Suspense 境界を要求するため、
// 内側を Suspense でラップする(下部の export function AppHeader)。
function AppHeaderInner() {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  // 保育業務メニューは機能フラグが有効な施設が1つでもある場合のみ表示する(既定OFF)。
  const [showChildcare, setShowChildcare] = useState(false);
  // ログイン中の氏名(役職)と、現在の操作対象施設を常時表示する(複数施設管理時の取り違え防止)。
  const [identity, setIdentity] = useState<SessionIdentity | null>(null);
  const [offices, setOffices] = useState<OfficeOption[]>([]);

  useEffect(() => {
    const supabase = createClient();
    supabase.rpc("fetch_my_childcare_offices").then(({ data, error }) => {
      const list = (data ?? []) as OfficeOption[];
      if (!error && list.length > 0) {
        setShowChildcare(true);
        setOffices(list);
      }
    });
    supabase.rpc("fetch_my_session_identity").then(({ data, error }) => {
      if (!error && Array.isArray(data) && data.length > 0) {
        setIdentity(data[0] as SessionIdentity);
      }
    });
  }, []);

  // 現在の操作対象施設: 画面の施設プルダウンが URL ?office= に同期しているのでそれを読む。
  // 施設選択が無い画面(?office= 無し)は所属施設をフォールバック表示する。
  const selectedOfficeId = searchParams.get("office");
  const currentOfficeName = selectedOfficeId
    ? offices.find((o) => o.office_id === selectedOfficeId)?.office_name ?? null
    : null;

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
      <div className="flex items-center gap-3">
        {identity && (
          <span className="text-sm text-slate-600">
            ログイン中: <span className="font-semibold text-slate-800">{identity.name}</span>
            <span className="text-slate-500">({roleDisplayName(identity.role_code)})</span>
            {currentOfficeName ? (
              <span className="ml-2 rounded-md bg-sky-50 px-2 py-0.5 text-xs font-semibold text-sky-700">
                施設: {currentOfficeName}
              </span>
            ) : (
              identity.home_office_name && (
                <span className="ml-2 rounded-md bg-slate-100 px-2 py-0.5 text-xs text-slate-500">
                  所属: {identity.home_office_name}
                </span>
              )
            )}
          </span>
        )}
        <button
          onClick={handleLogout}
          className="rounded-lg border border-slate-300 px-3 py-1.5 text-sm font-medium text-slate-600 transition hover:bg-slate-50"
        >
          ログアウト
        </button>
      </div>
    </header>
  );
}

export function AppHeader() {
  return (
    <Suspense
      fallback={
        <header className="flex items-center justify-between border-b border-slate-200 bg-white px-6 py-4">
          <h1 className="text-lg font-bold text-slate-800">Ohana Works 管理者Web</h1>
        </header>
      }
    >
      <AppHeaderInner />
    </Suspense>
  );
}
