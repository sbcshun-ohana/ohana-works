"use client";

import { useEffect, useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import type { ChildcareClass } from "@/lib/types";

/** 全クラス(絞り込みなし)を表す番兵値。 */
export const ALL_CLASSES = "";

/**
 * 保育業務系ページ共通のクラス選択。施設(useChildcareOffices の selectedOffice)配下の
 * クラス一覧を fetch_childcare_classes で取得し、選択中クラス(class_id)を URL の ?class= で
 * 引き継ぐ(?office= と同様にタブ切替で保持)。既定は全クラス。
 * 施設が変わると ?class= はその施設のクラスに属す時のみ維持し、属さなければ全クラスへリセット
 * (class_id は施設固有のため)。並び順は fetch_childcare_classes の返却順(=年齢区分順: age_group→class_name)を正とする。
 *
 * options.defaultToFirst=true: 全クラス(絞り込みなし)を持たず、クラス必須のページ
 * (欠席選択/クラス写真等)向け。有効な ?class= が無ければ先頭クラスを選び、その値を ?class= に
 * 書き込んでタブ切替で保持する。
 */
export function useChildcareClass(selectedOffice: string, options?: { defaultToFirst?: boolean }) {
  const defaultToFirst = options?.defaultToFirst ?? false;
  const [classes, setClasses] = useState<ChildcareClass[]>([]);
  const [selectedClass, setSelectedClassState] = useState<string>(ALL_CLASSES);
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();

  useEffect(() => {
    // 施設未選択(マウント直後の一瞬)は取得しない。初期値が空なので同期リセットは不要。
    if (!selectedOffice) return;
    const supabase = createClient();
    supabase.rpc("fetch_childcare_classes", { p_office_id: selectedOffice }).then(({ data, error }) => {
      if (error) return;
      const list = (data ?? []) as ChildcareClass[];
      setClasses(list);
      const fromUrl = searchParams.get("class");
      let valid = fromUrl && list.some((c) => c.class_id === fromUrl) ? fromUrl : ALL_CLASSES;
      if (valid === ALL_CLASSES && defaultToFirst && list.length > 0) valid = list[0].class_id;
      setSelectedClassState(valid);
      // 施設変更等で ?class= が現施設のクラスに属さない、または先頭クラス既定を採用した場合は URL を同期。
      if (valid !== (fromUrl ?? ALL_CLASSES)) {
        const params = new URLSearchParams(searchParams.toString());
        if (valid === ALL_CLASSES) params.delete("class");
        else params.set("class", valid);
        router.replace(`${pathname}?${params.toString()}`);
      }
    });
    // 施設変更時のみ再取得(?class= の変化では再取得しない)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedOffice]);

  function setSelectedClass(classId: string) {
    setSelectedClassState(classId);
    const params = new URLSearchParams(searchParams.toString());
    if (!classId) params.delete("class");
    else params.set("class", classId);
    router.replace(`${pathname}?${params.toString()}`);
  }

  /** 選択中クラスの class_name(全クラス選択時は null)。行の class_name 絞り込み用。 */
  const selectedClassName = classes.find((c) => c.class_id === selectedClass)?.class_name ?? null;

  return { classes, selectedClass, setSelectedClass, selectedClassName };
}
