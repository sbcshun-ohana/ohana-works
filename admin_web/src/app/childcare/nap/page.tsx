"use client";

import { Suspense, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { ChildcareNav } from "@/components/ChildcareNav";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";
import { useChildcareClass } from "@/hooks/useChildcareClass";
import { currentDate } from "@/lib/datetime";
import type { NapSessionRow, NapCheck, NapInterval } from "@/lib/types";
import { NAP_BODY_POSITIONS, NAP_BODY_POSITIONS_SHORT } from "@/lib/types";

// 午睡区間RPCの例外メッセージを日本語表示へ。
function friendlyNapError(msg: string | undefined): string {
  const m = msg ?? "";
  if (m.includes("not authorized")) return "この操作を行う権限がありません(30分超・過去日は主任以上)";
  if (m.includes("wake before sleep")) return "起床時刻は入眠時刻より後にしてください";
  if (m.includes("not found")) return "対象が見つかりません";
  return "操作に失敗しました";
}

// businessDate(YYYY-MM-DD)+ HH:MM を JST の ISO 文字列に。
function toIso(businessDate: string, time: string): string {
  return `${businessDate}T${time}:00+09:00`;
}
function hmLocal(iso: string): string {
  return new Date(iso).toLocaleTimeString("ja-JP", { hour: "2-digit", minute: "2-digit" });
}
function nowHm(): string {
  const d = new Date();
  return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
}

function hm(d: Date): string {
  return d.toLocaleTimeString("ja-JP", { hour: "2-digit", minute: "2-digit" });
}

// 選択中の時間帯(1時間)の5分スロット12本(HH:00〜HH:55 JST)。
function hourSlots(businessDate: string, hour: number): Date[] {
  const hh = String(hour).padStart(2, "0");
  return Array.from(
    { length: 12 },
    (_, i) => new Date(`${businessDate}T${hh}:${String(i * 5).padStart(2, "0")}:00+09:00`),
  );
}

// 各睡眠区間を [入眠ms, 起床ms|null] で返す(起床null=就寝中)。
function sleepRanges(row: NapSessionRow): [number, number | null][] {
  if (row.intervals.length > 0) {
    return row.intervals.map((i) => [
      new Date(i.sleep_start_at).getTime(),
      i.wake_up_at ? new Date(i.wake_up_at).getTime() : null,
    ]);
  }
  if (row.sleep_start_at) {
    return [[new Date(row.sleep_start_at).getTime(), row.wake_up_at ? new Date(row.wake_up_at).getTime() : null]];
  }
  return [];
}

// slot時点で就寝中か(いずれかの区間 [入眠,起床) に入る)。
function isSleepingAt(row: NapSessionRow, slot: Date): boolean {
  const t = slot.getTime();
  return sleepRanges(row).some(([s, w]) => t >= s && (w == null || t < w));
}

// slotより前で最も新しいチェック(列一括の「各児の直前チェック」)。
function priorCheck(row: NapSessionRow, slot: Date): NapCheck | null {
  let best: NapCheck | null = null;
  let bestT = -1;
  for (const c of row.checks) {
    const ct = new Date(c.slot_at).getTime();
    if (ct < slot.getTime() && ct > bestT) {
      best = c;
      bestT = ct;
    }
  }
  return best;
}

// 在籍名簿(クラス選択時=fetch_class_children / 全クラス=fetch_children_for_office)。
type RosterChild = {
  child_id: string;
  display_name: string;
  honorific_suffix: string | null;
  class_id: string | null;
  class_name: string | null;
  is_absent?: boolean;
};

// 名簿 × 午睡セッションのマージ: 在籍園児全員を行にし、セッションがあればその内容を、無ければ空の行を返す。
// 区間は sleep_start_at 昇順に統一(seq順でなく時刻順)。名簿に無いがセッションを持つ児(異動等)は末尾に補完。
function buildDisplayRows(roster: RosterChild[], board: NapSessionRow[]): NapSessionRow[] {
  const boardByChild = new Map(board.map((r) => [r.child_id, r]));
  const sortIv = (r: NapSessionRow): NapSessionRow => ({
    ...r,
    intervals: [...r.intervals].sort(
      (a, b) => new Date(a.sleep_start_at).getTime() - new Date(b.sleep_start_at).getTime(),
    ),
  });
  const rows: NapSessionRow[] = roster.map((c) => {
    const found = boardByChild.get(c.child_id);
    if (found) return sortIv(found);
    return {
      session_id: "",
      child_id: c.child_id,
      display_name: c.display_name,
      honorific_suffix: c.honorific_suffix,
      class_id: c.class_id ?? "",
      class_name: c.class_name ?? "",
      is_required: false,
      sleep_start_at: null,
      wake_up_at: null,
      intervals: [],
      checks: [],
    };
  });
  const rosterIds = new Set(roster.map((c) => c.child_id));
  for (const r of board) if (!rosterIds.has(r.child_id)) rows.push(sortIv(r));
  return rows;
}

function ChildcareNapPageContent() {
  // 施設選択はヘッダーに集約。selectedOffice は useChildcareOffices が ?office= に追随して供給する。
  const { offices, officesError, selectedOffice } = useChildcareOffices();
  const isManager = offices?.find((o) => o.office_id === selectedOffice)?.is_manager ?? false;
  const { classes, selectedClass, setSelectedClass } = useChildcareClass(selectedOffice);
  const [businessDate, setBusinessDate] = useState(currentDate());
  const [selectedHour, setSelectedHour] = useState<number>(new Date().getHours());
  const [rows, setRows] = useState<NapSessionRow[]>([]);
  const [reloadToken, setReloadToken] = useState(0);
  const [editing, setEditing] = useState<{ row: NapSessionRow; slot: Date; existing: NapCheck | null } | null>(null);
  const [intervalEdit, setIntervalEdit] = useState<{ interval: NapInterval } | null>(null);
  const [roster, setRoster] = useState<RosterChild[]>([]);
  const [toast, setToast] = useState<string | null>(null);
  // 現在時刻(5分窓・30分ルールの判定用)。レンダー中に Date.now() を呼ばないため状態化し、
  // 30秒ごとに更新して窓の開閉を自動反映する。
  const [nowMs, setNowMs] = useState<number>(() => Date.now());
  useEffect(() => {
    const id = window.setInterval(() => setNowMs(Date.now()), 30000);
    return () => window.clearInterval(id);
  }, []);

  function showToast(m: string) {
    setToast(m);
    window.setTimeout(() => setToast((c) => (c === m ? null : c)), 3500);
  }

  // セルの編集可否(サーバー側 nap_check_authz を UI で先取り。サーバー側ゲートは現状維持)。
  // - 未来のセル(まだ来ていない5分)は誰も記録不可。
  // - 主任以上: 窓外(過去)も記録・修正可。過去日も可。
  // - 一般職員 かつ 当日:
  //     未記入 = 「その5分間」(slot〜slot+5分)のみ記録可。
  //     記録済 = 記録から30分以内(slot経過で近似)のみ修正可。
  //   過去日は不可(主任のみ)。
  function cellCanEdit(slot: Date, hasCheck: boolean): boolean {
    const s = slot.getTime();
    if (nowMs < s) return false; // 未来
    if (isManager) return true;
    if (businessDate < currentDate()) return false; // 過去日=主任のみ
    if (hasCheck) return (nowMs - s) / 60000 <= 30; // 記録済は30分以内のみ修正
    return nowMs < s + 5 * 60000; // 未記入は「その5分間」のみ(nowMs>=s は上で保証)
  }

  // 列一括の可否(未記入セルの記録と同基準)。
  function columnBulkEnabled(slot: Date): boolean {
    const s = slot.getTime();
    if (nowMs < s) return false;
    if (isManager) return true;
    if (businessDate < currentDate()) return false;
    return nowMs < s + 5 * 60000; // 現在の5分窓
  }

  // 起床(開いている最終区間に起床時刻を書く)
  async function setWake(interval: NapInterval, time: string) {
    const { error } = await createClient().rpc("set_nap_interval", {
      p_interval_id: interval.id,
      p_sleep_start_at: interval.sleep_start_at,
      p_wake_up_at: toIso(businessDate, time),
    });
    if (error) showToast(friendlyNapError(error.message));
    else {
      showToast("起床を記録しました");
      setReloadToken((t) => t + 1);
    }
  }

  // 再入眠(新しい区間を追加)/ 入眠追加
  async function addInterval(childId: string, sleepTime: string, wakeTime?: string) {
    const { error } = await createClient().rpc("add_nap_interval", {
      p_child_id: childId,
      p_sleep_start_at: toIso(businessDate, sleepTime),
      p_wake_up_at: wakeTime ? toIso(businessDate, wakeTime) : null,
    });
    if (error) showToast(friendlyNapError(error.message));
    else {
      showToast("入眠を記録しました");
      setReloadToken((t) => t + 1);
    }
  }

  async function saveInterval(interval: NapInterval, sleepTime: string, wakeTime: string): Promise<boolean> {
    const { error } = await createClient().rpc("set_nap_interval", {
      p_interval_id: interval.id,
      p_sleep_start_at: toIso(businessDate, sleepTime),
      p_wake_up_at: wakeTime ? toIso(businessDate, wakeTime) : null,
    });
    if (error) {
      showToast(friendlyNapError(error.message));
      return false;
    }
    showToast("区間を更新しました");
    setReloadToken((t) => t + 1);
    return true;
  }

  async function deleteInterval(interval: NapInterval) {
    if (!window.confirm("この区間を削除します。よろしいですか?")) return;
    const { error } = await createClient().rpc("delete_nap_interval", { p_interval_id: interval.id });
    if (error) showToast(friendlyNapError(error.message));
    else {
      showToast("区間を削除しました");
      setReloadToken((t) => t + 1);
    }
  }

  useEffect(() => {
    function load() {
      if (!selectedOffice) return;
      createClient()
        .rpc("fetch_nap_board", {
          p_office_id: selectedOffice,
          p_class_id: selectedClass === "" ? null : selectedClass,
          p_session_date: businessDate,
        })
        .then(({ data }) => setRows((data ?? []) as NapSessionRow[]));
    }
    load();
  }, [selectedOffice, selectedClass, businessDate, reloadToken]);

  // 在籍名簿の取得。クラス選択時=そのクラスの在籍児、全クラス=施設の全園児(退園済み除く)。
  useEffect(() => {
    function load() {
      if (!selectedOffice) {
        setRoster([]);
        return;
      }
      const supabase = createClient();
      // 名簿は登園済み(present/picked_up・非欠席)のみ(258 fetch_nap_roster)。欠席・未登園は表示しない。
      supabase
        .rpc("fetch_nap_roster", {
          p_office_id: selectedOffice,
          p_class_id: selectedClass === "" ? null : selectedClass,
          p_business_date: businessDate,
        })
        .then(({ data }) =>
          setRoster(
            (data ?? []) as { child_id: string; display_name: string; honorific_suffix: string | null; class_id: string; class_name: string | null }[],
          ),
        );
    }
    load();
  }, [selectedOffice, selectedClass, businessDate, reloadToken, classes]);

  // 在籍名簿 × 午睡セッションのマージ(区間は sleep_start_at 昇順)。
  const displayRows = buildDisplayRows(roster, rows);

  // 列一括: その時刻列(slot)に就寝中の全児へ「各児の直前チェックと同じ体位」で一括記録。
  // 直前チェックが無い児・既に当該スロットに記録がある児はスキップ(旧「5分前と同じ」の
  // “ちょうど5分前が必須”という不具合を避け、隣接に限らず各児の最新の直前記録を複製する)。
  async function columnBulk(slot: Date) {
    const supabase = createClient();
    let count = 0;
    for (const row of displayRows) {
      if (!row.session_id) continue;
      if (!isSleepingAt(row, slot)) continue; // 就寝中のみ
      const has = row.checks.some((c) => new Date(c.slot_at).getTime() === slot.getTime());
      if (has) continue; // 既記入はスキップ
      const prior = priorCheck(row, slot);
      if (!prior) continue; // 直前記録が無い児はスキップ
      const { error } = await supabase.rpc("record_nap_check", {
        p_session_id: row.session_id,
        p_slot_at: slot.toISOString(),
        p_body_position: prior.body_position,
        p_breathing: prior.breathing,
        p_complexion: prior.complexion,
        p_bedding: prior.bedding,
      });
      if (error) {
        showToast(friendlyNapError(error.message));
        return;
      }
      count += 1;
    }
    showToast(count > 0 ? `${count}件を「直前と同じ」で登録しました` : "対象がありません(就寝中で直前チェックのある未記入セルなし)");
    setReloadToken((t) => t + 1);
  }

  async function saveCheck(
    row: NapSessionRow,
    slot: Date,
    body: string,
    breathing: boolean,
    complexion: boolean,
    bedding: boolean,
  ): Promise<boolean> {
    const { error } = await createClient().rpc("record_nap_check", {
      p_session_id: row.session_id,
      p_slot_at: slot.toISOString(),
      p_body_position: body,
      p_breathing: breathing,
      p_complexion: complexion,
      p_bedding: bedding,
    });
    if (error) return false;
    setReloadToken((t) => t + 1);
    return true;
  }

  if (officesError) {
    return (
      <div className="flex flex-1 flex-col">
        <AppHeader />
        <div className="p-8 text-sm text-red-500">施設一覧の取得に失敗しました: {officesError}</div>
      </div>
    );
  }

  return (
    <div className="flex flex-1 flex-col">
      <AppHeader />
      <ChildcareNav />
      <main className="flex-1 space-y-6 p-6">
        <h2 className="text-lg font-bold text-slate-800">午睡チェック(閲覧・修正)</h2>
        <p className="text-xs text-slate-500">
          過去日・30分超の修正は主任以上のみ可能です。当日30分以内は一般職員も記入できます。
        </p>

        <div className="flex flex-wrap items-end gap-4 rounded-2xl bg-white p-4 shadow-sm">
          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">クラス</label>
            <select
              value={selectedClass}
              onChange={(e) => setSelectedClass(e.target.value)}
              className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            >
              <option value="">全クラス</option>
              {classes.map((c) => (
                <option key={c.class_id} value={c.class_id}>
                  {c.class_name}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">対象日</label>
            <input
              type="date"
              value={businessDate}
              onChange={(e) => setBusinessDate(e.target.value)}
              className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            />
          </div>
          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">時間帯</label>
            <select
              value={selectedHour}
              onChange={(e) => setSelectedHour(Number(e.target.value))}
              className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            >
              {Array.from({ length: 24 }, (_, h) => (
                <option key={h} value={h}>
                  {String(h).padStart(2, "0")}:00 台
                </option>
              ))}
            </select>
          </div>
        </div>

        {displayRows.length === 0 && <p className="text-sm text-slate-400">対象の園児がいません。</p>}

        {/* コドモン準拠: 時間帯(1時間)の5分刻み12列グリッド。各列上部に列一括ボタン。 */}
        {displayRows.length > 0 && (
          <div className="overflow-x-auto rounded-2xl bg-white shadow-sm">
            <table className="min-w-full border-separate border-spacing-0 text-xs">
              <thead>
                <tr>
                  <th className="sticky left-0 z-10 bg-white px-3 py-2 text-left font-semibold text-slate-500">
                    園児 / 区間
                  </th>
                  {hourSlots(businessDate, selectedHour).map((slot) => (
                    <th key={slot.toISOString()} className="px-1 py-2 text-center">
                      <div className="text-[10px] tabular-nums text-slate-500">{hm(slot)}</div>
                      <button
                        onClick={() => columnBulk(slot)}
                        disabled={!columnBulkEnabled(slot)}
                        title="この時刻に就寝中の全児へ、各児の直前チェックと同じ体位で一括記録"
                        className="mt-0.5 rounded border border-indigo-300 bg-indigo-50 px-1 py-0.5 text-[9px] font-semibold text-indigo-700 hover:bg-indigo-100 disabled:cursor-not-allowed disabled:opacity-40"
                      >
                        一括
                      </button>
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {displayRows.map((row) => {
                  const lastOpen = row.intervals.find((i) => !i.wake_up_at);
                  const allWoken = row.intervals.length > 0 && row.intervals.every((i) => i.wake_up_at);
                  const notSlept = row.intervals.length === 0;
                  return (
                    <tr key={row.child_id} className="border-t border-slate-100">
                      <td className="sticky left-0 z-10 min-w-[16rem] bg-white px-3 py-2 align-top">
                        <div className="flex flex-wrap items-center gap-1 text-slate-800">
                          <span className="font-semibold">
                            {row.display_name}
                            {row.honorific_suffix ?? ""}
                          </span>
                          <span className="text-slate-400">/ {row.class_name}</span>
                        </div>
                        <div className="mt-1 flex flex-wrap items-center gap-1">
                          {row.intervals.map((iv) => (
                            <span key={iv.id} className="flex items-center gap-1 rounded-full bg-slate-100 px-2 py-0.5 text-[11px] text-slate-600">
                              {hmLocal(iv.sleep_start_at)}-{iv.wake_up_at ? hmLocal(iv.wake_up_at) : "就寝中"}
                              <button onClick={() => setIntervalEdit({ interval: iv })} className="text-sky-600 hover:underline">編集</button>
                              <button onClick={() => deleteInterval(iv)} className="text-red-500 hover:underline">削除</button>
                            </span>
                          ))}
                          {notSlept && (
                            <button onClick={() => addInterval(row.child_id, nowHm())} className="rounded border border-sky-300 px-2 py-0.5 text-[11px] text-sky-700 hover:bg-sky-50">
                              入眠(現在)
                            </button>
                          )}
                          {lastOpen && (
                            <button onClick={() => setWake(lastOpen, nowHm())} className="rounded border border-emerald-300 px-2 py-0.5 text-[11px] text-emerald-700 hover:bg-emerald-50">
                              起床(現在)
                            </button>
                          )}
                          {allWoken && (
                            <button onClick={() => addInterval(row.child_id, nowHm())} className="rounded border border-sky-300 px-2 py-0.5 text-[11px] text-sky-700 hover:bg-sky-50">
                              再入眠(現在)
                            </button>
                          )}
                        </div>
                      </td>
                      {hourSlots(businessDate, selectedHour).map((slot) => {
                        const sleeping = isSleepingAt(row, slot);
                        const check = row.checks.find((c) => new Date(c.slot_at).getTime() === slot.getTime()) ?? null;
                        // 就寝中でなく記録も無いセルは空欄(記録対象外)。
                        if (!sleeping && !check) {
                          return <td key={slot.toISOString()} className="px-1 py-1 text-center text-slate-200">·</td>;
                        }
                        const missing = sleeping && !check && slot.getTime() < nowMs;
                        const editable = cellCanEdit(slot, !!check);
                        return (
                          <td key={slot.toISOString()} className="px-1 py-1 text-center">
                            <button
                              disabled={!editable}
                              onClick={editable ? () => setEditing({ row, slot, existing: check }) : undefined}
                              title={
                                check
                                  ? `${NAP_BODY_POSITIONS[check.body_position] ?? check.body_position}${check.checked_by_name ? ` / 記録者: ${check.checked_by_name}` : ""}`
                                  : !editable
                                    ? "この5分間のみ記録可(過去・30分超は主任以上)"
                                    : undefined
                              }
                              className={`w-9 rounded px-1 py-1 font-semibold ${
                                check
                                  ? "bg-emerald-50 text-emerald-700"
                                  : missing
                                    ? "bg-red-50 text-red-600"
                                    : "bg-slate-50 text-slate-400"
                              } ${editable ? "" : "cursor-not-allowed opacity-40 grayscale"}`}
                            >
                              {check ? (NAP_BODY_POSITIONS_SHORT[check.body_position] ?? check.body_position) : missing ? "未" : "—"}
                            </button>
                          </td>
                        );
                      })}
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </main>

      {editing && (
        <NapCheckModal
          childName={`${editing.row.display_name}${editing.row.honorific_suffix ?? ""}`}
          slot={editing.slot}
          existing={editing.existing}
          onClose={() => setEditing(null)}
          onSave={async (body, breathing, complexion, bedding) => {
            const ok = await saveCheck(editing.row, editing.slot, body, breathing, complexion, bedding);
            if (ok) setEditing(null);
            return ok;
          }}
        />
      )}

      {intervalEdit && (
        <NapIntervalEditModal
          interval={intervalEdit.interval}
          onClose={() => setIntervalEdit(null)}
          onSave={async (sleepTime, wakeTime) => {
            const ok = await saveInterval(intervalEdit.interval, sleepTime, wakeTime);
            if (ok) setIntervalEdit(null);
          }}
        />
      )}

      {toast && (
        <div className="fixed bottom-6 left-1/2 z-[60] -translate-x-1/2 rounded-xl bg-slate-800 px-4 py-2 text-sm font-semibold text-white shadow-lg">
          {toast}
        </div>
      )}
    </div>
  );
}

// 区間の時刻編集(入眠・起床)。
function NapIntervalEditModal({
  interval,
  onClose,
  onSave,
}: {
  interval: NapInterval;
  onClose: () => void;
  onSave: (sleepTime: string, wakeTime: string) => void;
}) {
  const [sleep, setSleep] = useState(hmLocal(interval.sleep_start_at));
  const [wake, setWake] = useState(interval.wake_up_at ? hmLocal(interval.wake_up_at) : "");
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/30 p-4">
      <div className="w-full max-w-sm rounded-2xl bg-white p-6 shadow-xl">
        <h3 className="text-base font-bold text-slate-800">区間の時刻を編集</h3>
        <div className="mt-4 flex gap-3">
          <div>
            <label className="mb-1 block text-xs text-slate-500">入眠</label>
            <input type="time" value={sleep} onChange={(e) => setSleep(e.target.value)} className="rounded-lg border border-slate-300 px-3 py-2 text-sm" />
          </div>
          <div>
            <label className="mb-1 block text-xs text-slate-500">起床(空=就寝中)</label>
            <input type="time" value={wake} onChange={(e) => setWake(e.target.value)} className="rounded-lg border border-slate-300 px-3 py-2 text-sm" />
          </div>
        </div>
        <div className="mt-6 flex justify-end gap-2">
          <button onClick={onClose} className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-semibold text-slate-600 hover:bg-slate-50">キャンセル</button>
          <button onClick={() => onSave(sleep, wake)} className="rounded-lg bg-sky-500 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-600">保存</button>
        </div>
      </div>
    </div>
  );
}

function NapCheckModal({
  childName,
  slot,
  existing,
  onClose,
  onSave,
}: {
  childName: string;
  slot: Date;
  existing: NapCheck | null;
  onClose: () => void;
  onSave: (body: string, breathing: boolean, complexion: boolean, bedding: boolean) => Promise<boolean>;
}) {
  const [body, setBody] = useState(existing?.body_position ?? "supine");
  const [breathing, setBreathing] = useState(existing?.breathing ?? true);
  const [complexion, setComplexion] = useState(existing?.complexion ?? true);
  const [bedding, setBedding] = useState(existing?.bedding ?? true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/30 p-4">
      <div className="w-full max-w-sm rounded-2xl bg-white p-6 shadow-xl">
        <h3 className="text-base font-bold text-slate-800">
          {childName} {hm(slot)}
        </h3>
        <div className="mt-4">
          <label className="mb-1 block text-xs font-medium text-slate-500">身体の向き</label>
          <div className="flex flex-wrap gap-2">
            {Object.entries(NAP_BODY_POSITIONS).map(([k, v]) => (
              <button
                key={k}
                onClick={() => setBody(k)}
                className={`rounded-lg border px-3 py-1 text-sm ${
                  body === k ? "border-sky-400 bg-sky-50 text-sky-700" : "border-slate-300 text-slate-600"
                }`}
              >
                {v}
              </button>
            ))}
          </div>
        </div>
        <label className="mt-3 flex items-center gap-2 text-sm text-slate-700">
          <input type="checkbox" checked={breathing} onChange={(e) => setBreathing(e.target.checked)} /> 呼吸を確認
        </label>
        <label className="mt-2 flex items-center gap-2 text-sm text-slate-700">
          <input type="checkbox" checked={complexion} onChange={(e) => setComplexion(e.target.checked)} /> 顔色を確認
        </label>
        <label className="mt-2 flex items-center gap-2 text-sm text-slate-700">
          <input type="checkbox" checked={bedding} onChange={(e) => setBedding(e.target.checked)} /> 寝具の状態を確認
        </label>
        {error && <p className="mt-3 text-xs font-medium text-red-500">{error}</p>}
        <div className="mt-6 flex justify-end gap-2">
          <button
            onClick={onClose}
            className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-semibold text-slate-600 hover:bg-slate-50"
          >
            キャンセル
          </button>
          <button
            onClick={async () => {
              setSaving(true);
              setError(null);
              const ok = await onSave(body, breathing, complexion, bedding);
              if (!ok) {
                setSaving(false);
                setError("保存に失敗しました(過去日・30分超は主任以上のみ)");
              }
            }}
            disabled={saving}
            className="rounded-lg bg-sky-500 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-600 disabled:opacity-50"
          >
            {saving ? "保存中…" : "保存"}
          </button>
        </div>
      </div>
    </div>
  );
}

export default function ChildcareNapPage() {
  return (
    <Suspense fallback={null}>
      <ChildcareNapPageContent />
    </Suspense>
  );
}
