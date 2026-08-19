"use client";

import Link from "next/link";
import { usePathname, useSearchParams } from "next/navigation";
import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import type { ChildcareOffice } from "@/lib/types";

const THERAPY_HREF = "/childcare/therapy-records";
const SUPPORT_HREF = "/childcare/support-childcare";
const INCIDENT_HREF = "/childcare/incidents";
const MEAL_HREF = "/childcare/meal-board";

const CHILDCARE_NAV_ITEMS = [
  { href: "/childcare/daily-board", label: "デイリーボード" },
  { href: "/childcare/family-reports", label: "家庭での様子" },
  { href: "/childcare/nap", label: "午睡チェック" },
  { href: "/childcare/health-check", label: "健康チェック" },
  { href: "/childcare/class-activities", label: "クラス活動" },
  { href: "/childcare/contacts", label: "連絡帳" },
  { href: "/childcare/contacts/copy", label: "コピー" },
  { href: "/childcare/staff-messages", label: "園内連絡" },
  { href: "/childcare/announcements", label: "一斉配信" },
  { href: "/childcare/parent-requests", label: "保護者からの連絡" },
  { href: "/childcare/class-photos", label: "クラス写真" },
  { href: "/childcare/emergency-contacts", label: "緊急連絡先" },
  { href: THERAPY_HREF, label: "療育記録" },
  { href: "/childcare/support-childcare", label: "支援保育" },
  { href: INCIDENT_HREF, label: "ヒヤリハット・事故報告" },
  { href: MEAL_HREF, label: "食数ボード" },
  // 保護者管理・入園手続き・感染症マスターは管理業務としてトップレベルへ移設(俊指示 2026-08-17)。
];

export function ChildcareNav() {
  const pathname = usePathname();
  const searchParams = useSearchParams();
  // 療育記録タブは therapy_outing_enabled が「アクセス可能施設のいずれかでON」の
  // ときのみ表示(園児マスタの療育設定ボタン/デイリーボードのバッジと判定を揃える)。
  // 全施設OFFなら非表示。判定できるまで(初期)は安全側で非表示。
  const [therapyVisible, setTherapyVisible] = useState(false);
  // ヒヤリハット・事故報告タブは incident_reports_enabled が「アクセス可能施設のいずれかでON」のときのみ表示。
  const [incidentVisible, setIncidentVisible] = useState(false);
  // 食数ボードタブは meal_management_enabled が「アクセス可能施設のいずれかでON」のときのみ表示。
  const [mealVisible, setMealVisible] = useState(false);
  // 全保育施設と支援保育の対象施設。支援保育タブは「選択中施設が対象施設に含まれるとき」だけ表示する。
  // 対象施設リスト(supportOffices)は null=未取得/取得失敗 を意味し、その場合は安全側でタブを表示する。
  const [childcareOffices, setChildcareOffices] = useState<ChildcareOffice[]>([]);
  const [supportOffices, setSupportOffices] = useState<ChildcareOffice[] | null>(null);

  useEffect(() => {
    let cancelled = false;
    async function resolveVisibility() {
      const supabase = createClient();
      const { data } = await supabase.rpc("fetch_my_childcare_offices");
      const offices = (data ?? []) as ChildcareOffice[];
      if (!cancelled) setChildcareOffices(offices);
      if (offices.length > 0) {
        const checks = await Promise.all(
          offices.map((o) => supabase.rpc("is_therapy_outing_enabled_for_office", { p_office_id: o.office_id })),
        );
        if (!cancelled) setTherapyVisible(checks.some((c) => c.data === true));
        const incidentChecks = await Promise.all(
          offices.map((o) => supabase.rpc("is_incident_reports_enabled_for_office", { p_office_id: o.office_id })),
        );
        if (!cancelled) setIncidentVisible(incidentChecks.some((c) => c.data === true));
        const mealChecks = await Promise.all(
          offices.map((o) => supabase.rpc("is_meal_management_enabled_for_office", { p_office_id: o.office_id })),
        );
        if (!cancelled) setMealVisible(mealChecks.some((c) => c.data === true));
      }
      // 支援保育の対象施設。取得失敗時は null のまま(=タブ表示側に倒す)。
      const { data: supData, error: supErr } = await supabase.rpc("fetch_my_support_childcare_offices");
      if (!cancelled) setSupportOffices(supErr ? null : ((supData ?? []) as ChildcareOffice[]));
    }
    void resolveVisibility();
    return () => {
      cancelled = true;
    };
  }, []);

  // タブ切替後も選択中の施設(?office=)とクラス(?class=)を引き継ぐ。
  const office = searchParams.get("office");
  // 現在の実効施設(ヘッダーの selectedOffice 導出と一致): ?office= が有効ならそれ、無ければ先頭施設。
  const effectiveOffice =
    office && childcareOffices.some((o) => o.office_id === office)
      ? office
      : childcareOffices[0]?.office_id ?? office ?? null;
  // 支援保育タブ: 対象施設リスト未取得/失敗(null)なら表示、取得済みなら実効施設が対象に含まれるときのみ表示。
  const supportVisible =
    supportOffices === null ? true : effectiveOffice ? supportOffices.some((o) => o.office_id === effectiveOffice) : true;

  const items = CHILDCARE_NAV_ITEMS.filter(
    (item) =>
      (item.href !== THERAPY_HREF || therapyVisible) &&
      (item.href !== SUPPORT_HREF || supportVisible) &&
      (item.href !== INCIDENT_HREF || incidentVisible) &&
      (item.href !== MEAL_HREF || mealVisible),
  );

  const cls = searchParams.get("class");
  const params = new URLSearchParams();
  if (office) params.set("office", office);
  if (cls) params.set("class", cls);
  const query = params.toString();
  const suffix = query ? `?${query}` : "";

  return (
    <div className="border-b border-slate-200 bg-slate-50 px-6 py-2">
      <nav className="flex gap-1">
        {items.map((item) => (
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
