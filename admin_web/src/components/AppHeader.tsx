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
  // 俊指示(2026-08-14): 園児マスタは職員マスタと同様に保育業務外のトップレベルで管理する。
  // 俊指示(2026-08-17): 保護者管理・入園手続き・感染症マスターも管理業務としてトップレベルへ。
  { href: "/children", label: "園児マスタ" },
  { href: "/guardians", label: "保護者管理" },
  { href: "/enrollment-forms", label: "入園手続き" },
  { href: "/infection-masters", label: "感染症マスター" },
  { href: "/food-checks", label: "食材チェック" },
  { href: "/development-masters", label: "発達記録マスター" },
  // 俊指示(2026-08-25): 重要事項説明書は保育業務ではなく管理者業務としてトップレベルへ。
  { href: "/childcare/important-matters", label: "重要事項説明書" },
  { href: "/notices", label: "お知らせ(職員向け)" },
  { href: "/payroll", label: "給与確定" },
  { href: "/settings", label: "設定" },
  { href: "/feature-flags", label: "機能フラグ" },
];

// 保育業務の施設選択(?office=)に依存するトップレベルページ。
// useChildcareOffices を使うページを /childcare の外へ出す場合はここへ追加すること
// (追加しないと施設プルダウンが出ず、先頭施設が黙って選ばれる)。
const CHILDCARE_OFFICE_PAGES = ["/children", "/guardians", "/enrollment-forms", "/infection-masters", "/food-checks", "/billing/fee-master", "/billing/invoices"];

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
  // 料金マスタータブは「請求フラグONの施設を管理する主任以上」にのみ表示(金額非表示=AC-22)。
  // fetch_billing_offices は一般職員・フラグ全OFFでは0件を返すのでタブごと消える。
  const [showBilling, setShowBilling] = useState(false);

  useEffect(() => {
    const supabase = createClient();
    supabase.rpc("fetch_my_session_identity").then(({ data, error }) => {
      if (!error && Array.isArray(data) && data.length > 0) {
        setIdentity(data[0] as SessionIdentity);
      }
    });
    supabase.rpc("fetch_billing_offices").then(({ data, error }) => {
      setShowBilling(!error && Array.isArray(data) && data.length > 0);
    });
  }, []);

  // 保育業務メニュー/施設プルダウンは、機能フラグが有効な施設が1つでもある場合のみ表示(既定OFF)。
  const showChildcare = (offices?.length ?? 0) > 0;
  // 施設プルダウンは保育業務(/childcare)配下と、保育業務の施設選択に依存する
  // トップレベルページ(CHILDCARE_OFFICE_PAGES)で表示する。他ドメイン(勤怠/シフト等)は対象外。
  const isChildcarePage = pathname.startsWith("/childcare") || CHILDCARE_OFFICE_PAGES.includes(pathname);

  // 保育業務の入口はデイリーボード(全職員が閲覧可)。/childcare/attendance は主任以上RPC+
  // attendance_mgmt_enabled ゲートのため、入口に使うと一般職員・フラグOFF施設で赤帯着地になる。
  const navItems = [
    ...NAV_ITEMS,
    ...(showBilling
      ? [
          { href: "/billing/fee-master", label: "料金マスター" },
          { href: "/billing/invoices", label: "請求管理" },
          { href: "/childcare/temp-care", label: "一時預かり" },
        ]
      : []),
    ...(showChildcare ? [{ href: "/childcare/daily-board", label: "保育業務" }] : []),
  ];

  async function handleLogout() {
    const supabase = createClient();
    await supabase.auth.signOut();
    router.push("/login");
    router.refresh();
  }

  // 2行構成ヘッダー(俊指示 2026-08-17): 1行目=タイトル+施設選択+ログイン情報、2行目=ナビ。
  // 各タブは whitespace-nowrap でラベル内改行を禁止し、収まらない場合はタブ単位で折り返す
  // (画面幅に依存せず常に読める)。
  return (
    <header className="border-b border-slate-200 bg-white px-6 py-3">
      <div className="flex flex-wrap items-center justify-between gap-x-4 gap-y-2">
        <h1 className="whitespace-nowrap text-lg font-bold text-slate-800">Ohana Works 管理者Web</h1>
        <div className="flex flex-wrap items-center gap-3">
          {/* 保育業務系ページ: 施設選択プルダウン(全ページ共通)。各ページ本文の施設選択は廃止しここへ集約。 */}
          {isChildcarePage && showChildcare && (
            <label className="flex items-center gap-1.5 whitespace-nowrap text-xs font-semibold text-slate-500">
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
            <span className="whitespace-nowrap text-sm text-slate-600">
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
            className="whitespace-nowrap rounded-lg border border-slate-300 px-3 py-1.5 text-sm font-medium text-slate-600 transition hover:bg-slate-50"
          >
            ログアウト
          </button>
        </div>
      </div>
      <nav className="mt-2 flex flex-wrap gap-1">
        {navItems.map((item) => {
          // 「保育業務」タブは /childcare 配下でアクティブ。ただし重要事項説明書はトップレベル扱いのため除外。
          const isActive = item.href === "/childcare/daily-board"
            ? pathname.startsWith("/childcare")
                && !pathname.startsWith("/childcare/important-matters")
                && !pathname.startsWith("/childcare/temp-care")
            : pathname === item.href;
          // 施設選択に依存するページへのタブ遷移では現在の ?office= を引き継ぐ。
          // (引き継がないと遷移時に既定施設=大和へ戻り、一時預かり登録が誤施設で作られる等の事故になる)
          const isOfficeScoped = item.href.startsWith("/childcare") || CHILDCARE_OFFICE_PAGES.includes(item.href);
          const href = isOfficeScoped && selectedOffice
            ? `${item.href}?office=${selectedOffice}`
            : item.href;
          return (
            <Link
              key={item.href}
              href={href}
              className={`whitespace-nowrap rounded-lg border px-3 py-1.5 text-sm font-medium transition ${
                isActive
                  ? "border-sky-200 bg-sky-50 text-sky-700"
                  : "border-slate-200 text-slate-500 hover:bg-slate-50"
              }`}
            >
              {item.label}
            </Link>
          );
        })}
      </nav>
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
