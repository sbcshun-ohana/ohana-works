"use client";

import { Suspense, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { ChildcareNav } from "@/components/ChildcareNav";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";
import type {
  SupportChildcareAgencyLink,
  SupportChildcareApplicationDetail,
  SupportChildcareApplicationReview,
  SupportChildcareApplicationRow,
  SupportChildcareCandidatePoolRow,
  SupportChildcareCheckItem,
  SupportChildcareChildHeaderInfo,
  SupportChildcareForm2Term,
  SupportChildcareGuardianMeeting,
  SupportChildcareSubmissionSummary,
} from "@/lib/types";

const STATUS_LABELS: Record<string, string> = {
  candidate: "対象候補(未申請)",
  draft: "作成中",
  ai_draft: "作成中(AI下書きあり)",
  in_review: "確認中",
  returned: "差し戻し",
  approved: "承認済み(未確定)",
  finalized: "確定済み",
  released: "配布済み",
  superseded: "旧版",
  archived: "保管",
};

const CANDIDACY_LABELS: Record<string, string> = {
  candidate: "対象候補",
  under_review: "園内検討中",
  submission_target: "提出対象",
  excluded: "対象外",
};

// ラベルは原本xlsxのチェック項目の文言そのまま(巡回相談・発達相談の窓口は
// 大和市「すくすく子育て課発達支援係」が担当するため、その旨を明記する)。
const AGENCY_TYPE_LABELS: Record<string, string> = {
  patrol_consultation: "すくすく子育て課発達支援係の巡回相談にて相談している",
  developmental_consultation: "すくすく子育て課発達支援係で発達相談をしている",
  child_development_support_office: "児童発達支援事業所に通っている",
  facility_visit_support: "保育所等訪問支援が入っている",
};

// 区分ごとに必要な入力項目が異なる(原本xlsxで区分ごとに別レイアウトのため)
const AGENCY_FIELD_CONFIG: Record<
  string,
  {
    contactPersonLabel: string | null;
    showConsultationDate: boolean;
    showEnrollmentDate: boolean;
    showAgencyName: boolean;
    showFrequency: boolean;
    contentLabel: string;
  }
> = {
  patrol_consultation: {
    contactPersonLabel: "担当者",
    showConsultationDate: true,
    showEnrollmentDate: false,
    showAgencyName: false,
    showFrequency: false,
    contentLabel: "具体的な連携内容",
  },
  developmental_consultation: {
    contactPersonLabel: "担当者",
    showConsultationDate: true,
    showEnrollmentDate: false,
    showAgencyName: false,
    showFrequency: false,
    contentLabel: "具体的な連携内容",
  },
  child_development_support_office: {
    contactPersonLabel: null,
    showConsultationDate: false,
    showEnrollmentDate: true,
    showAgencyName: true,
    showFrequency: true,
    contentLabel: "具体的な連携内容(事業所等の担当者を含む)",
  },
  facility_visit_support: {
    contactPersonLabel: "担当心理士",
    showConsultationDate: false,
    showEnrollmentDate: false,
    showAgencyName: false,
    showFrequency: true,
    contentLabel: "具体的な連携内容",
  },
};

const TERM_FIELD_LABELS: { key: "child_behavior" | "considered_factors" | "support_measures" | "evaluation"; label: string }[] = [
  { key: "child_behavior", label: "子どもの姿" },
  { key: "considered_factors", label: "考えられる要因" },
  { key: "support_measures", label: "支援の手立て" },
  { key: "evaluation", label: "評価" },
];

function statusBadgeClass(status: string | null) {
  switch (status) {
    case "finalized":
    case "released":
      return "bg-emerald-50 text-emerald-700";
    case "returned":
      return "bg-red-50 text-red-600";
    case "in_review":
      return "bg-sky-50 text-sky-700";
    case "approved":
      return "bg-amber-50 text-amber-700";
    default:
      return "bg-slate-100 text-slate-500";
  }
}

function SupportChildcarePageContent() {
  const { offices, officesError, selectedOffice, setSelectedOffice } = useChildcareOffices(
    "fetch_my_support_childcare_offices",
  );
  const isManager = offices?.find((o) => o.office_id === selectedOffice)?.is_manager ?? false;

  const [programOfficeId, setProgramOfficeId] = useState<string>("");
  const [programOptions, setProgramOptions] = useState<{ program_office_id: string; label: string }[]>([]);

  const [rows, setRows] = useState<SupportChildcareApplicationRow[]>([]);
  const [rowsError, setRowsError] = useState<string | null>(null);
  const [summary, setSummary] = useState<SupportChildcareSubmissionSummary | null>(null);
  const [reloadToken, setReloadToken] = useState(0);

  const [selectedApplicationId, setSelectedApplicationId] = useState<string | null>(null);
  const [detail, setDetail] = useState<SupportChildcareApplicationDetail | null>(null);
  const [detailError, setDetailError] = useState<string | null>(null);
  const [childHeaderInfo, setChildHeaderInfo] = useState<SupportChildcareChildHeaderInfo | null>(null);
  const [terms, setTerms] = useState<SupportChildcareForm2Term[]>([]);
  const [checkItems, setCheckItems] = useState<SupportChildcareCheckItem[]>([]);
  const [checkedBehaviorIds, setCheckedBehaviorIds] = useState<string[]>([]);
  const [usePlanIds, setUsePlanIds] = useState<string[]>([]);
  const [usePlanOtherDetail, setUsePlanOtherDetail] = useState("");
  const [meetings, setMeetings] = useState<SupportChildcareGuardianMeeting[]>([]);
  const [agencyLinks, setAgencyLinks] = useState<SupportChildcareAgencyLink[]>([]);
  const [reviews, setReviews] = useState<SupportChildcareApplicationReview[]>([]);
  const [actionError, setActionError] = useState<string | null>(null);

  const [candidatePool, setCandidatePool] = useState<SupportChildcareCandidatePoolRow[] | null>(null);
  const [newAgencyType, setNewAgencyType] = useState<string>("patrol_consultation");

  // 施設の参加プログラム一覧(support_childcare_program_offices+programsを直接読み取り)
  useEffect(() => {
    if (!selectedOffice) return;
    const supabase = createClient();
    supabase
      .from("support_childcare_program_offices")
      .select("id, support_childcare_programs(fiscal_year, term, jurisdiction)")
      .eq("office_id", selectedOffice)
      .then(({ data, error }) => {
        if (error || !data) {
          setProgramOptions([]);
          return;
        }
        const opts = data.map((row) => {
          const program = row.support_childcare_programs as unknown as
            | { fiscal_year: number; term: string; jurisdiction: string }
            | null;
          return {
            program_office_id: row.id as string,
            label: program ? `${program.fiscal_year}年度${program.term}(${program.jurisdiction})` : "(不明な年度)",
          };
        });
        setProgramOptions(opts);
        setProgramOfficeId((prev) => (opts.some((o) => o.program_office_id === prev) ? prev : (opts[0]?.program_office_id ?? "")));
      });
  }, [selectedOffice]);

  // 一覧+提出票集計
  useEffect(() => {
    function load() {
      if (!programOfficeId) {
        setRows([]);
        setSummary(null);
        return;
      }
      const supabase = createClient();
      supabase.rpc("fetch_support_childcare_applications", { p_program_office_id: programOfficeId }).then(({ data, error }) => {
        if (error) {
          setRowsError(error.message);
          return;
        }
        setRowsError(null);
        setRows((data ?? []) as SupportChildcareApplicationRow[]);
      });
      supabase
        .rpc("fetch_support_childcare_submission_summary", { p_program_office_id: programOfficeId })
        .then(({ data, error }) => {
          if (!error && data && data.length > 0) {
            setSummary(data[0] as SupportChildcareSubmissionSummary);
          }
        });
    }
    load();
  }, [programOfficeId, reloadToken]);

  // チェック項目マスタ(初回のみ)
  useEffect(() => {
    const supabase = createClient();
    supabase
      .from("support_childcare_form1_check_items")
      .select("id, check_group, category, label, is_other_option, sort_order")
      .order("sort_order")
      .then(({ data, error }) => {
        if (!error) setCheckItems((data ?? []) as SupportChildcareCheckItem[]);
      });
  }, []);

  // 選択中の申請の詳細
  useEffect(() => {
    function load() {
      if (!selectedApplicationId) {
        setDetail(null);
        return;
      }
      const supabase = createClient();
      supabase
        .rpc("fetch_support_childcare_application_detail", { p_application_id: selectedApplicationId })
        .then(({ data, error }) => {
          if (error) {
            setDetailError(error.message);
            return;
          }
          setDetailError(null);
          const row = (data ?? [])[0] as SupportChildcareApplicationDetail | undefined;
          setDetail(row ?? null);
        });
      supabase
        .from("support_childcare_form2_terms")
        .select("id, form2_id, form1_id, term_number, term_goal, child_behavior, considered_factors, support_measures, evaluation")
        .order("term_number")
        .then(({ data, error }) => {
          // form2_idはdetail取得後に絞り込む(下のuseEffectで再フィルタ)
          if (!error) setTerms((data ?? []) as SupportChildcareForm2Term[]);
        });
      supabase
        .from("support_childcare_guardian_meetings")
        .select("id, meeting_date, attendee, content, guardian_intention")
        .eq("application_id", selectedApplicationId)
        .order("meeting_date", { ascending: false })
        .then(({ data, error }) => {
          if (!error) setMeetings((data ?? []) as SupportChildcareGuardianMeeting[]);
        });
      supabase
        .from("support_childcare_agency_links")
        .select("id, agency_type, contact_person, consultation_date, enrollment_start_date, agency_name, frequency, content, support_outcome")
        .eq("application_id", selectedApplicationId)
        .order("created_at", { ascending: false })
        .then(({ data, error }) => {
          if (!error) setAgencyLinks((data ?? []) as SupportChildcareAgencyLink[]);
        });
      supabase
        .from("support_childcare_application_reviews")
        .select("id, reviewer_id, review_type, action, comment, reviewed_at")
        .eq("application_id", selectedApplicationId)
        .order("reviewed_at", { ascending: false })
        .then(({ data, error }) => {
          if (!error) setReviews((data ?? []) as SupportChildcareApplicationReview[]);
        });
    }
    load();
  }, [selectedApplicationId, reloadToken]);

  // 様式2冒頭の児童氏名・生年月日・クラス名は既知の情報のため自動表示のみ(手入力欄にしない)
  useEffect(() => {
    function load() {
      if (!selectedApplicationId) {
        setChildHeaderInfo(null);
        return;
      }
      const supabase = createClient();
      supabase
        .from("support_childcare_applications")
        .select("support_childcare_candidates(child_id, class_id)")
        .eq("id", selectedApplicationId)
        .single()
        .then(({ data, error }) => {
          const cand = data?.support_childcare_candidates as unknown as
            | { child_id: string; class_id: string | null }
            | null;
          if (error || !cand) {
            setChildHeaderInfo(null);
            return;
          }
          supabase
            .from("children")
            .select("full_name, name_kana, birth_date, gender")
            .eq("id", cand.child_id)
            .single()
            .then(({ data: child, error: childError }) => {
              if (childError || !child) {
                setChildHeaderInfo(null);
                return;
              }
              if (!cand.class_id) {
                setChildHeaderInfo({ ...child, class_name: null, age_group: null });
                return;
              }
              supabase
                .from("childcare_classes")
                .select("class_name, age_group")
                .eq("id", cand.class_id)
                .single()
                .then(({ data: cls }) => {
                  setChildHeaderInfo({ ...child, class_name: cls?.class_name ?? null, age_group: cls?.age_group ?? null });
                });
            });
        });
    }
    load();
  }, [selectedApplicationId]);

  // form1に紐づくチェック・使途を取得(detail確定後)
  useEffect(() => {
    function load() {
      if (!detail?.form1_id) {
        setCheckedBehaviorIds([]);
        setUsePlanIds([]);
        setUsePlanOtherDetail("");
        return;
      }
      const supabase = createClient();
      supabase
        .from("support_childcare_form1_checks")
        .select("check_item_id")
        .eq("form1_id", detail.form1_id)
        .then(({ data, error }) => {
          if (!error) setCheckedBehaviorIds((data ?? []).map((r) => r.check_item_id as string));
        });
      supabase
        .from("support_childcare_use_plans")
        .select("check_item_id, other_detail")
        .eq("form1_id", detail.form1_id)
        .then(({ data, error }) => {
          if (!error) {
            const list = (data ?? []) as { check_item_id: string; other_detail: string | null }[];
            setUsePlanIds(list.map((r) => r.check_item_id));
            setUsePlanOtherDetail(list.find((r) => r.other_detail)?.other_detail ?? "");
          }
        });
    }
    load();
  }, [detail?.form1_id]);

  const termsForThisForm2 = terms.filter((t) => t.form2_id === detail?.form2_id);

  function reload() {
    setReloadToken((t) => t + 1);
  }

  async function openCandidatePool() {
    if (!programOfficeId) return;
    const supabase = createClient();
    const { data, error } = await supabase.rpc("fetch_support_childcare_candidate_pool", {
      p_program_office_id: programOfficeId,
    });
    if (error) {
      setActionError(error.message);
      return;
    }
    setCandidatePool((data ?? []) as SupportChildcareCandidatePoolRow[]);
  }

  async function addCandidate(childId: string, classId: string | null) {
    const supabase = createClient();
    const { error } = await supabase.rpc("add_support_childcare_candidate", {
      p_program_office_id: programOfficeId,
      p_child_id: childId,
      p_class_id: classId,
    });
    if (error) {
      setActionError(error.message);
      return;
    }
    setCandidatePool(null);
    reload();
  }

  async function createApplication(candidateId: string) {
    const supabase = createClient();
    const { data, error } = await supabase.rpc("create_support_childcare_application", { p_candidate_id: candidateId });
    if (error) {
      setActionError(error.message);
      return;
    }
    reload();
    setSelectedApplicationId(data as string);
  }

  async function saveForm1() {
    if (!detail) return;
    const supabase = createClient();
    const { error } = await supabase.rpc("update_support_childcare_form1", {
      p_application_id: detail.application_id,
      p_recorded_on: detail.form1_recorded_on,
      p_extra_staff_count_3: detail.form1_extra_staff_count_3,
      p_extra_staff_count_4: detail.form1_extra_staff_count_4,
      p_extra_staff_count_5: detail.form1_extra_staff_count_5,
      p_staff_count_3: detail.form1_staff_count_3,
      p_staff_count_4: detail.form1_staff_count_4,
      p_staff_count_5: detail.form1_staff_count_5,
      p_notes_3: detail.form1_notes_3,
      p_notes_4: detail.form1_notes_4,
      p_notes_5: detail.form1_notes_5,
      p_policy_stance_item_id: detail.form1_policy_stance_item_id,
      p_policy_target_month: detail.form1_policy_target_month,
      p_policy_no_extra_staff_reason: detail.form1_policy_no_extra_staff_reason,
      p_policy_no_application_reason: detail.form1_policy_no_application_reason,
      p_subsidy_expected_effect: detail.form1_subsidy_expected_effect,
    });
    if (error) {
      setActionError(error.message);
      return;
    }
    reload();
  }

  async function saveChecks() {
    if (!detail) return;
    const supabase = createClient();
    const { error } = await supabase.rpc("update_support_childcare_form1_checks", {
      p_form1_id: detail.form1_id,
      p_check_item_ids: checkedBehaviorIds,
    });
    if (error) setActionError(error.message);
  }

  async function saveUsePlans() {
    if (!detail) return;
    const supabase = createClient();
    const { error } = await supabase.rpc("update_support_childcare_use_plans", {
      p_form1_id: detail.form1_id,
      p_check_item_ids: usePlanIds,
      p_other_detail: usePlanOtherDetail || null,
    });
    if (error) setActionError(error.message);
  }

  async function saveForm2() {
    if (!detail) return;
    const supabase = createClient();
    const { error } = await supabase.rpc("update_support_childcare_form2", {
      p_application_id: detail.application_id,
      p_annual_goal: detail.form2_annual_goal,
    });
    if (error) {
      setActionError(error.message);
      return;
    }
    reload();
  }

  async function saveTerm(term: SupportChildcareForm2Term) {
    const supabase = createClient();
    const { error } = await supabase.rpc("update_support_childcare_form2_term", {
      p_term_id: term.id,
      p_term_goal: term.term_goal,
      p_child_behavior: term.child_behavior,
      p_considered_factors: term.considered_factors,
      p_support_measures: term.support_measures,
      p_evaluation: term.evaluation,
    });
    if (error) setActionError(error.message);
  }

  function updateTermField(termId: string, field: keyof SupportChildcareForm2Term, value: string) {
    setTerms((prev) => prev.map((t) => (t.id === termId ? { ...t, [field]: value } : t)));
  }

  async function generateDraft(term: SupportChildcareForm2Term, field: "child_behavior" | "considered_factors" | "support_measures" | "evaluation") {
    const supabase = createClient();
    const { data, error } = await supabase.rpc("generate_support_childcare_form2_term_draft", {
      p_term_id: term.id,
      p_field: field,
    });
    if (error) {
      setActionError(error.message);
      return;
    }
    const result = (data ?? [])[0] as { ai_run_id: string; output_text: string; evidence_count: number; low_evidence: boolean } | undefined;
    if (result) {
      updateTermField(term.id, field, result.output_text);
      window.alert(
        `AI下書き(モック)を反映しました。\n根拠件数: ${result.evidence_count}件${result.low_evidence ? "(根拠が少ないため参考程度にご確認ください)" : ""}\n\n内容を編集した場合は保存時に「編集」として、そのまま使う場合は「採用」として記録することをおすすめします。`,
      );
      await recordAiDecision(result.ai_run_id, "adopted");
    }
  }

  async function recordAiDecision(aiRunId: string, decision: "adopted" | "edited" | "regenerated" | "discarded") {
    const supabase = createClient();
    await supabase.rpc("record_ai_run_decision", { p_ai_run_id: aiRunId, p_decision: decision });
  }

  async function addMeeting(formData: FormData) {
    if (!detail) return;
    const supabase = createClient();
    const { error } = await supabase.rpc("record_support_childcare_guardian_meeting", {
      p_application_id: detail.application_id,
      p_meeting_date: formData.get("meeting_date"),
      p_attendee: formData.get("attendee") || null,
      p_content: formData.get("content") || null,
      p_guardian_intention: formData.get("guardian_intention") || null,
    });
    if (error) {
      setActionError(error.message);
      return;
    }
    reload();
  }

  async function addAgencyLink(formData: FormData) {
    if (!detail) return;
    const supabase = createClient();
    const { error } = await supabase.rpc("record_support_childcare_agency_link", {
      p_application_id: detail.application_id,
      p_agency_type: formData.get("agency_type"),
      p_contact_person: formData.get("contact_person") || null,
      p_consultation_date: formData.get("consultation_date") || null,
      p_enrollment_start_date: formData.get("enrollment_start_date") || null,
      p_agency_name: formData.get("agency_name") || null,
      p_frequency: formData.get("frequency") || null,
      p_content: formData.get("content") || null,
      p_support_outcome: formData.get("support_outcome") || null,
    });
    if (error) {
      setActionError(error.message);
      return;
    }
    reload();
  }

  async function submitForReview() {
    if (!detail) return;
    const supabase = createClient();
    const { error } = await supabase.rpc("submit_support_childcare_application_for_review", {
      p_application_id: detail.application_id,
    });
    if (error) {
      setActionError(error.message);
      return;
    }
    reload();
  }

  async function reviewAction(reviewType: "chief_check" | "multi_person_confirm", action: "approved" | "returned") {
    if (!detail) return;
    const comment = action === "returned" ? window.prompt("差し戻し理由を入力してください") : null;
    if (action === "returned" && !comment) return;
    const supabase = createClient();
    const { error } = await supabase.rpc("record_support_childcare_review", {
      p_application_id: detail.application_id,
      p_review_type: reviewType,
      p_action: action,
      p_comment: comment,
    });
    if (error) {
      setActionError(error.message);
      return;
    }
    reload();
  }

  async function approveFinal(action: "approved" | "returned") {
    if (!detail) return;
    const comment = action === "returned" ? window.prompt("差し戻し理由を入力してください") : null;
    if (action === "returned" && !comment) return;
    const supabase = createClient();
    const { error } = await supabase.rpc("approve_support_childcare_application_final", {
      p_application_id: detail.application_id,
      p_action: action,
      p_comment: comment,
    });
    if (error) {
      setActionError(error.message);
      return;
    }
    reload();
  }

  async function finalizeApplication() {
    if (!detail) return;
    if (!window.confirm("確定すると内容を凍結します。よろしいですか?")) return;
    const supabase = createClient();
    const { error } = await supabase.rpc("finalize_support_childcare_application", {
      p_application_id: detail.application_id,
    });
    if (error) {
      setActionError(error.message);
      return;
    }
    reload();
  }

  const editable = detail ? !["finalized", "released", "superseded", "archived"].includes(detail.status) : false;
  const policyItems = checkItems.filter((c) => c.check_group === "policy_stance");
  const subsidyItems = checkItems.filter((c) => c.check_group === "subsidy_use");
  const behaviorItems = checkItems.filter((c) => c.check_group === "child_behavior");
  const behaviorCategories = Array.from(new Set(behaviorItems.map((b) => b.category ?? "")));

  return (
    <div className="flex flex-1 flex-col">
      <AppHeader />
      <ChildcareNav />
      <main className="flex-1 space-y-6 p-6">
        <div className="flex flex-wrap items-center gap-3">
          <select
            value={selectedOffice}
            onChange={(e) => setSelectedOffice(e.target.value)}
            className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
          >
            {offices?.map((office) => (
              <option key={office.office_id} value={office.office_id}>
                {office.office_name}
              </option>
            ))}
          </select>
          <select
            value={programOfficeId}
            onChange={(e) => {
              setProgramOfficeId(e.target.value);
              setSelectedApplicationId(null);
            }}
            className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
          >
            {programOptions.length === 0 && <option value="">開設中の年度・期がありません</option>}
            {programOptions.map((opt) => (
              <option key={opt.program_office_id} value={opt.program_office_id}>
                {opt.label}
              </option>
            ))}
          </select>
          <button
            onClick={openCandidatePool}
            disabled={!programOfficeId}
            className="rounded-lg bg-sky-600 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-700 disabled:opacity-40"
          >
            対象候補を追加
          </button>
        </div>

        {officesError && <p className="text-sm text-red-600">{officesError}</p>}
        {rowsError && <p className="text-sm text-red-600">{rowsError}</p>}
        {actionError && (
          <p className="rounded-lg bg-red-50 px-3 py-2 text-sm text-red-600">{actionError}</p>
        )}

        {summary && (
          <div className="grid grid-cols-4 gap-3">
            <div className="rounded-2xl bg-white p-4 shadow-sm">
              <p className="text-xs text-slate-500">3歳児</p>
              <p className="text-xl font-bold text-slate-800">{summary.age_3_count}</p>
            </div>
            <div className="rounded-2xl bg-white p-4 shadow-sm">
              <p className="text-xs text-slate-500">4歳児</p>
              <p className="text-xl font-bold text-slate-800">{summary.age_4_count}</p>
            </div>
            <div className="rounded-2xl bg-white p-4 shadow-sm">
              <p className="text-xs text-slate-500">5歳児</p>
              <p className="text-xl font-bold text-slate-800">{summary.age_5_count}</p>
            </div>
            <div className="rounded-2xl bg-white p-4 shadow-sm">
              <p className="text-xs text-slate-500">提出対象合計</p>
              <p className="text-xl font-bold text-slate-800">{summary.total_count}</p>
            </div>
          </div>
        )}

        <div className="grid grid-cols-1 gap-6 md:grid-cols-3">
          <div className="md:col-span-1">
            <div className="overflow-x-auto rounded-2xl bg-white shadow-sm">
              <table className="min-w-full text-sm">
                <thead>
                  <tr className="border-b border-slate-200 text-left text-xs font-semibold text-slate-500">
                    <th className="px-4 py-3">園児</th>
                    <th className="px-4 py-3">候補状態</th>
                    <th className="px-4 py-3">申請状態</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((row) => (
                    <tr
                      key={row.child_id}
                      onClick={() => row.application_id && setSelectedApplicationId(row.application_id)}
                      className={`cursor-pointer border-b border-slate-100 last:border-0 hover:bg-slate-50 ${
                        row.application_id === selectedApplicationId ? "bg-sky-50" : ""
                      }`}
                    >
                      <td className="px-4 py-3 font-medium text-slate-800">{row.child_name}</td>
                      <td className="px-4 py-3 text-slate-500">{CANDIDACY_LABELS[row.candidacy_status]}</td>
                      <td className="px-4 py-3">
                        {row.application_id ? (
                          <span className={`rounded-full px-2 py-0.5 text-xs font-semibold ${statusBadgeClass(row.status)}`}>
                            {STATUS_LABELS[row.status ?? ""] ?? row.status}
                          </span>
                        ) : (
                          <button
                            onClick={(e) => {
                              e.stopPropagation();
                              const candId = rows.find((r) => r.child_id === row.child_id);
                              if (candId) void createApplication(row.child_id);
                            }}
                            className="rounded-lg border border-sky-300 px-2 py-1 text-xs font-medium text-sky-600 hover:bg-sky-50"
                          >
                            申請作成
                          </button>
                        )}
                      </td>
                    </tr>
                  ))}
                  {rows.length === 0 && (
                    <tr>
                      <td colSpan={3} className="px-4 py-6 text-center text-sm text-slate-400">
                        対象候補がありません
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          </div>

          <div className="md:col-span-2 space-y-6">
            {!detail && <p className="text-sm text-slate-400">左の一覧から申請を選択してください</p>}
            {detailError && <p className="text-sm text-red-600">{detailError}</p>}

            {detail && (
              <>
                <div className="rounded-2xl bg-white p-4 shadow-sm">
                  <div className="mb-3 flex items-center justify-between">
                    <h2 className="text-base font-bold text-slate-800">{detail.child_name}</h2>
                    <span className={`rounded-full px-2 py-0.5 text-xs font-semibold ${statusBadgeClass(detail.status)}`}>
                      {STATUS_LABELS[detail.status] ?? detail.status}
                    </span>
                  </div>
                  <div className="flex flex-wrap gap-2">
                    {editable && (detail.status === "draft" || detail.status === "ai_draft" || detail.status === "returned") && (
                      <button onClick={submitForReview} className="rounded-lg bg-sky-600 px-3 py-1.5 text-xs font-semibold text-white hover:bg-sky-700">
                        提出(確認へ)
                      </button>
                    )}
                    {isManager && detail.status === "in_review" && (
                      <>
                        <button onClick={() => reviewAction("chief_check", "approved")} className="rounded-lg bg-emerald-600 px-3 py-1.5 text-xs font-semibold text-white hover:bg-emerald-700">
                          主任確認(承認)
                        </button>
                        <button onClick={() => reviewAction("chief_check", "returned")} className="rounded-lg border border-red-300 px-3 py-1.5 text-xs font-medium text-red-600 hover:bg-red-50">
                          主任確認(差戻)
                        </button>
                      </>
                    )}
                    {detail.status === "in_review" && (
                      <>
                        <button onClick={() => reviewAction("multi_person_confirm", "approved")} className="rounded-lg bg-emerald-600 px-3 py-1.5 text-xs font-semibold text-white hover:bg-emerald-700">
                          複数名確認(承認)
                        </button>
                        <button onClick={() => reviewAction("multi_person_confirm", "returned")} className="rounded-lg border border-red-300 px-3 py-1.5 text-xs font-medium text-red-600 hover:bg-red-50">
                          複数名確認(差戻)
                        </button>
                        <button onClick={() => approveFinal("approved")} className="rounded-lg bg-indigo-600 px-3 py-1.5 text-xs font-semibold text-white hover:bg-indigo-700">
                          最終承認
                        </button>
                        <button onClick={() => approveFinal("returned")} className="rounded-lg border border-red-300 px-3 py-1.5 text-xs font-medium text-red-600 hover:bg-red-50">
                          最終承認(差戻)
                        </button>
                      </>
                    )}
                    {detail.status === "approved" && (
                      <button onClick={finalizeApplication} className="rounded-lg bg-slate-800 px-3 py-1.5 text-xs font-semibold text-white hover:bg-slate-900">
                        確定する
                      </button>
                    )}
                  </div>
                  {reviews.length > 0 && (
                    <div className="mt-3 space-y-1 border-t border-slate-100 pt-3 text-xs text-slate-500">
                      {reviews.map((r) => (
                        <p key={r.id}>
                          {r.review_type === "chief_check" ? "主任確認" : "複数名確認"} — {r.action === "approved" ? "承認" : "差戻"}
                          {r.comment ? `(${r.comment})` : ""}
                        </p>
                      ))}
                    </div>
                  )}
                </div>

                {/* 様式1 */}
                <div className="space-y-4 rounded-2xl bg-white p-4 shadow-sm">
                  <h3 className="text-sm font-bold text-slate-800">様式1: 集団生活で支援を必要とする子どもの姿</h3>
                  <div>
                    <label className="mb-1 block text-xs text-slate-500">記入日</label>
                    <input
                      type="date"
                      disabled={!editable}
                      value={detail.form1_recorded_on ?? ""}
                      onChange={(e) => setDetail({ ...detail, form1_recorded_on: e.target.value })}
                      className="w-48 rounded-lg border border-slate-300 px-2 py-1.5 text-sm disabled:bg-slate-50"
                    />
                  </div>

                  {/* クラス編成・職員配置: 3・4・5歳児クラスごとに加配児童数・職員数・備考が別入力 */}
                  <div className="overflow-x-auto">
                    <table className="min-w-full text-sm">
                      <thead>
                        <tr className="border-b border-slate-200 text-left text-xs font-semibold text-slate-500">
                          <th className="px-2 py-1">クラス</th>
                          <th className="px-2 py-1">加配児童数</th>
                          <th className="px-2 py-1">職員数</th>
                          <th className="px-2 py-1">備考</th>
                        </tr>
                      </thead>
                      <tbody>
                        {(["3", "4", "5"] as const).map((age) => (
                          <tr key={age} className="border-b border-slate-100 last:border-0">
                            <td className="px-2 py-1 font-medium text-slate-700">{age}歳児クラス</td>
                            <td className="px-2 py-1">
                              <input
                                type="number"
                                disabled={!editable}
                                value={detail[`form1_extra_staff_count_${age}` as keyof SupportChildcareApplicationDetail] as number | null ?? ""}
                                onChange={(e) =>
                                  setDetail({ ...detail, [`form1_extra_staff_count_${age}`]: e.target.value ? Number(e.target.value) : null })
                                }
                                className="w-20 rounded-lg border border-slate-300 px-2 py-1.5 text-sm disabled:bg-slate-50"
                              />
                            </td>
                            <td className="px-2 py-1">
                              <input
                                type="number"
                                disabled={!editable}
                                value={detail[`form1_staff_count_${age}` as keyof SupportChildcareApplicationDetail] as number | null ?? ""}
                                onChange={(e) =>
                                  setDetail({ ...detail, [`form1_staff_count_${age}`]: e.target.value ? Number(e.target.value) : null })
                                }
                                className="w-20 rounded-lg border border-slate-300 px-2 py-1.5 text-sm disabled:bg-slate-50"
                              />
                            </td>
                            <td className="px-2 py-1">
                              <input
                                type="text"
                                disabled={!editable}
                                value={(detail[`form1_notes_${age}` as keyof SupportChildcareApplicationDetail] as string | null) ?? ""}
                                onChange={(e) => setDetail({ ...detail, [`form1_notes_${age}`]: e.target.value })}
                                className="w-full min-w-[10rem] rounded-lg border border-slate-300 px-2 py-1.5 text-sm disabled:bg-slate-50"
                              />
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>

                  <div>
                    <p className="mb-1 text-xs font-semibold text-slate-600">＜1＞保育園の今後の方針</p>
                    <div className="space-y-1">
                      {policyItems.map((item, index) => (
                        <label key={item.id} className="flex items-center gap-2 text-sm text-slate-700">
                          <input
                            type="radio"
                            disabled={!editable}
                            checked={detail.form1_policy_stance_item_id === item.id}
                            onChange={() => setDetail({ ...detail, form1_policy_stance_item_id: item.id })}
                          />
                          {item.label}
                          {index === 3 && <span className="text-xs text-slate-400">(入力欄は任意)</span>}
                        </label>
                      ))}
                    </div>
                    {/* 選択したラジオボタンに応じて必要な入力欄のみ表示する。
                        1番目=目途必須、2番目=目途+配置困難理由必須、3番目=配置困難理由必須、4番目=いずれも不要(理由欄は任意で表示) */}
                    {(() => {
                      const selectedIndex = policyItems.findIndex((p) => p.id === detail.form1_policy_stance_item_id);
                      if (selectedIndex < 0) return null;
                      const needsTargetMonth = selectedIndex === 0 || selectedIndex === 1;
                      const needsNoStaffReason = selectedIndex === 1 || selectedIndex === 2;
                      const showNoApplicationReason = selectedIndex === 3;
                      const requiredClass = "border-amber-400 bg-amber-50";
                      const normalClass = "border-slate-300";
                      return (
                        <div className="mt-2 grid grid-cols-1 gap-2 md:grid-cols-3">
                          {needsTargetMonth && (
                            <div>
                              <label className="mb-1 block text-xs font-semibold text-amber-700">目途(令和何年何月頃)【必須】</label>
                              <input
                                disabled={!editable}
                                value={detail.form1_policy_target_month ?? ""}
                                onChange={(e) => setDetail({ ...detail, form1_policy_target_month: e.target.value })}
                                className={`w-full rounded-lg border px-2 py-1.5 text-sm disabled:bg-slate-50 ${requiredClass}`}
                              />
                            </div>
                          )}
                          {needsNoStaffReason && (
                            <div>
                              <label className="mb-1 block text-xs font-semibold text-amber-700">保育士配置が困難な理由【必須】</label>
                              <input
                                disabled={!editable}
                                value={detail.form1_policy_no_extra_staff_reason ?? ""}
                                onChange={(e) => setDetail({ ...detail, form1_policy_no_extra_staff_reason: e.target.value })}
                                className={`w-full rounded-lg border px-2 py-1.5 text-sm disabled:bg-slate-50 ${requiredClass}`}
                              />
                            </div>
                          )}
                          {showNoApplicationReason && (
                            <div>
                              <label className="mb-1 block text-xs text-slate-500">申請しない理由(任意)</label>
                              <input
                                disabled={!editable}
                                value={detail.form1_policy_no_application_reason ?? ""}
                                onChange={(e) => setDetail({ ...detail, form1_policy_no_application_reason: e.target.value })}
                                className={`w-full rounded-lg border px-2 py-1.5 text-sm disabled:bg-slate-50 ${normalClass}`}
                              />
                            </div>
                          )}
                        </div>
                      );
                    })()}
                  </div>

                  <div>
                    <p className="mb-1 text-xs font-semibold text-slate-600">対象児童に対する補助金の使用方法</p>
                    <div className="space-y-1">
                      {subsidyItems.map((item) => (
                        <label key={item.id} className="flex items-center gap-2 text-sm text-slate-700">
                          <input
                            type="checkbox"
                            disabled={!editable}
                            checked={usePlanIds.includes(item.id)}
                            onChange={(e) =>
                              setUsePlanIds((prev) => (e.target.checked ? [...prev, item.id] : prev.filter((id) => id !== item.id)))
                            }
                          />
                          {item.label}
                        </label>
                      ))}
                    </div>
                    {usePlanIds.some((id) => subsidyItems.find((i) => i.id === id)?.is_other_option) && (
                      <input
                        placeholder="その他の内容"
                        disabled={!editable}
                        value={usePlanOtherDetail}
                        onChange={(e) => setUsePlanOtherDetail(e.target.value)}
                        className="mt-2 w-full rounded-lg border border-slate-300 px-2 py-1.5 text-sm disabled:bg-slate-50"
                      />
                    )}
                    <textarea
                      placeholder="対象児童が受ける支援効果の見込み"
                      disabled={!editable}
                      rows={2}
                      value={detail.form1_subsidy_expected_effect ?? ""}
                      onChange={(e) => setDetail({ ...detail, form1_subsidy_expected_effect: e.target.value })}
                      className="mt-2 w-full rounded-lg border border-slate-300 px-2 py-1.5 text-sm disabled:bg-slate-50"
                    />
                  </div>

                  <div>
                    <p className="mb-1 text-xs font-semibold text-slate-600">＜4＞子どもの姿</p>
                    {behaviorCategories.map((category) => (
                      <div key={category} className="mb-2">
                        <p className="mb-1 text-xs text-slate-500">{category}</p>
                        <div className="space-y-1">
                          {behaviorItems
                            .filter((b) => b.category === category)
                            .map((item) => (
                              <label key={item.id} className="flex items-start gap-2 text-sm text-slate-700">
                                <input
                                  type="checkbox"
                                  disabled={!editable}
                                  checked={checkedBehaviorIds.includes(item.id)}
                                  onChange={(e) =>
                                    setCheckedBehaviorIds((prev) =>
                                      e.target.checked ? [...prev, item.id] : prev.filter((id) => id !== item.id),
                                    )
                                  }
                                />
                                <span>{item.label}</span>
                              </label>
                            ))}
                        </div>
                      </div>
                    ))}
                  </div>

                  {editable && (
                    <button
                      onClick={async () => {
                        await saveForm1();
                        await saveChecks();
                        await saveUsePlans();
                      }}
                      className="rounded-lg bg-sky-600 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-700"
                    >
                      様式1を保存
                    </button>
                  )}
                </div>

                {/* 様式2 */}
                <div className="space-y-4 rounded-2xl bg-white p-4 shadow-sm">
                  <h3 className="text-sm font-bold text-slate-800">様式2: 個別支援計画及び発達経過記録</h3>
                  {childHeaderInfo && (
                    <div className="grid grid-cols-2 gap-2 rounded-lg bg-slate-50 p-3 text-xs text-slate-600 md:grid-cols-4">
                      <p>児童氏名: {childHeaderInfo.full_name}</p>
                      <p>生年月日: {childHeaderInfo.birth_date}</p>
                      <p>クラス名: {childHeaderInfo.class_name ?? "-"}</p>
                      <p>年齢: {childHeaderInfo.age_group ?? "-"}</p>
                    </div>
                  )}
                  <div>
                    <label className="mb-1 block text-xs text-slate-500">年間目標</label>
                    <textarea
                      disabled={!editable}
                      rows={2}
                      value={detail.form2_annual_goal ?? ""}
                      onChange={(e) => setDetail({ ...detail, form2_annual_goal: e.target.value })}
                      className="w-full rounded-lg border border-slate-300 px-2 py-1.5 text-sm disabled:bg-slate-50"
                    />
                    {editable && (
                      <button onClick={saveForm2} className="mt-2 rounded-lg border border-slate-300 px-3 py-1.5 text-xs font-medium text-slate-600 hover:bg-slate-100">
                        年間目標を保存
                      </button>
                    )}
                  </div>

                  {termsForThisForm2.map((term) => (
                    <div key={term.id} className="rounded-xl border border-slate-200 p-3">
                      <p className="mb-2 text-xs font-semibold text-slate-600">第{term.term_number}期</p>
                      <input
                        placeholder="期の目標"
                        disabled={!editable}
                        value={term.term_goal ?? ""}
                        onChange={(e) => updateTermField(term.id, "term_goal", e.target.value)}
                        className="mb-2 w-full rounded-lg border border-slate-300 px-2 py-1.5 text-sm disabled:bg-slate-50"
                      />
                      {TERM_FIELD_LABELS.map(({ key, label }) => (
                        <div key={key} className="mb-2">
                          <div className="mb-1 flex items-center justify-between">
                            <label className="text-xs text-slate-500">{label}</label>
                            {editable && (
                              <button
                                onClick={() => generateDraft(term, key)}
                                className="rounded-lg border border-indigo-300 px-2 py-0.5 text-xs font-medium text-indigo-600 hover:bg-indigo-50"
                              >
                                AI下書き(モック)
                              </button>
                            )}
                          </div>
                          <textarea
                            disabled={!editable}
                            rows={2}
                            value={(term[key] as string) ?? ""}
                            onChange={(e) => updateTermField(term.id, key, e.target.value)}
                            className="w-full rounded-lg border border-slate-300 px-2 py-1.5 text-sm disabled:bg-slate-50"
                          />
                        </div>
                      ))}
                      {editable && (
                        <button
                          onClick={() => saveTerm(term)}
                          className="rounded-lg border border-slate-300 px-3 py-1.5 text-xs font-medium text-slate-600 hover:bg-slate-100"
                        >
                          第{term.term_number}期を保存
                        </button>
                      )}
                    </div>
                  ))}
                </div>

                {/* 保護者面談(すべて正式面談として記録。送迎時の会話は支援記録として認められないため選択肢自体を廃止) */}
                <div className="space-y-3 rounded-2xl bg-white p-4 shadow-sm">
                  <h3 className="text-sm font-bold text-slate-800">＜2＞保護者との連携(面談記録)</h3>
                  {meetings.map((m) => (
                    <div key={m.id} className="rounded-lg border border-slate-100 p-2 text-sm">
                      <p className="text-xs text-slate-500">{m.meeting_date} 面談者: {m.attendee ?? "-"}</p>
                      <p className="text-slate-700">{m.content}</p>
                      {m.guardian_intention && <p className="mt-1 whitespace-pre-wrap text-slate-500">保護者の意向: {m.guardian_intention}</p>}
                    </div>
                  ))}
                  {editable && (
                    <form
                      action={(fd) => {
                        void addMeeting(fd);
                      }}
                      className="grid grid-cols-1 gap-2 rounded-lg bg-slate-50 p-3 md:grid-cols-2"
                    >
                      <input name="meeting_date" type="date" required className="rounded-lg border border-slate-300 px-2 py-1.5 text-sm" />
                      <input name="attendee" placeholder="面談者" className="rounded-lg border border-slate-300 px-2 py-1.5 text-sm" />
                      <textarea
                        name="content"
                        placeholder="面談内容(現在の支援の状況、今後に向けて等)"
                        rows={4}
                        className="md:col-span-2 rounded-lg border border-slate-300 px-2 py-1.5 text-sm"
                      />
                      <textarea
                        name="guardian_intention"
                        placeholder="保護者の意向"
                        rows={4}
                        className="md:col-span-2 rounded-lg border border-slate-300 px-2 py-1.5 text-sm"
                      />
                      <button type="submit" className="md:col-span-2 rounded-lg bg-sky-600 px-3 py-1.5 text-xs font-semibold text-white hover:bg-sky-700">
                        面談記録を追加
                      </button>
                    </form>
                  )}
                </div>

                {/* 関係機関連携: 区分(4種類)ごとに必要な入力項目が異なる */}
                <div className="space-y-3 rounded-2xl bg-white p-4 shadow-sm">
                  <h3 className="text-sm font-bold text-slate-800">＜3＞関係機関との連携</h3>
                  {agencyLinks.map((a) => {
                    const cfg = AGENCY_FIELD_CONFIG[a.agency_type];
                    return (
                      <div key={a.id} className="rounded-lg border border-slate-100 p-2 text-sm">
                        <p className="text-xs text-slate-500">
                          {AGENCY_TYPE_LABELS[a.agency_type]}
                          {cfg.showAgencyName && a.agency_name ? ` / 事業所名: ${a.agency_name}` : ""}
                          {cfg.contactPersonLabel && a.contact_person ? ` / ${cfg.contactPersonLabel}: ${a.contact_person}` : ""}
                          {cfg.showConsultationDate && a.consultation_date ? ` / 直近の相談日: ${a.consultation_date}` : ""}
                          {cfg.showEnrollmentDate && a.enrollment_start_date ? ` / 通所開始日: ${a.enrollment_start_date}` : ""}
                          {cfg.showFrequency && a.frequency ? ` / 頻度: ${a.frequency}` : ""}
                        </p>
                        <p className="text-slate-700">{a.content}</p>
                        {a.support_outcome && <p className="text-slate-500">連携をとおした具体的な支援内容: {a.support_outcome}</p>}
                      </div>
                    );
                  })}
                  {editable && (
                    <form
                      key={newAgencyType}
                      action={(fd) => {
                        void addAgencyLink(fd);
                      }}
                      className="grid grid-cols-1 gap-2 rounded-lg bg-slate-50 p-3 md:grid-cols-2"
                    >
                      <select
                        name="agency_type"
                        value={newAgencyType}
                        onChange={(e) => setNewAgencyType(e.target.value)}
                        className="md:col-span-2 rounded-lg border border-slate-300 px-2 py-1.5 text-sm"
                      >
                        {Object.entries(AGENCY_TYPE_LABELS).map(([value, label]) => (
                          <option key={value} value={value}>
                            {label}
                          </option>
                        ))}
                      </select>
                      {AGENCY_FIELD_CONFIG[newAgencyType].contactPersonLabel && (
                        <input
                          name="contact_person"
                          placeholder={AGENCY_FIELD_CONFIG[newAgencyType].contactPersonLabel ?? ""}
                          className="rounded-lg border border-slate-300 px-2 py-1.5 text-sm"
                        />
                      )}
                      {AGENCY_FIELD_CONFIG[newAgencyType].showConsultationDate && (
                        <input
                          name="consultation_date"
                          type="date"
                          placeholder="直近の相談日"
                          className="rounded-lg border border-slate-300 px-2 py-1.5 text-sm"
                        />
                      )}
                      {AGENCY_FIELD_CONFIG[newAgencyType].showEnrollmentDate && (
                        <input
                          name="enrollment_start_date"
                          type="date"
                          placeholder="通所開始日"
                          className="rounded-lg border border-slate-300 px-2 py-1.5 text-sm"
                        />
                      )}
                      {AGENCY_FIELD_CONFIG[newAgencyType].showAgencyName && (
                        <input
                          name="agency_name"
                          placeholder="事業所名"
                          className="rounded-lg border border-slate-300 px-2 py-1.5 text-sm"
                        />
                      )}
                      {AGENCY_FIELD_CONFIG[newAgencyType].showFrequency && (
                        <input name="frequency" placeholder="頻度" className="rounded-lg border border-slate-300 px-2 py-1.5 text-sm" />
                      )}
                      <textarea
                        name="content"
                        placeholder={AGENCY_FIELD_CONFIG[newAgencyType].contentLabel}
                        className="md:col-span-2 rounded-lg border border-slate-300 px-2 py-1.5 text-sm"
                      />
                      <textarea
                        name="support_outcome"
                        placeholder="連携をとおした具体的な支援内容"
                        className="md:col-span-2 rounded-lg border border-slate-300 px-2 py-1.5 text-sm"
                      />
                      <button type="submit" className="md:col-span-2 rounded-lg bg-sky-600 px-3 py-1.5 text-xs font-semibold text-white hover:bg-sky-700">
                        連携記録を追加
                      </button>
                    </form>
                  )}
                </div>
              </>
            )}
          </div>
        </div>

        {candidatePool && (
          <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 px-4">
            <div className="max-h-[80vh] w-full max-w-lg overflow-y-auto rounded-2xl bg-white p-6 shadow-lg">
              <div className="mb-4 flex items-center justify-between">
                <h2 className="text-base font-bold text-slate-800">対象候補を追加</h2>
                <button onClick={() => setCandidatePool(null)} className="text-sm text-slate-400 hover:text-slate-600">
                  閉じる
                </button>
              </div>
              <div className="space-y-2">
                {candidatePool.map((c) => (
                  <div key={c.child_id} className="flex items-center justify-between rounded-lg border border-slate-200 p-2 text-sm">
                    <div>
                      <p className="font-medium text-slate-800">{c.child_name}</p>
                      <p className="text-xs text-slate-500">{c.class_name ?? "未所属"}</p>
                    </div>
                    <button
                      onClick={() => addCandidate(c.child_id, c.class_id)}
                      className="rounded-lg bg-sky-600 px-3 py-1 text-xs font-semibold text-white hover:bg-sky-700"
                    >
                      追加
                    </button>
                  </div>
                ))}
                {candidatePool.length === 0 && <p className="text-sm text-slate-400">追加可能な園児がいません</p>}
              </div>
            </div>
          </div>
        )}
      </main>
    </div>
  );
}

export default function SupportChildcarePage() {
  return (
    <Suspense fallback={null}>
      <SupportChildcarePageContent />
    </Suspense>
  );
}
