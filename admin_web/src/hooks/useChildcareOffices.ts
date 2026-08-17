"use client";

import { useEffect, useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import type { ChildcareOffice } from "@/lib/types";

/**
 * 保育業務系ページ共通の施設選択。施設名の表示・選択はヘッダー(AppHeader)に集約し、
 * 各ページは選択中施設(selectedOffice)を本フックから受け取る。
 * 選択状態は URL クエリパラメータ(?office=)を正とし、タブ(ページ)を切り替えても
 * 施設が保持される/URL共有で同じ施設が開く。rpcNameで施設一覧RPCを差し替えられる。
 */
export function useChildcareOffices(rpcName: "fetch_my_childcare_offices" | "fetch_my_support_childcare_offices" = "fetch_my_childcare_offices") {
  const [offices, setOffices] = useState<ChildcareOffice[] | null>(null);
  const [officesError, setOfficesError] = useState<string | null>(null);
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();

  useEffect(() => {
    const supabase = createClient();
    supabase.rpc(rpcName).then(({ data, error }) => {
      if (error) {
        setOfficesError(error.message);
        return;
      }
      setOffices((data ?? []) as ChildcareOffice[]);
    });
    // 施設一覧(RPC)は初回マウント時のみ取得する。
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // 選択中施設は URL(?office=) から導出する(内部stateを持たない)。ヘッダーの施設プルダウンが
  // ?office= を更新すると、このフックを使う全ページの selectedOffice が同じ値へ即追随する。
  // 一覧が未取得の間は空文字。URLに無い/一覧に無い場合は既定施設(大和オハナ保育園、
  // 無ければ先頭施設)にする(俊指示 2026-08-17)。
  const fromUrl = searchParams.get("office");
  const selectedOffice = offices
    ? fromUrl && offices.some((o) => o.office_id === fromUrl)
      ? fromUrl
      : offices.find((o) => o.office_name === "大和オハナ保育園")?.office_id ?? offices[0]?.office_id ?? ""
    : "";

  function setSelectedOffice(officeId: string) {
    const params = new URLSearchParams(searchParams.toString());
    params.set("office", officeId);
    router.replace(`${pathname}?${params.toString()}`);
  }

  return { offices, officesError, selectedOffice, setSelectedOffice };
}
