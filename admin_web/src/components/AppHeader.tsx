"use client";

import { Suspense, useEffect, useState } from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";
import { roleDisplayName, type SessionIdentity } from "@/lib/types";

const NAV_ITEMS = [
  { href: "/attendance", label: "施設別勤怠" },
  { href: "/shifts", label: "シフト管理" },
  { href: "/employees", label: "職員マスタ" },
  { href: "/notices", label: "お知らせ(職員向け)" },
  { href: "/payroll", label: "給与確定" },
  { href: "/settings", label: "設定" },
  { href: "/feature-flags", label: "機能フラグ" },
];

// useSearchParams はビルド時の静的プリレンダーで Suspense 境界を要求するため、
// 内側を Suspense でラップする(下部の export function AppHeader)。
function AppHeaderInner() {
  const router = useRouter();
  const pathname = usePathname();
  // 保育業務系ページの施設選択はヘッダーに集約する。選択は useChildcareOffices の
  // ?office= 機構(URL同期)を駆動し、各ページの selectedOffice へ伝播する。
  const { offices, selectedOffice, setSelectedOffice } = useChildcareOffices();
  // ログイン中の氏名(役職)を常時表示する(複数施設管理時の取り違え防止)。
  const [identity, setIdentity] = useState<SessionIdentity | null>(null);

  useEffect(() => {
    const supabase = createClient();
    supabase.rpc("fetch_my_session_identity").then(({ data, error }) => {
      if (!error && Array.isArray(data) && data.length > 0) {
        setIdentity(data[0] as SessionIdentity);
      }
    });
  }, []);

  // 保育業務メニュー/施設プルダウンは、機能フラグが有効な施設が1つでもある場合のみ表示(既定OFF)。
  const showChildcare = (offices?.length ?? 0) > 0;
  // 施設プルダウンは保育業務(/childcare)配下でのみ表示する。他ドメイン(勤怠/シフト等)は対象外。
  const isChildcarePage = pathname.startsWith("/childcare");

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
        {/* 保育業務配下: 施設選択プルダウン(全ページ共通)。各ページ本文の施設選択は廃止しここへ集約。 */}
        {isChildcarePage && showChildcare && (
          <label className="flex items-center gap-1.5 text-xs font-semibold text-slate-500">
            施設:
            <select
              value={selectedOffice}
              onChange={(e) => setSelectedOffice(e.target.value)}
              className="rounded-md border border-slate-300 bg-white px-2 py-1 text-sm font-semibold text-slate-800 focus:border-sky-400 focus:outline-none"
            >
              {offices?.map((office) => (
                <option key={office.office_id} value={office.office_id}>
                  {office.office_name}
                </option>
              ))}
            </select>
          </label>
        )}
        {identity && (
          <span className="text-sm text-slate-600">
            ログイン中: <span className="font-semibold text-slate-800">{identity.name}</span>
            <span className="text-slate-500">({roleDisplayName(identity.role_code)})</span>
            {/* 保育業務以外の画面では所属施設をフォールバック表示(施設プルダウンが無いため)。 */}
            {!isChildcarePage && identity.home_office_name && (
              <span className="ml-2 rounded-md bg-slate-100 px-2 py-0.5 text-xs text-slate-500">
                所属: {identity.home_office_name}
              </span>
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
