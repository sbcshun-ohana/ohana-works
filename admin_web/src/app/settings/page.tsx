"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { parseWithholdingTaxCsv, type ParseResult } from "@/lib/import/withholdingTaxCsv";
import {
  parseEmployeeMasterCsv,
  type ParseResult as EmployeeParseResult,
} from "@/lib/import/employeeMasterCsv";
import {
  parseFacilityWageCsv,
  type ParseResult as FacilityWageParseResult,
} from "@/lib/import/facilityWageCsv";
import {
  parseFacilityAllowanceCsv,
  type ParseResult as FacilityAllowanceParseResult,
} from "@/lib/import/facilityAllowanceCsv";
import {
  parseTaxWithholdingCsv,
  type ParseResult as TaxWithholdingParseResult,
} from "@/lib/import/taxWithholdingCsv";
import {
  parseStandardMonthlyRemunerationCsv,
  type ParseResult as SmrParseResult,
} from "@/lib/import/standardMonthlyRemunerationCsv";
import {
  parseInsuranceEnrollmentCsv,
  type ParseResult as EnrollmentParseResult,
} from "@/lib/import/insuranceEnrollmentCsv";
import {
  parseResidentTaxCsv,
  type ParseResult as ResidentTaxParseResult,
} from "@/lib/import/residentTaxCsv";
import {
  parseCommuteCsv,
  type ParseResult as CommuteParseResult,
} from "@/lib/import/commuteCsv";

type ImportHistoryItem = {
  id: string;
  file_name: string;
  imported_by_name: string | null;
  imported_at: string;
  target_period: string;
  imported_count: number;
};

type EmployeeImportHistoryItem = {
  id: string;
  file_name: string;
  imported_by_name: string | null;
  imported_at: string;
  target_period: string;
  imported_count: number;
  detail: { inserted?: number; updated?: number } | null;
};

type MasterOption = { id: string; name: string };
type EmployeeDirectoryEntry = { employee_number: string; name: string; home_office_id: string };

type BulkImportHistoryItem = {
  id: string;
  file_name: string;
  imported_by_name: string | null;
  imported_at: string;
  imported_count: number;
};

function currentYearMonth(): string {
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`;
}

export default function SettingsPage() {
  const [canManage, setCanManage] = useState<boolean | null>(null);

  const [fileName, setFileName] = useState<string | null>(null);
  const [parseResult, setParseResult] = useState<ParseResult | null>(null);
  const [effectiveYearMonth, setEffectiveYearMonth] = useState(currentYearMonth());

  const [isApplying, setIsApplying] = useState(false);
  const [applyError, setApplyError] = useState<string | null>(null);
  const [applySuccess, setApplySuccess] = useState<string | null>(null);

  const [history, setHistory] = useState<ImportHistoryItem[]>([]);
  const [historyError, setHistoryError] = useState<string | null>(null);
  const [reloadToken, setReloadToken] = useState(0);

  const [offices, setOffices] = useState<MasterOption[]>([]);
  const [employmentTypes, setEmploymentTypes] = useState<MasterOption[]>([]);
  const [employeeFileName, setEmployeeFileName] = useState<string | null>(null);
  const [employeeParseResult, setEmployeeParseResult] = useState<EmployeeParseResult | null>(null);
  const [isApplyingEmployees, setIsApplyingEmployees] = useState(false);
  const [employeeApplyError, setEmployeeApplyError] = useState<string | null>(null);
  const [employeeApplySuccess, setEmployeeApplySuccess] = useState<string | null>(null);
  const [employeeHistory, setEmployeeHistory] = useState<EmployeeImportHistoryItem[]>([]);
  const [employeeHistoryError, setEmployeeHistoryError] = useState<string | null>(null);
  const [employeeReloadToken, setEmployeeReloadToken] = useState(0);

  const [employeeDirectory, setEmployeeDirectory] = useState<EmployeeDirectoryEntry[]>([]);
  const [allowanceMasters, setAllowanceMasters] = useState<MasterOption[]>([]);

  const [wageFileName, setWageFileName] = useState<string | null>(null);
  const [wageParseResult, setWageParseResult] = useState<FacilityWageParseResult | null>(null);
  const [isApplyingWages, setIsApplyingWages] = useState(false);
  const [wageApplyError, setWageApplyError] = useState<string | null>(null);
  const [wageApplySuccess, setWageApplySuccess] = useState<string | null>(null);
  const [wageHistory, setWageHistory] = useState<BulkImportHistoryItem[]>([]);
  const [wageReloadToken, setWageReloadToken] = useState(0);

  const [allowanceFileName, setAllowanceFileName] = useState<string | null>(null);
  const [allowanceParseResult, setAllowanceParseResult] = useState<FacilityAllowanceParseResult | null>(null);
  const [isApplyingAllowances, setIsApplyingAllowances] = useState(false);
  const [allowanceApplyError, setAllowanceApplyError] = useState<string | null>(null);
  const [allowanceApplySuccess, setAllowanceApplySuccess] = useState<string | null>(null);
  const [allowanceHistory, setAllowanceHistory] = useState<BulkImportHistoryItem[]>([]);
  const [allowanceReloadToken, setAllowanceReloadToken] = useState(0);

  const [taxFileName, setTaxFileName] = useState<string | null>(null);
  const [taxParseResult, setTaxParseResult] = useState<TaxWithholdingParseResult | null>(null);
  const [isApplyingTax, setIsApplyingTax] = useState(false);
  const [taxApplyError, setTaxApplyError] = useState<string | null>(null);
  const [taxApplySuccess, setTaxApplySuccess] = useState<string | null>(null);
  const [taxHistory, setTaxHistory] = useState<BulkImportHistoryItem[]>([]);
  const [taxReloadToken, setTaxReloadToken] = useState(0);

  const [smrFileName, setSmrFileName] = useState<string | null>(null);
  const [smrParseResult, setSmrParseResult] = useState<SmrParseResult | null>(null);
  const [isApplyingSmr, setIsApplyingSmr] = useState(false);
  const [smrApplyError, setSmrApplyError] = useState<string | null>(null);
  const [smrApplySuccess, setSmrApplySuccess] = useState<string | null>(null);

  const [enrollFileName, setEnrollFileName] = useState<string | null>(null);
  const [enrollParseResult, setEnrollParseResult] = useState<EnrollmentParseResult | null>(null);
  const [isApplyingEnroll, setIsApplyingEnroll] = useState(false);
  const [enrollApplyError, setEnrollApplyError] = useState<string | null>(null);
  const [enrollApplySuccess, setEnrollApplySuccess] = useState<string | null>(null);

  const [residentFileName, setResidentFileName] = useState<string | null>(null);
  const [residentParseResult, setResidentParseResult] = useState<ResidentTaxParseResult | null>(null);
  const [isApplyingResident, setIsApplyingResident] = useState(false);
  const [residentApplyError, setResidentApplyError] = useState<string | null>(null);
  const [residentApplySuccess, setResidentApplySuccess] = useState<string | null>(null);

  const [socialInsuranceHistory, setSocialInsuranceHistory] = useState<
    (BulkImportHistoryItem & { import_target: string })[]
  >([]);
  const [socialInsuranceReloadToken, setSocialInsuranceReloadToken] = useState(0);

  const [commuteFileName, setCommuteFileName] = useState<string | null>(null);
  const [commuteParseResult, setCommuteParseResult] = useState<CommuteParseResult | null>(null);
  const [isApplyingCommute, setIsApplyingCommute] = useState(false);
  const [commuteApplyError, setCommuteApplyError] = useState<string | null>(null);
  const [commuteApplySuccess, setCommuteApplySuccess] = useState<string | null>(null);
  const [commuteHistory, setCommuteHistory] = useState<BulkImportHistoryItem[]>([]);
  const [commuteReloadToken, setCommuteReloadToken] = useState(0);

  useEffect(() => {
    const supabase = createClient();
    supabase.rpc("is_labor_manager_plus").then(({ data, error }) => {
      setCanManage(error ? false : Boolean(data));
    });
  }, []);

  useEffect(() => {
    if (!canManage) return;
    const supabase = createClient();
    supabase.rpc("fetch_withholding_tax_import_history").then(({ data, error }) => {
      if (error) {
        setHistoryError(error.message);
        return;
      }
      setHistory((data ?? []) as ImportHistoryItem[]);
    });
  }, [canManage, reloadToken]);

  useEffect(() => {
    if (!canManage) return;
    const supabase = createClient();
    supabase
      .from("offices")
      .select("id, name")
      .then(({ data, error }) => {
        if (!error) setOffices((data ?? []) as MasterOption[]);
      });
    supabase
      .from("employment_types")
      .select("id, name")
      .eq("is_active", true)
      .then(({ data, error }) => {
        if (!error) setEmploymentTypes((data ?? []) as MasterOption[]);
      });
  }, [canManage]);

  useEffect(() => {
    if (!canManage) return;
    const supabase = createClient();
    supabase.rpc("fetch_employee_import_history").then(({ data, error }) => {
      if (error) {
        setEmployeeHistoryError(error.message);
        return;
      }
      setEmployeeHistory((data ?? []) as EmployeeImportHistoryItem[]);
    });
  }, [canManage, employeeReloadToken]);

  useEffect(() => {
    if (!canManage) return;
    const supabase = createClient();
    supabase.rpc("fetch_employee_directory").then(({ data, error }) => {
      if (!error) setEmployeeDirectory((data ?? []) as EmployeeDirectoryEntry[]);
    });
    supabase.rpc("fetch_allowance_masters").then(({ data, error }) => {
      if (!error) setAllowanceMasters((data ?? []) as MasterOption[]);
    });
  }, [canManage]);

  useEffect(() => {
    if (!canManage) return;
    const supabase = createClient();
    supabase.rpc("fetch_employee_facility_wages_import_history").then(({ data, error }) => {
      if (!error) setWageHistory((data ?? []) as BulkImportHistoryItem[]);
    });
  }, [canManage, wageReloadToken]);

  useEffect(() => {
    if (!canManage) return;
    const supabase = createClient();
    supabase.rpc("fetch_employee_commutes_import_history").then(({ data, error }) => {
      if (!error) setCommuteHistory((data ?? []) as BulkImportHistoryItem[]);
    });
  }, [canManage, commuteReloadToken]);

  useEffect(() => {
    if (!canManage) return;
    const supabase = createClient();
    supabase.rpc("fetch_employee_facility_allowances_import_history").then(({ data, error }) => {
      if (!error) setAllowanceHistory((data ?? []) as BulkImportHistoryItem[]);
    });
  }, [canManage, allowanceReloadToken]);

  useEffect(() => {
    if (!canManage) return;
    const supabase = createClient();
    supabase.rpc("fetch_employee_tax_withholding_import_history").then(({ data, error }) => {
      if (!error) setTaxHistory((data ?? []) as BulkImportHistoryItem[]);
    });
  }, [canManage, taxReloadToken]);

  useEffect(() => {
    if (!canManage) return;
    const supabase = createClient();
    supabase.rpc("fetch_social_insurance_import_history").then(({ data, error }) => {
      if (!error) setSocialInsuranceHistory((data ?? []) as (BulkImportHistoryItem & { import_target: string })[]);
    });
  }, [canManage, socialInsuranceReloadToken]);

  async function handleFileChange(event: React.ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    if (!file) return;
    setApplyError(null);
    setApplySuccess(null);
    setFileName(file.name);
    const text = await file.text();
    setParseResult(parseWithholdingTaxCsv(text));
  }

  async function handleApply() {
    if (!parseResult || parseResult.errors.length > 0 || parseResult.rows.length === 0) return;
    setIsApplying(true);
    setApplyError(null);
    setApplySuccess(null);

    const supabase = createClient();
    const { error } = await supabase.rpc("import_withholding_tax_table", {
      p_file_name: fileName,
      p_effective_start_year_month: `${effectiveYearMonth}-01`,
      p_rows: parseResult.rows,
    });

    setIsApplying(false);
    if (error) {
      setApplyError(error.message);
      return;
    }
    setApplySuccess(`${parseResult.wideRows.length}件の賃金帯(甲欄8区分+乙欄8区分=${parseResult.rows.length}行)を反映しました`);
    setParseResult(null);
    setFileName(null);
    setReloadToken((t) => t + 1);
  }

  async function handleEmployeeFileChange(event: React.ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    if (!file) return;
    setEmployeeApplyError(null);
    setEmployeeApplySuccess(null);
    setEmployeeFileName(file.name);
    const text = await file.text();
    setEmployeeParseResult(parseEmployeeMasterCsv(text, offices, employmentTypes));
  }

  async function handleApplyEmployees() {
    if (!employeeParseResult || employeeParseResult.errors.length > 0 || employeeParseResult.rows.length === 0) {
      return;
    }
    setIsApplyingEmployees(true);
    setEmployeeApplyError(null);
    setEmployeeApplySuccess(null);

    const supabase = createClient();
    const { data, error } = await supabase.rpc("import_employees_csv", {
      p_file_name: employeeFileName,
      p_rows: employeeParseResult.rows,
    });

    setIsApplyingEmployees(false);
    if (error) {
      setEmployeeApplyError(error.message);
      return;
    }
    const result = data as { inserted_count: number; updated_count: number };
    setEmployeeApplySuccess(
      `${employeeParseResult.rows.length}件を反映しました(新規登録${result.inserted_count}件・上書き更新${result.updated_count}件)`,
    );
    setEmployeeParseResult(null);
    setEmployeeFileName(null);
    setEmployeeReloadToken((t) => t + 1);
  }

  async function handleWageFileChange(event: React.ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    if (!file) return;
    setWageApplyError(null);
    setWageApplySuccess(null);
    setWageFileName(file.name);
    const text = await file.text();
    setWageParseResult(parseFacilityWageCsv(text, offices, employeeDirectory));
  }

  async function handleApplyWages() {
    if (!wageParseResult || wageParseResult.errors.length > 0 || wageParseResult.rows.length === 0) return;
    setIsApplyingWages(true);
    setWageApplyError(null);
    setWageApplySuccess(null);

    const supabase = createClient();
    const { data, error } = await supabase.rpc("import_employee_facility_wages_csv", {
      p_file_name: wageFileName,
      p_rows: wageParseResult.rows,
    });

    setIsApplyingWages(false);
    if (error) {
      setWageApplyError(error.message);
      return;
    }
    const result = data as { imported_count: number };
    setWageApplySuccess(`${result.imported_count}件の施設別基本給を反映しました`);
    setWageParseResult(null);
    setWageFileName(null);
    setWageReloadToken((t) => t + 1);
  }

  async function handleCommuteFileChange(event: React.ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    if (!file) return;
    setCommuteApplyError(null);
    setCommuteApplySuccess(null);
    setCommuteFileName(file.name);
    const text = await file.text();
    setCommuteParseResult(parseCommuteCsv(text, offices, employeeDirectory));
  }

  async function handleApplyCommute() {
    if (!commuteParseResult || commuteParseResult.errors.length > 0 || commuteParseResult.rows.length === 0) return;
    setIsApplyingCommute(true);
    setCommuteApplyError(null);
    setCommuteApplySuccess(null);

    const supabase = createClient();
    const { data, error } = await supabase.rpc("import_employee_commutes_csv", {
      p_file_name: commuteFileName,
      p_rows: commuteParseResult.rows,
    });

    setIsApplyingCommute(false);
    if (error) {
      setCommuteApplyError(error.message);
      return;
    }
    const result = data as { imported_count: number };
    setCommuteApplySuccess(`${result.imported_count}件の通勤費を反映しました`);
    setCommuteParseResult(null);
    setCommuteFileName(null);
    setCommuteReloadToken((t) => t + 1);
  }

  async function handleAllowanceFileChange(event: React.ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    if (!file) return;
    setAllowanceApplyError(null);
    setAllowanceApplySuccess(null);
    setAllowanceFileName(file.name);
    const text = await file.text();
    setAllowanceParseResult(parseFacilityAllowanceCsv(text, offices, employeeDirectory, allowanceMasters));
  }

  async function handleApplyAllowances() {
    if (!allowanceParseResult || allowanceParseResult.errors.length > 0 || allowanceParseResult.rows.length === 0) {
      return;
    }
    setIsApplyingAllowances(true);
    setAllowanceApplyError(null);
    setAllowanceApplySuccess(null);

    const supabase = createClient();
    const { data, error } = await supabase.rpc("import_employee_facility_allowances_csv", {
      p_file_name: allowanceFileName,
      p_rows: allowanceParseResult.rows,
    });

    setIsApplyingAllowances(false);
    if (error) {
      setAllowanceApplyError(error.message);
      return;
    }
    const result = data as { imported_count: number };
    setAllowanceApplySuccess(`${result.imported_count}件の施設別手当を反映しました`);
    setAllowanceParseResult(null);
    setAllowanceFileName(null);
    setAllowanceReloadToken((t) => t + 1);
  }

  async function handleTaxFileChange(event: React.ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    if (!file) return;
    setTaxApplyError(null);
    setTaxApplySuccess(null);
    setTaxFileName(file.name);
    const text = await file.text();
    setTaxParseResult(parseTaxWithholdingCsv(text, employeeDirectory));
  }

  async function handleApplyTax() {
    if (!taxParseResult || taxParseResult.errors.length > 0 || taxParseResult.rows.length === 0) return;
    setIsApplyingTax(true);
    setTaxApplyError(null);
    setTaxApplySuccess(null);

    const supabase = createClient();
    const { data, error } = await supabase.rpc("import_employee_tax_withholding_csv", {
      p_file_name: taxFileName,
      p_rows: taxParseResult.rows,
    });

    setIsApplyingTax(false);
    if (error) {
      setTaxApplyError(error.message);
      return;
    }
    const result = data as { imported_count: number };
    setTaxApplySuccess(`${result.imported_count}件の源泉徴収区分・扶養人数を反映しました`);
    setTaxParseResult(null);
    setTaxFileName(null);
    setTaxReloadToken((t) => t + 1);
  }

  async function handleSmrFileChange(event: React.ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    if (!file) return;
    setSmrApplyError(null);
    setSmrApplySuccess(null);
    setSmrFileName(file.name);
    const text = await file.text();
    setSmrParseResult(parseStandardMonthlyRemunerationCsv(text, employeeDirectory));
  }

  async function handleApplySmr() {
    if (!smrParseResult || smrParseResult.errors.length > 0 || smrParseResult.rows.length === 0) return;
    setIsApplyingSmr(true);
    setSmrApplyError(null);
    setSmrApplySuccess(null);

    const supabase = createClient();
    const { data, error } = await supabase.rpc("import_standard_monthly_remunerations_csv", {
      p_file_name: smrFileName,
      p_rows: smrParseResult.rows,
    });

    setIsApplyingSmr(false);
    if (error) {
      setSmrApplyError(error.message);
      return;
    }
    const result = data as { imported_count: number };
    setSmrApplySuccess(`${result.imported_count}件の標準報酬月額を反映しました`);
    setSmrParseResult(null);
    setSmrFileName(null);
    setSocialInsuranceReloadToken((t) => t + 1);
  }

  async function handleEnrollFileChange(event: React.ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    if (!file) return;
    setEnrollApplyError(null);
    setEnrollApplySuccess(null);
    setEnrollFileName(file.name);
    const text = await file.text();
    setEnrollParseResult(parseInsuranceEnrollmentCsv(text, employeeDirectory));
  }

  async function handleApplyEnroll() {
    if (!enrollParseResult || enrollParseResult.errors.length > 0 || enrollParseResult.rows.length === 0) return;
    setIsApplyingEnroll(true);
    setEnrollApplyError(null);
    setEnrollApplySuccess(null);

    const supabase = createClient();
    const { data, error } = await supabase.rpc("import_insurance_enrollments_csv", {
      p_file_name: enrollFileName,
      p_rows: enrollParseResult.rows,
    });

    setIsApplyingEnroll(false);
    if (error) {
      setEnrollApplyError(error.message);
      return;
    }
    const result = data as { imported_count: number };
    setEnrollApplySuccess(`${result.imported_count}件の保険加入状況を反映しました`);
    setEnrollParseResult(null);
    setEnrollFileName(null);
    setSocialInsuranceReloadToken((t) => t + 1);
  }

  async function handleResidentFileChange(event: React.ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    if (!file) return;
    setResidentApplyError(null);
    setResidentApplySuccess(null);
    setResidentFileName(file.name);
    const text = await file.text();
    setResidentParseResult(parseResidentTaxCsv(text, employeeDirectory));
  }

  async function handleApplyResident() {
    if (!residentParseResult || residentParseResult.errors.length > 0 || residentParseResult.rows.length === 0) {
      return;
    }
    setIsApplyingResident(true);
    setResidentApplyError(null);
    setResidentApplySuccess(null);

    const supabase = createClient();
    const { data, error } = await supabase.rpc("import_resident_taxes_csv", {
      p_file_name: residentFileName,
      p_rows: residentParseResult.rows,
    });

    setIsApplyingResident(false);
    if (error) {
      setResidentApplyError(error.message);
      return;
    }
    const result = data as { imported_count: number; row_count: number };
    setResidentApplySuccess(`${result.row_count}行(${result.imported_count}件の年度別レコード)の住民税を反映しました`);
    setResidentParseResult(null);
    setResidentFileName(null);
    setSocialInsuranceReloadToken((t) => t + 1);
  }

  if (canManage === null) {
    return (
      <div className="flex flex-1 flex-col">
        <AppHeader />
        <div className="p-8 text-sm text-slate-400">読み込み中…</div>
      </div>
    );
  }

  if (!canManage) {
    return (
      <div className="flex flex-1 flex-col">
        <AppHeader />
        <div className="p-8 text-sm text-slate-500">
          この機能を利用する権限がありません(労務管理者以上が必要です)。
        </div>
      </div>
    );
  }

  return (
    <div className="flex flex-1 flex-col">
      <AppHeader />
      <main className="flex-1 space-y-6 p-6">
        <h2 className="text-lg font-bold text-slate-800">マスタ設定・ファイル読込</h2>

        <div className="space-y-4 rounded-2xl bg-white p-6 shadow-sm">
          <h3 className="text-base font-bold text-slate-800">源泉所得税額表(月額表)CSV取込</h3>
          <p className="text-xs text-slate-400">
            1賃金帯=1行のCSV(ヘッダー: wage_lower_bound,wage_upper_bound,kou_dep0〜kou_dep7plus,otsu_amount)を
            読み込みます。国税庁公表の月額表(甲欄0〜7人以上・乙欄)を基に作成したファイルをアップロードしてください。
            最終行のwage_upper_boundは上限なしを表す空欄にしてください。読込後は必ず内容を確認してから反映してください
            (自動確定は行いません)。
          </p>

          <div className="flex flex-wrap items-end gap-4">
            <div>
              <label className="mb-1 block text-xs font-medium text-slate-500">CSVファイル</label>
              <input
                type="file"
                accept=".csv,text/csv"
                onChange={handleFileChange}
                className="text-sm"
              />
            </div>
            <div>
              <label className="mb-1 block text-xs font-medium text-slate-500">適用開始年月</label>
              <input
                type="month"
                value={effectiveYearMonth}
                onChange={(e) => setEffectiveYearMonth(e.target.value)}
                className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
              />
            </div>
          </div>

          {parseResult && (
            <div className="space-y-2 rounded-xl border border-slate-200 p-4">
              <p className="text-sm font-semibold text-slate-700">プレビュー</p>
              <dl className="grid grid-cols-2 gap-2 text-sm text-slate-600 sm:grid-cols-4">
                <div>
                  <dt className="text-xs text-slate-400">ファイル名</dt>
                  <dd>{fileName}</dd>
                </div>
                <div>
                  <dt className="text-xs text-slate-400">対象年月</dt>
                  <dd>{effectiveYearMonth}</dd>
                </div>
                <div>
                  <dt className="text-xs text-slate-400">取込件数(賃金帯)</dt>
                  <dd>{parseResult.wideRows.length}件</dd>
                </div>
                <div>
                  <dt className="text-xs text-slate-400">反映予定行数</dt>
                  <dd>{parseResult.rows.length}行</dd>
                </div>
              </dl>

              {parseResult.errors.length > 0 && (
                <div>
                  <p className="text-xs font-semibold text-red-500">エラー {parseResult.errors.length}件(反映不可)</p>
                  <ul className="list-disc pl-5 text-xs text-red-500">
                    {parseResult.errors.slice(0, 20).map((e, i) => (
                      <li key={i}>{e}</li>
                    ))}
                  </ul>
                </div>
              )}
              {parseResult.warnings.length > 0 && (
                <div>
                  <p className="text-xs font-semibold text-amber-600">警告 {parseResult.warnings.length}件</p>
                  <ul className="list-disc pl-5 text-xs text-amber-600">
                    {parseResult.warnings.slice(0, 20).map((w, i) => (
                      <li key={i}>{w}</li>
                    ))}
                  </ul>
                </div>
              )}

              {parseResult.wideRows.length > 0 && (
                <div className="overflow-x-auto">
                  <table className="min-w-full text-xs">
                    <thead>
                      <tr className="border-b border-slate-200 text-left text-slate-400">
                        <th className="px-2 py-1">賃金帯(以上〜未満)</th>
                        <th className="px-2 py-1">甲欄0人</th>
                        <th className="px-2 py-1">甲欄7人以上</th>
                        <th className="px-2 py-1">乙欄</th>
                      </tr>
                    </thead>
                    <tbody>
                      {parseResult.wideRows.slice(0, 5).map((w, i) => (
                        <tr key={i} className="border-b border-slate-100">
                          <td className="px-2 py-1">
                            {w.wageLowerBound}円〜{w.wageUpperBound ?? "上限なし"}
                          </td>
                          <td className="px-2 py-1">{w.kouAmounts[0]}円</td>
                          <td className="px-2 py-1">{w.kouAmounts[7]}円</td>
                          <td className="px-2 py-1">{w.otsuAmount}円</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                  {parseResult.wideRows.length > 5 && (
                    <p className="mt-1 text-xs text-slate-400">他{parseResult.wideRows.length - 5}件…</p>
                  )}
                </div>
              )}

              <button
                onClick={handleApply}
                disabled={isApplying || parseResult.errors.length > 0 || parseResult.rows.length === 0}
                className="rounded-lg bg-sky-500 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-600 disabled:opacity-60"
              >
                {isApplying ? "反映中…" : "この内容で反映する"}
              </button>
            </div>
          )}

          {applyError && <p className="text-sm font-medium text-red-500">{applyError}</p>}
          {applySuccess && <p className="text-sm font-medium text-emerald-600">{applySuccess}</p>}
        </div>

        <div className="space-y-4 rounded-2xl bg-white p-6 shadow-sm">
          <h3 className="text-base font-bold text-slate-800">職員マスタCSV取込</h3>
          <p className="text-xs text-slate-400">
            1職員=1行のCSV(ヘッダー: employee_number,last_name,first_name,last_name_kana,
            first_name_kana,birth_date,hire_date,office_id,employment_type,full_time_flag,
            base_salary)を読み込みます。office_idは施設UUID、employment_typeは雇用形態名
            (完全一致)、full_time_flagはtrue/false、birth_date/base_salaryは空欄可です。
            既存のemployee_numberは内容を上書き更新します。読込後は必ず内容を確認してから
            反映してください(自動確定は行いません)。
          </p>

          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">CSVファイル</label>
            <input
              type="file"
              accept=".csv,text/csv"
              onChange={handleEmployeeFileChange}
              className="text-sm"
            />
          </div>

          {employeeParseResult && (
            <div className="space-y-2 rounded-xl border border-slate-200 p-4">
              <p className="text-sm font-semibold text-slate-700">プレビュー</p>
              <dl className="grid grid-cols-2 gap-2 text-sm text-slate-600 sm:grid-cols-4">
                <div>
                  <dt className="text-xs text-slate-400">ファイル名</dt>
                  <dd>{employeeFileName}</dd>
                </div>
                <div>
                  <dt className="text-xs text-slate-400">取込件数(職員)</dt>
                  <dd>{employeeParseResult.rows.length}件</dd>
                </div>
              </dl>

              {employeeParseResult.errors.length > 0 && (
                <div>
                  <p className="text-xs font-semibold text-red-500">
                    エラー {employeeParseResult.errors.length}件(反映不可)
                  </p>
                  <ul className="list-disc pl-5 text-xs text-red-500">
                    {employeeParseResult.errors.slice(0, 20).map((e, i) => (
                      <li key={i}>{e}</li>
                    ))}
                  </ul>
                </div>
              )}
              {employeeParseResult.warnings.length > 0 && (
                <div>
                  <p className="text-xs font-semibold text-amber-600">
                    警告 {employeeParseResult.warnings.length}件
                  </p>
                  <ul className="list-disc pl-5 text-xs text-amber-600">
                    {employeeParseResult.warnings.slice(0, 20).map((w, i) => (
                      <li key={i}>{w}</li>
                    ))}
                  </ul>
                </div>
              )}

              {employeeParseResult.rows.length > 0 && (
                <div className="overflow-x-auto">
                  <table className="min-w-full text-xs">
                    <thead>
                      <tr className="border-b border-slate-200 text-left text-slate-400">
                        <th className="px-2 py-1">職員番号</th>
                        <th className="px-2 py-1">氏名</th>
                        <th className="px-2 py-1">施設</th>
                        <th className="px-2 py-1">雇用形態</th>
                        <th className="px-2 py-1">区分</th>
                        <th className="px-2 py-1">基本給</th>
                      </tr>
                    </thead>
                    <tbody>
                      {employeeParseResult.rows.slice(0, 5).map((r, i) => (
                        <tr key={i} className="border-b border-slate-100">
                          <td className="px-2 py-1">{r.employee_number}</td>
                          <td className="px-2 py-1">
                            {r.name}
                            {r.name_kana ? `(${r.name_kana})` : ""}
                          </td>
                          <td className="px-2 py-1">{r.office_name}</td>
                          <td className="px-2 py-1">{r.employment_type_name}</td>
                          <td className="px-2 py-1">{r.full_time_flag ? "フルタイム" : "パート"}</td>
                          <td className="px-2 py-1">{r.base_salary != null ? `${r.base_salary}円` : "—"}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                  {employeeParseResult.rows.length > 5 && (
                    <p className="mt-1 text-xs text-slate-400">他{employeeParseResult.rows.length - 5}件…</p>
                  )}
                </div>
              )}

              <button
                onClick={handleApplyEmployees}
                disabled={
                  isApplyingEmployees ||
                  employeeParseResult.errors.length > 0 ||
                  employeeParseResult.rows.length === 0
                }
                className="rounded-lg bg-sky-500 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-600 disabled:opacity-60"
              >
                {isApplyingEmployees ? "反映中…" : "この内容で反映する"}
              </button>
            </div>
          )}

          {employeeApplyError && <p className="text-sm font-medium text-red-500">{employeeApplyError}</p>}
          {employeeApplySuccess && <p className="text-sm font-medium text-emerald-600">{employeeApplySuccess}</p>}

          <div className="space-y-3 border-t border-slate-100 pt-4">
            <p className="text-sm font-semibold text-slate-700">反映履歴</p>
            {employeeHistoryError && <p className="text-sm font-medium text-red-500">{employeeHistoryError}</p>}
            {employeeHistory.length === 0 && <p className="text-sm text-slate-400">まだ取込履歴はありません</p>}
            <ul className="divide-y divide-slate-100">
              {employeeHistory.map((h) => (
                <li key={h.id} className="py-2 text-sm text-slate-600">
                  {h.file_name}
                  {" ・ "}
                  {h.imported_count}件
                  {h.detail ? ` (新規${h.detail.inserted ?? 0}・更新${h.detail.updated ?? 0})` : ""}
                  {" ・ "}
                  {h.imported_by_name ?? "(不明)"}
                  {" ・ "}
                  {new Date(h.imported_at).toLocaleString("ja-JP")}
                </li>
              ))}
            </ul>
          </div>
        </div>

        <div className="space-y-4 rounded-2xl bg-white p-6 shadow-sm">
          <h3 className="text-base font-bold text-slate-800">施設別基本給 一括CSV取込</h3>
          <p className="text-xs text-slate-400">
            1施設×1職員=1行のCSV(ヘッダー: employee_number,office_id,salary_type,monthly_base_salary,
            hourly_wage,effective_start_date)を読み込みます。兼務職員は施設数分の行を用意してください。
            月給の場合はmonthly_base_salaryのみ、時給の場合はhourly_wageのみを指定し、他方は空欄にします。
          </p>

          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">CSVファイル</label>
            <input type="file" accept=".csv,text/csv" onChange={handleWageFileChange} className="text-sm" />
          </div>

          {wageParseResult && (
            <div className="space-y-2 rounded-xl border border-slate-200 p-4">
              <p className="text-sm font-semibold text-slate-700">プレビュー</p>
              <dl className="grid grid-cols-2 gap-2 text-sm text-slate-600 sm:grid-cols-4">
                <div>
                  <dt className="text-xs text-slate-400">ファイル名</dt>
                  <dd>{wageFileName}</dd>
                </div>
                <div>
                  <dt className="text-xs text-slate-400">取込件数</dt>
                  <dd>{wageParseResult.rows.length}件</dd>
                </div>
              </dl>

              {wageParseResult.errors.length > 0 && (
                <div>
                  <p className="text-xs font-semibold text-red-500">エラー {wageParseResult.errors.length}件(反映不可)</p>
                  <ul className="list-disc pl-5 text-xs text-red-500">
                    {wageParseResult.errors.slice(0, 20).map((e, i) => (
                      <li key={i}>{e}</li>
                    ))}
                  </ul>
                </div>
              )}

              {wageParseResult.rows.length > 0 && (
                <div className="overflow-x-auto">
                  <table className="min-w-full text-xs">
                    <thead>
                      <tr className="border-b border-slate-200 text-left text-slate-400">
                        <th className="px-2 py-1">職員</th>
                        <th className="px-2 py-1">施設</th>
                        <th className="px-2 py-1">給与形態</th>
                        <th className="px-2 py-1">金額</th>
                      </tr>
                    </thead>
                    <tbody>
                      {wageParseResult.rows.slice(0, 8).map((r, i) => (
                        <tr key={i} className="border-b border-slate-100">
                          <td className="px-2 py-1">{r.employee_name}</td>
                          <td className="px-2 py-1">{r.office_name}</td>
                          <td className="px-2 py-1">{r.salary_type}</td>
                          <td className="px-2 py-1">
                            {r.salary_type === "月給" ? `${r.monthly_base_salary}円/月` : `${r.hourly_wage}円/時`}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                  {wageParseResult.rows.length > 8 && (
                    <p className="mt-1 text-xs text-slate-400">他{wageParseResult.rows.length - 8}件…</p>
                  )}
                </div>
              )}

              <button
                onClick={handleApplyWages}
                disabled={isApplyingWages || wageParseResult.errors.length > 0 || wageParseResult.rows.length === 0}
                className="rounded-lg bg-sky-500 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-600 disabled:opacity-60"
              >
                {isApplyingWages ? "反映中…" : "この内容で反映する"}
              </button>
            </div>
          )}

          {wageApplyError && <p className="text-sm font-medium text-red-500">{wageApplyError}</p>}
          {wageApplySuccess && <p className="text-sm font-medium text-emerald-600">{wageApplySuccess}</p>}

          <div className="space-y-3 border-t border-slate-100 pt-4">
            <p className="text-sm font-semibold text-slate-700">反映履歴</p>
            {wageHistory.length === 0 && <p className="text-sm text-slate-400">まだ取込履歴はありません</p>}
            <ul className="divide-y divide-slate-100">
              {wageHistory.map((h) => (
                <li key={h.id} className="py-2 text-sm text-slate-600">
                  {h.file_name}
                  {" ・ "}
                  {h.imported_count}件
                  {" ・ "}
                  {h.imported_by_name ?? "(不明)"}
                  {" ・ "}
                  {new Date(h.imported_at).toLocaleString("ja-JP")}
                </li>
              ))}
            </ul>
          </div>
        </div>

        <div className="space-y-4 rounded-2xl bg-white p-6 shadow-sm">
          <h3 className="text-base font-bold text-slate-800">通勤費 一括CSV取込</h3>
          <p className="text-xs text-slate-400">
            1職員=1行のCSV(ヘッダー: employee_number,office_id,commute_method,calc_type,unit_price,
            taxable_limit,effective_start_date)を読み込みます。通勤費は所属施設(home_office_id)からのみ支給されるため、
            office_idは対象職員の所属施設と一致させてください。calc_typeはfixed_monthly(月額固定)または
            per_day_roundtrip(日額×出勤日数)、commute_method・taxable_limitは空欄可です。
          </p>

          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">CSVファイル</label>
            <input type="file" accept=".csv,text/csv" onChange={handleCommuteFileChange} className="text-sm" />
          </div>

          {commuteParseResult && (
            <div className="space-y-2 rounded-xl border border-slate-200 p-4">
              <p className="text-sm font-semibold text-slate-700">プレビュー</p>
              <dl className="grid grid-cols-2 gap-2 text-sm text-slate-600 sm:grid-cols-4">
                <div>
                  <dt className="text-xs text-slate-400">ファイル名</dt>
                  <dd>{commuteFileName}</dd>
                </div>
                <div>
                  <dt className="text-xs text-slate-400">取込件数</dt>
                  <dd>{commuteParseResult.rows.length}件</dd>
                </div>
              </dl>

              {commuteParseResult.errors.length > 0 && (
                <div>
                  <p className="text-xs font-semibold text-red-500">エラー {commuteParseResult.errors.length}件(反映不可)</p>
                  <ul className="list-disc pl-5 text-xs text-red-500">
                    {commuteParseResult.errors.slice(0, 20).map((e, i) => (
                      <li key={i}>{e}</li>
                    ))}
                  </ul>
                </div>
              )}

              {commuteParseResult.rows.length > 0 && (
                <div className="overflow-x-auto">
                  <table className="min-w-full text-xs">
                    <thead>
                      <tr className="border-b border-slate-200 text-left text-slate-400">
                        <th className="px-2 py-1">職員</th>
                        <th className="px-2 py-1">施設</th>
                        <th className="px-2 py-1">計算方法</th>
                        <th className="px-2 py-1">単価</th>
                      </tr>
                    </thead>
                    <tbody>
                      {commuteParseResult.rows.slice(0, 8).map((r, i) => (
                        <tr key={i} className="border-b border-slate-100">
                          <td className="px-2 py-1">{r.employee_name}</td>
                          <td className="px-2 py-1">{r.office_name}</td>
                          <td className="px-2 py-1">{r.calc_type === "fixed_monthly" ? "月額固定" : "日額×出勤日数"}</td>
                          <td className="px-2 py-1">
                            {r.calc_type === "fixed_monthly" ? `${r.unit_price}円/月` : `${r.unit_price}円/日`}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                  {commuteParseResult.rows.length > 8 && (
                    <p className="mt-1 text-xs text-slate-400">他{commuteParseResult.rows.length - 8}件…</p>
                  )}
                </div>
              )}

              <button
                onClick={handleApplyCommute}
                disabled={isApplyingCommute || commuteParseResult.errors.length > 0 || commuteParseResult.rows.length === 0}
                className="rounded-lg bg-sky-500 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-600 disabled:opacity-60"
              >
                {isApplyingCommute ? "反映中…" : "この内容で反映する"}
              </button>
            </div>
          )}

          {commuteApplyError && <p className="text-sm font-medium text-red-500">{commuteApplyError}</p>}
          {commuteApplySuccess && <p className="text-sm font-medium text-emerald-600">{commuteApplySuccess}</p>}

          <div className="space-y-3 border-t border-slate-100 pt-4">
            <p className="text-sm font-semibold text-slate-700">反映履歴</p>
            {commuteHistory.length === 0 && <p className="text-sm text-slate-400">まだ取込履歴はありません</p>}
            <ul className="divide-y divide-slate-100">
              {commuteHistory.map((h) => (
                <li key={h.id} className="py-2 text-sm text-slate-600">
                  {h.file_name}
                  {" ・ "}
                  {h.imported_count}件
                  {" ・ "}
                  {h.imported_by_name ?? "(不明)"}
                  {" ・ "}
                  {new Date(h.imported_at).toLocaleString("ja-JP")}
                </li>
              ))}
            </ul>
          </div>
        </div>

        <div className="space-y-4 rounded-2xl bg-white p-6 shadow-sm">
          <h3 className="text-base font-bold text-slate-800">施設別手当 一括CSV取込</h3>
          <p className="text-xs text-slate-400">
            1施設×1手当種別×1職員=1行のCSV(ヘッダー: employee_number,office_id,allowance_name,amount,
            effective_start_date)を読み込みます。allowance_nameは役職手当・資格手当・職務手当等、手当マスタの名称と完全一致させてください。
          </p>

          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">CSVファイル</label>
            <input type="file" accept=".csv,text/csv" onChange={handleAllowanceFileChange} className="text-sm" />
          </div>

          {allowanceParseResult && (
            <div className="space-y-2 rounded-xl border border-slate-200 p-4">
              <p className="text-sm font-semibold text-slate-700">プレビュー</p>
              <dl className="grid grid-cols-2 gap-2 text-sm text-slate-600 sm:grid-cols-4">
                <div>
                  <dt className="text-xs text-slate-400">ファイル名</dt>
                  <dd>{allowanceFileName}</dd>
                </div>
                <div>
                  <dt className="text-xs text-slate-400">取込件数</dt>
                  <dd>{allowanceParseResult.rows.length}件</dd>
                </div>
              </dl>

              {allowanceParseResult.errors.length > 0 && (
                <div>
                  <p className="text-xs font-semibold text-red-500">
                    エラー {allowanceParseResult.errors.length}件(反映不可)
                  </p>
                  <ul className="list-disc pl-5 text-xs text-red-500">
                    {allowanceParseResult.errors.slice(0, 20).map((e, i) => (
                      <li key={i}>{e}</li>
                    ))}
                  </ul>
                </div>
              )}

              {allowanceParseResult.rows.length > 0 && (
                <div className="overflow-x-auto">
                  <table className="min-w-full text-xs">
                    <thead>
                      <tr className="border-b border-slate-200 text-left text-slate-400">
                        <th className="px-2 py-1">職員</th>
                        <th className="px-2 py-1">施設</th>
                        <th className="px-2 py-1">手当種別</th>
                        <th className="px-2 py-1">金額</th>
                      </tr>
                    </thead>
                    <tbody>
                      {allowanceParseResult.rows.slice(0, 8).map((r, i) => (
                        <tr key={i} className="border-b border-slate-100">
                          <td className="px-2 py-1">{r.employee_name}</td>
                          <td className="px-2 py-1">{r.office_name}</td>
                          <td className="px-2 py-1">{r.allowance_name}</td>
                          <td className="px-2 py-1">{r.amount}円</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                  {allowanceParseResult.rows.length > 8 && (
                    <p className="mt-1 text-xs text-slate-400">他{allowanceParseResult.rows.length - 8}件…</p>
                  )}
                </div>
              )}

              <button
                onClick={handleApplyAllowances}
                disabled={
                  isApplyingAllowances ||
                  allowanceParseResult.errors.length > 0 ||
                  allowanceParseResult.rows.length === 0
                }
                className="rounded-lg bg-sky-500 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-600 disabled:opacity-60"
              >
                {isApplyingAllowances ? "反映中…" : "この内容で反映する"}
              </button>
            </div>
          )}

          {allowanceApplyError && <p className="text-sm font-medium text-red-500">{allowanceApplyError}</p>}
          {allowanceApplySuccess && <p className="text-sm font-medium text-emerald-600">{allowanceApplySuccess}</p>}

          <div className="space-y-3 border-t border-slate-100 pt-4">
            <p className="text-sm font-semibold text-slate-700">反映履歴</p>
            {allowanceHistory.length === 0 && <p className="text-sm text-slate-400">まだ取込履歴はありません</p>}
            <ul className="divide-y divide-slate-100">
              {allowanceHistory.map((h) => (
                <li key={h.id} className="py-2 text-sm text-slate-600">
                  {h.file_name}
                  {" ・ "}
                  {h.imported_count}件
                  {" ・ "}
                  {h.imported_by_name ?? "(不明)"}
                  {" ・ "}
                  {new Date(h.imported_at).toLocaleString("ja-JP")}
                </li>
              ))}
            </ul>
          </div>
        </div>

        <div className="space-y-4 rounded-2xl bg-white p-6 shadow-sm">
          <h3 className="text-base font-bold text-slate-800">源泉徴収区分・扶養人数 一括CSV取込</h3>
          <p className="text-xs text-slate-400">
            1職員=1行のCSV(ヘッダー: employee_number,tax_column,social_insurance_dependent_count,
            income_tax_dependent_count,submitted_flag,effective_start_year_month)を読み込みます。tax_columnは甲欄または乙欄、
            social_insurance_dependent_countは①社会保険の扶養人数、income_tax_dependent_countは②所得税の扶養人数
            (源泉徴収税額の計算に使用)、submitted_flagはtrue/false、effective_start_year_monthはYYYY-MM-01形式で指定してください。
          </p>

          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">CSVファイル</label>
            <input type="file" accept=".csv,text/csv" onChange={handleTaxFileChange} className="text-sm" />
          </div>

          {taxParseResult && (
            <div className="space-y-2 rounded-xl border border-slate-200 p-4">
              <p className="text-sm font-semibold text-slate-700">プレビュー</p>
              <dl className="grid grid-cols-2 gap-2 text-sm text-slate-600 sm:grid-cols-4">
                <div>
                  <dt className="text-xs text-slate-400">ファイル名</dt>
                  <dd>{taxFileName}</dd>
                </div>
                <div>
                  <dt className="text-xs text-slate-400">取込件数</dt>
                  <dd>{taxParseResult.rows.length}件</dd>
                </div>
              </dl>

              {taxParseResult.errors.length > 0 && (
                <div>
                  <p className="text-xs font-semibold text-red-500">エラー {taxParseResult.errors.length}件(反映不可)</p>
                  <ul className="list-disc pl-5 text-xs text-red-500">
                    {taxParseResult.errors.slice(0, 20).map((e, i) => (
                      <li key={i}>{e}</li>
                    ))}
                  </ul>
                </div>
              )}

              {taxParseResult.rows.length > 0 && (
                <div className="overflow-x-auto">
                  <table className="min-w-full text-xs">
                    <thead>
                      <tr className="border-b border-slate-200 text-left text-slate-400">
                        <th className="px-2 py-1">職員</th>
                        <th className="px-2 py-1">区分</th>
                        <th className="px-2 py-1">①社保扶養</th>
                        <th className="px-2 py-1">②所得税扶養</th>
                        <th className="px-2 py-1">申告書提出</th>
                      </tr>
                    </thead>
                    <tbody>
                      {taxParseResult.rows.slice(0, 8).map((r, i) => (
                        <tr key={i} className="border-b border-slate-100">
                          <td className="px-2 py-1">{r.employee_name}</td>
                          <td className="px-2 py-1">{r.tax_column}</td>
                          <td className="px-2 py-1">{r.social_insurance_dependent_count}</td>
                          <td className="px-2 py-1">{r.income_tax_dependent_count}</td>
                          <td className="px-2 py-1">{r.submitted_flag ? "あり" : "なし"}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                  {taxParseResult.rows.length > 8 && (
                    <p className="mt-1 text-xs text-slate-400">他{taxParseResult.rows.length - 8}件…</p>
                  )}
                </div>
              )}

              <button
                onClick={handleApplyTax}
                disabled={isApplyingTax || taxParseResult.errors.length > 0 || taxParseResult.rows.length === 0}
                className="rounded-lg bg-sky-500 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-600 disabled:opacity-60"
              >
                {isApplyingTax ? "反映中…" : "この内容で反映する"}
              </button>
            </div>
          )}

          {taxApplyError && <p className="text-sm font-medium text-red-500">{taxApplyError}</p>}
          {taxApplySuccess && <p className="text-sm font-medium text-emerald-600">{taxApplySuccess}</p>}

          <div className="space-y-3 border-t border-slate-100 pt-4">
            <p className="text-sm font-semibold text-slate-700">反映履歴</p>
            {taxHistory.length === 0 && <p className="text-sm text-slate-400">まだ取込履歴はありません</p>}
            <ul className="divide-y divide-slate-100">
              {taxHistory.map((h) => (
                <li key={h.id} className="py-2 text-sm text-slate-600">
                  {h.file_name}
                  {" ・ "}
                  {h.imported_count}件
                  {" ・ "}
                  {h.imported_by_name ?? "(不明)"}
                  {" ・ "}
                  {new Date(h.imported_at).toLocaleString("ja-JP")}
                </li>
              ))}
            </ul>
          </div>
        </div>

        <div className="space-y-4 rounded-2xl bg-white p-6 shadow-sm">
          <h3 className="text-base font-bold text-slate-800">標準報酬月額 一括CSV取込</h3>
          <p className="text-xs text-slate-400">
            1職員=1行のCSV(ヘッダー: employee_number,health_insurance_amount,health_insurance_grade,
            pension_amount,pension_grade,effective_year_month,revision_reason)を読み込みます。
            revision_reasonは資格取得時決定・定時決定・随時改定のいずれかで指定してください。
          </p>
          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">CSVファイル</label>
            <input type="file" accept=".csv,text/csv" onChange={handleSmrFileChange} className="text-sm" />
          </div>
          {smrParseResult && (
            <div className="space-y-2 rounded-xl border border-slate-200 p-4">
              <p className="text-sm font-semibold text-slate-700">プレビュー</p>
              <dl className="grid grid-cols-2 gap-2 text-sm text-slate-600 sm:grid-cols-4">
                <div>
                  <dt className="text-xs text-slate-400">ファイル名</dt>
                  <dd>{smrFileName}</dd>
                </div>
                <div>
                  <dt className="text-xs text-slate-400">取込件数</dt>
                  <dd>{smrParseResult.rows.length}件</dd>
                </div>
              </dl>
              {smrParseResult.errors.length > 0 && (
                <div>
                  <p className="text-xs font-semibold text-red-500">エラー {smrParseResult.errors.length}件(反映不可)</p>
                  <ul className="list-disc pl-5 text-xs text-red-500">
                    {smrParseResult.errors.slice(0, 20).map((e, i) => (
                      <li key={i}>{e}</li>
                    ))}
                  </ul>
                </div>
              )}
              {smrParseResult.rows.length > 0 && (
                <div className="overflow-x-auto">
                  <table className="min-w-full text-xs">
                    <thead>
                      <tr className="border-b border-slate-200 text-left text-slate-400">
                        <th className="px-2 py-1">職員</th>
                        <th className="px-2 py-1">健康保険標準報酬</th>
                        <th className="px-2 py-1">厚生年金標準報酬</th>
                      </tr>
                    </thead>
                    <tbody>
                      {smrParseResult.rows.slice(0, 8).map((r, i) => (
                        <tr key={i} className="border-b border-slate-100">
                          <td className="px-2 py-1">{r.employee_name}</td>
                          <td className="px-2 py-1">{r.health_insurance_amount}円</td>
                          <td className="px-2 py-1">{r.pension_amount}円</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                  {smrParseResult.rows.length > 8 && (
                    <p className="mt-1 text-xs text-slate-400">他{smrParseResult.rows.length - 8}件…</p>
                  )}
                </div>
              )}
              <button
                onClick={handleApplySmr}
                disabled={isApplyingSmr || smrParseResult.errors.length > 0 || smrParseResult.rows.length === 0}
                className="rounded-lg bg-sky-500 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-600 disabled:opacity-60"
              >
                {isApplyingSmr ? "反映中…" : "この内容で反映する"}
              </button>
            </div>
          )}
          {smrApplyError && <p className="text-sm font-medium text-red-500">{smrApplyError}</p>}
          {smrApplySuccess && <p className="text-sm font-medium text-emerald-600">{smrApplySuccess}</p>}
        </div>

        <div className="space-y-4 rounded-2xl bg-white p-6 shadow-sm">
          <h3 className="text-base font-bold text-slate-800">社会保険・雇用保険加入状況 一括CSV取込</h3>
          <p className="text-xs text-slate-400">
            1職員×1保険種別=1行のCSV(ヘッダー: employee_number,insurance_type,enrolled,acquisition_date,
            loss_date)を読み込みます。insurance_typeは健康保険・厚生年金・雇用保険のいずれか、
            acquisition_date/loss_dateは空欄可です。
          </p>
          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">CSVファイル</label>
            <input type="file" accept=".csv,text/csv" onChange={handleEnrollFileChange} className="text-sm" />
          </div>
          {enrollParseResult && (
            <div className="space-y-2 rounded-xl border border-slate-200 p-4">
              <p className="text-sm font-semibold text-slate-700">プレビュー</p>
              <dl className="grid grid-cols-2 gap-2 text-sm text-slate-600 sm:grid-cols-4">
                <div>
                  <dt className="text-xs text-slate-400">ファイル名</dt>
                  <dd>{enrollFileName}</dd>
                </div>
                <div>
                  <dt className="text-xs text-slate-400">取込件数</dt>
                  <dd>{enrollParseResult.rows.length}件</dd>
                </div>
              </dl>
              {enrollParseResult.errors.length > 0 && (
                <div>
                  <p className="text-xs font-semibold text-red-500">
                    エラー {enrollParseResult.errors.length}件(反映不可)
                  </p>
                  <ul className="list-disc pl-5 text-xs text-red-500">
                    {enrollParseResult.errors.slice(0, 20).map((e, i) => (
                      <li key={i}>{e}</li>
                    ))}
                  </ul>
                </div>
              )}
              {enrollParseResult.rows.length > 0 && (
                <div className="overflow-x-auto">
                  <table className="min-w-full text-xs">
                    <thead>
                      <tr className="border-b border-slate-200 text-left text-slate-400">
                        <th className="px-2 py-1">職員</th>
                        <th className="px-2 py-1">保険種別</th>
                        <th className="px-2 py-1">加入</th>
                      </tr>
                    </thead>
                    <tbody>
                      {enrollParseResult.rows.slice(0, 8).map((r, i) => (
                        <tr key={i} className="border-b border-slate-100">
                          <td className="px-2 py-1">{r.employee_name}</td>
                          <td className="px-2 py-1">{r.insurance_type}</td>
                          <td className="px-2 py-1">{r.enrolled ? "あり" : "なし"}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                  {enrollParseResult.rows.length > 8 && (
                    <p className="mt-1 text-xs text-slate-400">他{enrollParseResult.rows.length - 8}件…</p>
                  )}
                </div>
              )}
              <button
                onClick={handleApplyEnroll}
                disabled={isApplyingEnroll || enrollParseResult.errors.length > 0 || enrollParseResult.rows.length === 0}
                className="rounded-lg bg-sky-500 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-600 disabled:opacity-60"
              >
                {isApplyingEnroll ? "反映中…" : "この内容で反映する"}
              </button>
            </div>
          )}
          {enrollApplyError && <p className="text-sm font-medium text-red-500">{enrollApplyError}</p>}
          {enrollApplySuccess && <p className="text-sm font-medium text-emerald-600">{enrollApplySuccess}</p>}
        </div>

        <div className="space-y-4 rounded-2xl bg-white p-6 shadow-sm">
          <h3 className="text-base font-bold text-slate-800">住民税(月額) 一括CSV取込</h3>
          <p className="text-xs text-slate-400">
            1職員×1年度×1ヶ月=1行のロング形式CSV(ヘッダー: employee_number,fiscal_year,year_month,amount)を
            読み込みます。fiscal_yearは6月開始の年度(例: 2026年6月〜2027年5月分は2026)、year_monthはYYYY-MM形式です。
          </p>
          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">CSVファイル</label>
            <input type="file" accept=".csv,text/csv" onChange={handleResidentFileChange} className="text-sm" />
          </div>
          {residentParseResult && (
            <div className="space-y-2 rounded-xl border border-slate-200 p-4">
              <p className="text-sm font-semibold text-slate-700">プレビュー</p>
              <dl className="grid grid-cols-2 gap-2 text-sm text-slate-600 sm:grid-cols-4">
                <div>
                  <dt className="text-xs text-slate-400">ファイル名</dt>
                  <dd>{residentFileName}</dd>
                </div>
                <div>
                  <dt className="text-xs text-slate-400">取込件数(行)</dt>
                  <dd>{residentParseResult.rows.length}行</dd>
                </div>
                <div>
                  <dt className="text-xs text-slate-400">年度別レコード数</dt>
                  <dd>{residentParseResult.groupCount}件</dd>
                </div>
              </dl>
              {residentParseResult.errors.length > 0 && (
                <div>
                  <p className="text-xs font-semibold text-red-500">
                    エラー {residentParseResult.errors.length}件(反映不可)
                  </p>
                  <ul className="list-disc pl-5 text-xs text-red-500">
                    {residentParseResult.errors.slice(0, 20).map((e, i) => (
                      <li key={i}>{e}</li>
                    ))}
                  </ul>
                </div>
              )}
              {residentParseResult.rows.length > 0 && (
                <div className="overflow-x-auto">
                  <table className="min-w-full text-xs">
                    <thead>
                      <tr className="border-b border-slate-200 text-left text-slate-400">
                        <th className="px-2 py-1">職員</th>
                        <th className="px-2 py-1">年度</th>
                        <th className="px-2 py-1">年月</th>
                        <th className="px-2 py-1">金額</th>
                      </tr>
                    </thead>
                    <tbody>
                      {residentParseResult.rows.slice(0, 8).map((r, i) => (
                        <tr key={i} className="border-b border-slate-100">
                          <td className="px-2 py-1">{r.employee_name}</td>
                          <td className="px-2 py-1">{r.fiscal_year}</td>
                          <td className="px-2 py-1">{r.year_month}</td>
                          <td className="px-2 py-1">{r.amount}円</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                  {residentParseResult.rows.length > 8 && (
                    <p className="mt-1 text-xs text-slate-400">他{residentParseResult.rows.length - 8}行…</p>
                  )}
                </div>
              )}
              <button
                onClick={handleApplyResident}
                disabled={
                  isApplyingResident || residentParseResult.errors.length > 0 || residentParseResult.rows.length === 0
                }
                className="rounded-lg bg-sky-500 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-600 disabled:opacity-60"
              >
                {isApplyingResident ? "反映中…" : "この内容で反映する"}
              </button>
            </div>
          )}
          {residentApplyError && <p className="text-sm font-medium text-red-500">{residentApplyError}</p>}
          {residentApplySuccess && <p className="text-sm font-medium text-emerald-600">{residentApplySuccess}</p>}

          <div className="space-y-3 border-t border-slate-100 pt-4">
            <p className="text-sm font-semibold text-slate-700">
              標準報酬月額・保険加入・住民税 反映履歴(3種共通)
            </p>
            {socialInsuranceHistory.length === 0 && (
              <p className="text-sm text-slate-400">まだ取込履歴はありません</p>
            )}
            <ul className="divide-y divide-slate-100">
              {socialInsuranceHistory.map((h) => (
                <li key={h.id} className="py-2 text-sm text-slate-600">
                  <span className="font-medium text-slate-800">{h.import_target}</span>
                  {" ・ "}
                  {h.file_name}
                  {" ・ "}
                  {h.imported_count}件
                  {" ・ "}
                  {h.imported_by_name ?? "(不明)"}
                  {" ・ "}
                  {new Date(h.imported_at).toLocaleString("ja-JP")}
                </li>
              ))}
            </ul>
          </div>
        </div>

        <div className="space-y-3 rounded-2xl bg-white p-6 shadow-sm">
          <h3 className="text-base font-bold text-slate-800">源泉徴収税額表 反映履歴</h3>
          {historyError && <p className="text-sm font-medium text-red-500">{historyError}</p>}
          {history.length === 0 && <p className="text-sm text-slate-400">まだ取込履歴はありません</p>}
          <ul className="divide-y divide-slate-100">
            {history.map((h) => (
              <li key={h.id} className="py-2 text-sm text-slate-600">
                <span className="font-medium text-slate-800">{h.target_period}</span>
                {" ・ "}
                {h.file_name}
                {" ・ "}
                {h.imported_count}件
                {" ・ "}
                {h.imported_by_name ?? "(不明)"}
                {" ・ "}
                {new Date(h.imported_at).toLocaleString("ja-JP")}
              </li>
            ))}
          </ul>
        </div>
      </main>
    </div>
  );
}
