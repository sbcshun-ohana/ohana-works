"use client";

import Link from "next/link";
import { usePathname, useSearchParams } from "next/navigation";

const CHILDCARE_NAV_ITEMS = [
  { href: "/childcare/daily-board", label: "デイリーボード" },
  { href: "/childcare/children", label: "園児マスタ" },
  { href: "/childcare/attendance", label: "欠席選択" },
  { href: "/childcare/class-activities", label: "クラス活動" },
  { href: "/childcare/contacts", label: "連絡帳" },
  { href: "/childcare/contacts/copy", label: "コピー" },
  { href: "/childcare/guardians", label: "保護者管理" },
  { href: "/childcare/parent-requests", label: "保護者申請" },
  { href: "/childcare/class-photos", label: "クラス写真" },
  { href: "/childcare/emergency-contacts", label: "緊急連絡先" },
  { href: "/childcare/support-childcare", label: "支援保育" },
];

export function ChildcareNav() {
  const pathname = usePathname();
  const searchParams = useSearchParams();
  // タブ切替後も選択中の施設(?office=)を引き継ぐ。
  const office = searchParams.get("office");
  const suffix = office ? `?office=${office}` : "";

  return (
    <div className="border-b border-slate-200 bg-slate-50 px-6 py-2">
      <nav className="flex gap-1">
        {CHILDCARE_NAV_ITEMS.map((item) => (
          <Link
            key={item.href}
            href={`${item.href}${suffix}`}
            className={`rounded-lg px-3 py-1.5 text-sm font-medium transition ${
              pathname === item.href
                ? "bg-white text-sky-700 shadow-sm"
                : "text-slate-500 hover:bg-white/60"
            }`}
          >
            {item.label}
          </Link>
        ))}
      </nav>
    </div>
  );
}
