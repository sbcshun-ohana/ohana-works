"use client";

import { useEffect, useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import type { ChildcareOffice } from "@/lib/types";

/**
 * 保育業務系ページ共通の施設選択。タブ(ページ)を切り替えても選択中の施設が
 * リセットされないよう、URLクエリパラメータ(?office=)で状態を引き継ぐ。
 * rpcNameを指定すると、機能フラグが異なる施設一覧RPC(例: 支援保育専用の
 * fetch_my_support_childcare_offices)に差し替えられる。
 */
export function useChildcareOffices(rpcName: "fetch_my_childcare_offices" | "fetch_my_support_childcare_offices" = "fetch_my_childcare_offices") {
  const [offices, setOffices] = useState<ChildcareOffice[] | null>(null);
  const [officesError, setOfficesError] = useState<string | null>(null);
  const [selectedOffice, setSelectedOfficeState] = useState<string>("");
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
      const list = (data ?? []) as ChildcareOffice[];
      setOffices(list);
      const fromUrl = searchParams.get("office");
      const initial = fromUrl && list.some((o) => o.office_id === fromUrl) ? fromUrl : (list[0]?.office_id ?? "");
      setSelectedOfficeState(initial);
    });
    // 初回マウント時のみ実行(officeパラメータの変化で再取得はしない)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  function setSelectedOffice(officeId: string) {
    setSelectedOfficeState(officeId);
    const params = new URLSearchParams(searchParams.toString());
    params.set("office", officeId);
    router.replace(`${pathname}?${params.toString()}`);
  }

  return { offices, officesError, selectedOffice, setSelectedOffice };
}
