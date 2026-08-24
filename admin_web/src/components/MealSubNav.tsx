"use client";

import Link from "next/link";
import { usePathname, useSearchParams } from "next/navigation";

// 給食管理の内部サブナビ。食数ボード/献立/(将来: 検食チェック等)を1つの「給食管理」内で振り分ける。
const SUB_ITEMS = [
  { href: "/childcare/meal-board", label: "食数ボード" },
  { href: "/childcare/meal-photos", label: "給食写真" },
  { href: "/childcare/menus", label: "献立" },
  { href: "/childcare/menus/day", label: "日別ビュー" },
  { href: "/childcare/allergy-incidents", label: "アレルギー報告" },
  { href: "/childcare/meal-conferences", label: "給食会議" },
];

export function MealSubNav() {
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const office = searchParams.get("office");
  const cls = searchParams.get("class");
  const params = new URLSearchParams();
  if (office) params.set("office", office);
  if (cls) params.set("class", cls);
  const query = params.toString();
  const suffix = query ? `?${query}` : "";

  return (
    <div className="flex flex-wrap items-center gap-2 border-b border-slate-200 px-6 pb-2 pt-3">
      <span className="mr-2 text-sm font-bold text-slate-700">給食管理</span>
      {SUB_ITEMS.map((item) => (
        <Link
          key={item.href}
          href={`${item.href}${suffix}`}
          className={`rounded-lg px-3 py-1 text-sm font-medium transition ${
            pathname === item.href ? "bg-emerald-600 text-white" : "text-slate-500 hover:bg-slate-100"
          }`}
        >
          {item.label}
        </Link>
      ))}
    </div>
  );
}
