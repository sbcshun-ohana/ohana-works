"use client";

import { useState } from "react";
import QRCode from "qrcode";
import { createClient } from "@/lib/supabase/client";

type Props = {
  childId: string;
  childName: string;
  onClose: () => void;
  onIssued?: () => void;
};

// 有効期限の選択肢。既定は7日(入園説明会で紙で渡す運用を想定)。
const TTL_OPTIONS = [
  { hours: 72, label: "3日間" },
  { hours: 168, label: "7日間" },
  { hours: 720, label: "30日間" },
] as const;

/// 保護者招待の発行+QR表示モーダル。QRの中身は招待コード(生トークン)そのもので、
/// 保護者アプリの「QRを読み取る」から取り込める。トークンはこの画面でのみ表示される
/// (DBにはハッシュのみ保存)。紛失時は無効化して再発行する(草案§7)。
export function InvitationQrModal({ childId, childName, onClose, onIssued }: Props) {
  const [role, setRole] = useState<"primary" | "additional">("primary");
  const [ttlHours, setTtlHours] = useState<number>(168);
  const [isIssuing, setIsIssuing] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [issued, setIssued] = useState<{ token: string; expiresAt: string; qrDataUrl: string } | null>(null);

  async function issueInvitation() {
    setIsIssuing(true);
    setErrorMessage(null);
    const supabase = createClient();
    const { data, error } = await supabase.rpc("create_guardian_invitation_by_staff", {
      p_child_id: childId,
      p_role: role,
      p_ttl_hours: ttlHours,
    });
    if (error) {
      setIsIssuing(false);
      setErrorMessage(error.message);
      return;
    }
    const result = (Array.isArray(data) ? data[0] : data) as { token: string; expires_at: string };
    const qrDataUrl = await QRCode.toDataURL(result.token, { width: 240, margin: 1 });
    setIsIssuing(false);
    setIssued({ token: result.token, expiresAt: result.expires_at, qrDataUrl });
    onIssued?.();
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 px-4">
      <div className="max-h-[85vh] w-full max-w-md overflow-y-auto rounded-2xl bg-white p-6 shadow-lg">
        <h2 className="mb-1 text-base font-bold text-slate-800">保護者招待QRの発行</h2>
        <p className="mb-4 text-sm text-slate-600">対象園児: {childName}</p>

        {!issued && (
          <div className="space-y-4">
            <div className="flex flex-wrap gap-4">
              <div>
                <label className="mb-1 block text-xs font-medium text-slate-500">役割</label>
                <select
                  value={role}
                  onChange={(e) => setRole(e.target.value as "primary" | "additional")}
                  className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
                >
                  <option value="primary">主たる保護者</option>
                  <option value="additional">追加保護者</option>
                </select>
              </div>
              <div>
                <label className="mb-1 block text-xs font-medium text-slate-500">有効期限</label>
                <select
                  value={ttlHours}
                  onChange={(e) => setTtlHours(Number(e.target.value))}
                  className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
                >
                  {TTL_OPTIONS.map((o) => (
                    <option key={o.hours} value={o.hours}>
                      {o.label}
                    </option>
                  ))}
                </select>
              </div>
            </div>
            <p className="text-xs text-slate-400">
              QRコード(招待コード)はこの画面でのみ表示されます。紛失した場合は招待を無効化して再発行してください。
              QRコードだけでは園児の個人情報は表示されません。
            </p>
            {errorMessage && <p className="text-sm font-medium text-red-500">{errorMessage}</p>}
            <div className="flex justify-end gap-3">
              <button
                onClick={onClose}
                className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50"
              >
                キャンセル
              </button>
              <button
                onClick={issueInvitation}
                disabled={isIssuing}
                className="rounded-lg bg-sky-500 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-600 disabled:opacity-60"
              >
                {isIssuing ? "発行中…" : "発行する"}
              </button>
            </div>
          </div>
        )}

        {issued && (
          <div className="space-y-4">
            <div className="flex flex-col items-center rounded-xl border border-slate-200 p-4">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={issued.qrDataUrl} alt="招待QRコード" className="h-60 w-60" />
              <p className="mt-2 break-all text-center font-mono text-xs text-slate-500">{issued.token}</p>
            </div>
            <div className="rounded-xl border border-amber-200 bg-amber-50 p-3 text-xs text-amber-900">
              <p className="font-semibold">
                この画面を閉じると再表示できません。印刷または保護者アプリでの読み取りが済んでから閉じてください。
              </p>
              <p className="mt-1">有効期限: {new Date(issued.expiresAt).toLocaleString("ja-JP")}</p>
            </div>
            <div className="flex justify-end gap-3">
              <button
                onClick={() => window.print()}
                className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50"
              >
                印刷
              </button>
              <button
                onClick={onClose}
                className="rounded-lg bg-sky-500 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-600"
              >
                閉じる
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
