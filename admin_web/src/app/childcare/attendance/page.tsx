import { redirect } from "next/navigation";

// 「欠席選択」タブは廃止(K5/W7 整理)。欠席登録はデイリーボードの出欠編集(K7)へ集約。
// 旧URLのブックマーク救済のためデイリーボードへ恒久リダイレクトする。
export default function ChildcareAttendancePage() {
  redirect("/childcare/daily-board");
}
