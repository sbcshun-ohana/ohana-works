/**
 * ステージング環境(project ref: ulzachwkkyrvmxfzktio)専用の匿名化シードデータ投入スクリプト。
 * 実在の個人データは一切含まない。テスト職員・テスト保護者・テスト園児のみ。
 *
 * 接続先は本番と取り違えないよう、このファイル内で staging の URL を固定している
 * (env var 経由で URL を切り替え可能にしない)。service_role key とテスト用共通
 * パスワードのみ環境変数から読む。
 *
 * 実行方法:
 *   STAGING_SERVICE_ROLE_KEY=xxx STAGING_SEED_PASSWORD=xxx npx tsx seed_staging.ts
 *
 * 冪等性: employee_number / (feature_key, office_id) / (office_id, school_year, class_name)
 * などの一意制約を使い、再実行しても重複投入されないようにしている。
 * children / guardians は一意制約がないため、投入前に同名データの有無をチェックする。
 */

import { createClient, type SupabaseClient } from "@supabase/supabase-js";

const STAGING_URL = "https://ulzachwkkyrvmxfzktio.supabase.co";

const rawServiceRoleKey = process.env.STAGING_SERVICE_ROLE_KEY;
const rawSeedPassword = process.env.STAGING_SEED_PASSWORD;

if (!rawServiceRoleKey) {
  throw new Error("環境変数 STAGING_SERVICE_ROLE_KEY が設定されていません");
}
if (!rawSeedPassword || rawSeedPassword.length < 8) {
  throw new Error(
    "環境変数 STAGING_SEED_PASSWORD が未設定、または短すぎます(8文字以上)",
  );
}
const serviceRoleKey: string = rawServiceRoleKey;
const seedPassword: string = rawSeedPassword;

const admin: SupabaseClient = createClient(STAGING_URL, serviceRoleKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});

type RoleCode = "director" | "chief" | "office_manager" | "staff";

interface EmployeeSeed {
  employeeNumber: string;
  name: string;
  email: string;
  roleCode: RoleCode;
  officeName: string;
  isGoalSheetApprover?: boolean;
}

const EMPLOYEES: EmployeeSeed[] = [
  {
    employeeNumber: "STG-EMP-01",
    name: "テスト園長(大和)",
    email: "stg-emp-01+staging@ohana-works.test",
    roleCode: "director",
    officeName: "大和オハナ保育園",
  },
  {
    employeeNumber: "STG-EMP-02",
    name: "テスト主任(大和)",
    email: "stg-emp-02+staging@ohana-works.test",
    roleCode: "chief",
    officeName: "大和オハナ保育園",
    isGoalSheetApprover: true,
  },
  {
    employeeNumber: "STG-EMP-03",
    name: "テスト副主任(大和)",
    email: "stg-emp-03+staging@ohana-works.test",
    roleCode: "staff",
    officeName: "大和オハナ保育園",
  },
  {
    employeeNumber: "STG-EMP-04",
    name: "テスト一般職員(大和)",
    email: "stg-emp-04+staging@ohana-works.test",
    roleCode: "staff",
    officeName: "大和オハナ保育園",
  },
  {
    employeeNumber: "STG-EMP-05",
    name: "テスト管理者(マハロ)",
    email: "stg-emp-05+staging@ohana-works.test",
    roleCode: "office_manager",
    officeName: "BABY MAHALO",
  },
  {
    employeeNumber: "STG-EMP-06",
    name: "テスト一般職員(マハロ)",
    email: "stg-emp-06+staging@ohana-works.test",
    roleCode: "staff",
    officeName: "BABY MAHALO",
  },
  {
    employeeNumber: "STG-EMP-07",
    name: "テスト管理者(ステーション)",
    email: "stg-emp-07+staging@ohana-works.test",
    roleCode: "office_manager",
    officeName: "Mahalo Station",
  },
  {
    employeeNumber: "STG-EMP-08",
    name: "テスト一般職員(ステーション)",
    email: "stg-emp-08+staging@ohana-works.test",
    roleCode: "staff",
    officeName: "Mahalo Station",
  },
  {
    employeeNumber: "STG-EMP-09",
    name: "テスト管理者(ハレレア)",
    email: "stg-emp-09+staging@ohana-works.test",
    roleCode: "office_manager",
    officeName: "Halelea",
  },
  {
    employeeNumber: "STG-EMP-10",
    name: "テスト一般職員(ハレレア)",
    email: "stg-emp-10+staging@ohana-works.test",
    roleCode: "staff",
    officeName: "Halelea",
  },
];

interface ClassSeed {
  className: string;
  ageGroup: string;
}

const CLASS_TEMPLATES: ClassSeed[] = [
  { className: "ひよこ組", ageGroup: "0-1歳" },
  { className: "うさぎ組", ageGroup: "2-3歳" },
  { className: "くま組", ageGroup: "4-5歳" },
  // 支援保育事業(Phase3)の対象候補検証用。本番の実クラス名規則(「組名／N歳児」)に
  // 合わせた単年齢クラスを追加し、3・4・5歳児の提出票集計テストにも使えるようにする。
  { className: "たいよう組／3歳児", ageGroup: "3歳児" },
  { className: "つばさ組／4歳児", ageGroup: "4歳児" },
  { className: "ほし組／5歳児", ageGroup: "5歳児" },
];

const SCHOOL_YEAR = 2026;

interface ChildSeed {
  no: number;
  officeName: string;
  className: string;
  gender: "男" | "女";
  birthDate: string;
}

const CHILDREN: ChildSeed[] = [
  { no: 1, officeName: "大和オハナ保育園", className: "ひよこ組", gender: "男", birthDate: "2025-06-01" },
  { no: 2, officeName: "大和オハナ保育園", className: "うさぎ組", gender: "女", birthDate: "2023-05-10" },
  { no: 3, officeName: "BABY MAHALO", className: "ひよこ組", gender: "女", birthDate: "2025-08-20" },
  { no: 4, officeName: "BABY MAHALO", className: "くま組", gender: "男", birthDate: "2021-09-15" },
  { no: 5, officeName: "Mahalo Station", className: "うさぎ組", gender: "男", birthDate: "2023-11-02" },
  { no: 6, officeName: "Mahalo Station", className: "くま組", gender: "女", birthDate: "2022-01-25" },
  { no: 7, officeName: "Halelea", className: "ひよこ組", gender: "女", birthDate: "2025-04-12" },
  { no: 8, officeName: "Halelea", className: "うさぎ組", gender: "男", birthDate: "2023-03-30" },
  // 支援保育事業(Phase3)の対象候補プール検証用。3・4・5歳児クラスに1名ずつ、
  // まだどの申請候補にも登録されていない状態で投入する。
  { no: 9, officeName: "大和オハナ保育園", className: "たいよう組／3歳児", gender: "男", birthDate: "2022-07-10" },
  { no: 10, officeName: "大和オハナ保育園", className: "つばさ組／4歳児", gender: "女", birthDate: "2021-08-15" },
  { no: 11, officeName: "大和オハナ保育園", className: "ほし組／5歳児", gender: "男", birthDate: "2020-09-20" },
  { no: 12, officeName: "BABY MAHALO", className: "たいよう組／3歳児", gender: "女", birthDate: "2022-05-05" },
  { no: 13, officeName: "BABY MAHALO", className: "つばさ組／4歳児", gender: "男", birthDate: "2021-06-18" },
  { no: 14, officeName: "BABY MAHALO", className: "ほし組／5歳児", gender: "女", birthDate: "2020-10-01" },
  { no: 15, officeName: "Mahalo Station", className: "たいよう組／3歳児", gender: "男", birthDate: "2022-11-22" },
  { no: 16, officeName: "Mahalo Station", className: "つばさ組／4歳児", gender: "女", birthDate: "2021-12-03" },
  { no: 17, officeName: "Mahalo Station", className: "ほし組／5歳児", gender: "男", birthDate: "2020-02-14" },
  { no: 18, officeName: "Halelea", className: "たいよう組／3歳児", gender: "女", birthDate: "2022-03-08" },
  { no: 19, officeName: "Halelea", className: "つばさ組／4歳児", gender: "男", birthDate: "2021-04-27" },
  { no: 20, officeName: "Halelea", className: "ほし組／5歳児", gender: "女", birthDate: "2020-05-30" },
];

// 「まず検索し、無ければ作成する」の順序にすることで、エラーメッセージの
// 文字列一致に依存せずに冪等性を担保する(createUser→失敗時catchで探す方式だと
// GoTrueのエラー文言が変わった場合に再実行が復旧できなくなるため採用しない)。
// 現状の投入対象は最大18アカウント程度のため perPage: 200 で全件を1ページに収める。
async function getOrCreateAuthUser(email: string, password: string): Promise<string> {
  const { data: list, error: listError } = await admin.auth.admin.listUsers({
    perPage: 200,
  });
  if (listError) throw listError;
  const existing = list.users.find((u) => u.email === email);
  if (existing) {
    return existing.id;
  }

  const { data, error } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
  });
  if (error) throw error;
  if (!data.user) {
    throw new Error(`createUser for ${email} returned no user`);
  }
  return data.user.id;
}

async function main() {
  console.log(`接続先: ${STAGING_URL}`);

  const { data: offices, error: officesError } = await admin
    .from("offices")
    .select("id, name");
  if (officesError) throw officesError;
  const officeIdByName = new Map<string, string>(
    (offices ?? []).map((o: { id: string; name: string }) => [o.name, o.id]),
  );
  for (const name of ["大和オハナ保育園", "BABY MAHALO", "Mahalo Station", "Halelea"]) {
    if (!officeIdByName.has(name)) {
      throw new Error(`施設「${name}」がofficesテーブルに見つかりません`);
    }
  }

  const { data: roles, error: rolesError } = await admin.from("roles").select("id, code");
  if (rolesError) throw rolesError;
  const roleIdByCode = new Map<string, string>(
    (roles ?? []).map((r: { id: string; code: string }) => [r.code, r.id]),
  );

  const { data: employmentTypes, error: employmentTypesError } = await admin
    .from("employment_types")
    .select("id")
    .limit(1);
  if (employmentTypesError) throw employmentTypesError;
  if (!employmentTypes || employmentTypes.length === 0) {
    throw new Error("employment_typesが空です");
  }
  const employmentTypeId = employmentTypes[0].id as string;

  console.log("--- 職員(auth + employees + employee_roles + employee_office_assignments) ---");
  const employeeIdByNumber = new Map<string, string>();
  for (const emp of EMPLOYEES) {
    const officeId = officeIdByName.get(emp.officeName)!;
    const roleId = roleIdByCode.get(emp.roleCode);
    if (!roleId) throw new Error(`role code「${emp.roleCode}」が見つかりません`);

    const authUserId = await getOrCreateAuthUser(emp.email, seedPassword);

    const { data: empRow, error: empError } = await admin
      .from("employees")
      .upsert(
        {
          employee_number: emp.employeeNumber,
          auth_user_id: authUserId,
          name: emp.name,
          hire_date: "2026-04-01",
          home_office_id: officeId,
          employment_type_id: employmentTypeId,
          salary_type: "月給",
        },
        { onConflict: "employee_number" },
      )
      .select("id")
      .single();
    if (empError) throw empError;
    const employeeId = empRow.id as string;
    employeeIdByNumber.set(emp.employeeNumber, employeeId);

    const { error: roleError } = await admin
      .from("employee_roles")
      .upsert(
        { employee_id: employeeId, role_id: roleId, office_id: officeId },
        { onConflict: "employee_id,role_id,office_id" },
      );
    if (roleError) throw roleError;

    const { data: existingAssignment, error: assignmentSelectError } = await admin
      .from("employee_office_assignments")
      .select("id")
      .eq("employee_id", employeeId)
      .eq("office_id", officeId)
      .maybeSingle();
    if (assignmentSelectError) throw assignmentSelectError;
    if (!existingAssignment) {
      const { error: assignmentError } = await admin.from("employee_office_assignments").insert({
        employee_id: employeeId,
        office_id: officeId,
        assignment_type: "primary",
        start_date: "2026-04-01",
      });
      if (assignmentError) throw assignmentError;
    }

    if (emp.isGoalSheetApprover) {
      const { error: approverError } = await admin
        .from("employee_goal_sheet_office_approvers")
        .upsert(
          { office_id: officeId, approver_employee_id: employeeId },
          { onConflict: "office_id" },
        );
      if (approverError) throw approverError;
    }

    console.log(`  ${emp.employeeNumber} ${emp.name} (${emp.officeName}/${emp.roleCode}) OK`);
  }

  console.log("--- クラス(childcare_classes) ---");
  const classIdByOfficeAndName = new Map<string, string>();
  for (const officeName of ["大和オハナ保育園", "BABY MAHALO", "Mahalo Station", "Halelea"]) {
    const officeId = officeIdByName.get(officeName)!;
    for (const tmpl of CLASS_TEMPLATES) {
      const { data: classRow, error: classError } = await admin
        .from("childcare_classes")
        .upsert(
          {
            office_id: officeId,
            school_year: SCHOOL_YEAR,
            class_name: tmpl.className,
            age_group: tmpl.ageGroup,
          },
          { onConflict: "office_id,school_year,class_name" },
        )
        .select("id")
        .single();
      if (classError) throw classError;
      classIdByOfficeAndName.set(`${officeName}::${tmpl.className}`, classRow.id as string);
    }
    console.log(`  ${officeName}: ${CLASS_TEMPLATES.length}クラス OK`);
  }

  console.log("--- 園児・保護者(children + guardians + guardian_child_links + child_class_enrollments) ---");
  for (const child of CHILDREN) {
    const officeId = officeIdByName.get(child.officeName)!;
    const classId = classIdByOfficeAndName.get(`${child.officeName}::${child.className}`)!;
    const displayName = `テスト園児${String(child.no).padStart(2, "0")}`;

    const { data: existingChild, error: childSelectError } = await admin
      .from("children")
      .select("id")
      .eq("office_id", officeId)
      .eq("full_name", displayName)
      .maybeSingle();
    if (childSelectError) throw childSelectError;

    let childId: string;
    if (existingChild) {
      childId = existingChild.id as string;
    } else {
      const { data: childRow, error: childError } = await admin
        .from("children")
        .insert({
          office_id: officeId,
          full_name: displayName,
          display_name: displayName,
          gender: child.gender,
          birth_date: child.birthDate,
          enrollment_date: "2026-04-01",
          enrollment_status: "在籍中",
        })
        .select("id")
        .single();
      if (childError) throw childError;
      childId = childRow.id as string;
    }

    const { data: existingEnrollment, error: enrollmentSelectError } = await admin
      .from("child_class_enrollments")
      .select("id")
      .eq("child_id", childId)
      .eq("class_id", classId)
      .maybeSingle();
    if (enrollmentSelectError) throw enrollmentSelectError;
    if (!existingEnrollment) {
      const { error: enrollmentError } = await admin.from("child_class_enrollments").insert({
        child_id: childId,
        class_id: classId,
        effective_start_date: "2026-04-01",
      });
      if (enrollmentError) throw enrollmentError;
    }

    const guardianEmail = `stg-guardian-${String(child.no).padStart(2, "0")}+staging@ohana-works.test`;
    const guardianAuthUserId = await getOrCreateAuthUser(guardianEmail, seedPassword);
    const guardianName = `テスト保護者${String(child.no).padStart(2, "0")}`;

    const { data: guardianRow, error: guardianError } = await admin
      .from("guardians")
      .upsert(
        { auth_user_id: guardianAuthUserId, name: guardianName, email: guardianEmail },
        { onConflict: "auth_user_id" },
      )
      .select("id")
      .single();
    if (guardianError) throw guardianError;
    const guardianId = guardianRow.id as string;

    const { data: existingLink, error: linkSelectError } = await admin
      .from("guardian_child_links")
      .select("id")
      .eq("guardian_id", guardianId)
      .eq("child_id", childId)
      .maybeSingle();
    if (linkSelectError) throw linkSelectError;
    if (!existingLink) {
      const { error: linkError } = await admin.from("guardian_child_links").insert({
        guardian_id: guardianId,
        child_id: childId,
        role: "primary",
      });
      if (linkError) throw linkError;
    }

    console.log(`  ${displayName} (${child.officeName}/${child.className}) + ${guardianName} OK`);
  }

  console.log("--- 機能フラグ(feature_flag_office_overrides: 大和オハナ保育園のみ全ON) ---");
  const { data: flags, error: flagsError } = await admin.from("feature_flags").select("feature_key");
  if (flagsError) throw flagsError;
  const yamatoOfficeId = officeIdByName.get("大和オハナ保育園")!;
  for (const flag of flags ?? []) {
    const { error: overrideError } = await admin
      .from("feature_flag_office_overrides")
      .upsert(
        {
          feature_key: flag.feature_key,
          office_id: yamatoOfficeId,
          enabled: true,
          note: "ステージング検証用(scripts/seed_staging.tsにより投入)",
        },
        { onConflict: "feature_key,office_id" },
      );
    if (overrideError) throw overrideError;
  }
  console.log(`  ${(flags ?? []).length}フラグ OK`);

  // 検証用の意図的な中間状態: BABY MAHALO は childcare_operations のみON、
  // child_internal_notes_enabled はOFFのまま。これにより「保育業務は使えるが
  // 園内記録フラグはOFF」の施設ができ、園内記録ボタンが非表示になることを
  // STG-EMP-05(BABY MAHALOの管理者)で確認できる(大和のみ全ONだと再現不能なため)。
  // child_internal_notes_enabled の行はここで作らない(=OFFを維持)。
  console.log("--- 検証用フラグ(BABY MAHALO: childcare_operationsのみON) ---");
  const babyMahaloOfficeId = officeIdByName.get("BABY MAHALO")!;
  {
    const { error: babyMahaloFlagError } = await admin
      .from("feature_flag_office_overrides")
      .upsert(
        {
          feature_key: "childcare_operations",
          office_id: babyMahaloOfficeId,
          enabled: true,
          note: "ステージング検証用: 園内記録フラグOFFでボタン非表示を確認するため、childcare_operationsのみON(child_internal_notes_enabledはOFFのまま)",
        },
        { onConflict: "feature_key,office_id" },
      );
    if (babyMahaloFlagError) throw babyMahaloFlagError;
  }
  console.log("  BABY MAHALO childcare_operations ON(園内記録はOFF維持) OK");

  // 統括園長・統括管理者(マイグレーション20260714000147)の拒否側E2E用テストアカウント。
  //  - STG-EMP-01 = 統括園長(executive_director・全施設)。大原利奈の切替を模したテスト。
  //  - STG-EMP-05 = 統括管理者(area_manager マーカー)＋ Mahalo Station への付与(管理者相当)。
  //    自施設 BABY MAHALO は既存の office_manager、付与施設 Mahalo Station は付与テーブル、
  //    付与外 Halelea は拒否、を検証できる。
  //  - STG-EMP-04 = 拒否側E2E用の system_admin(grant/revoke は system_admin のみ可の検証用。
  //    ステージングには他に system_admin が居ないため、本番とは無関係のテスト便宜として付与)。
  // employee_roles の office_id=null 行は UNIQUE の NULL 非同一性のため upsert が効かないので存在確認で冪等化。
  console.log("--- テスト用: 統括園長/統括管理者/system_admin(権限E2E用) ---");
  async function ensureAllOfficeRole(employeeNumber: string, roleCode: string) {
    const employeeId = employeeIdByNumber.get(employeeNumber)!;
    const roleId = roleIdByCode.get(roleCode);
    if (!roleId) throw new Error(`role code「${roleCode}」が見つかりません(マイグレーション未適用?)`);
    const { data: existing, error: selErr } = await admin
      .from("employee_roles")
      .select("id")
      .eq("employee_id", employeeId)
      .eq("role_id", roleId)
      .is("office_id", null)
      .maybeSingle();
    if (selErr) throw selErr;
    if (!existing) {
      const { error } = await admin
        .from("employee_roles")
        .insert({ employee_id: employeeId, role_id: roleId, office_id: null });
      if (error) throw error;
    }
  }
  await ensureAllOfficeRole("STG-EMP-01", "executive_director");
  await ensureAllOfficeRole("STG-EMP-05", "area_manager");
  await ensureAllOfficeRole("STG-EMP-04", "system_admin");

  {
    const granteeId = employeeIdByNumber.get("STG-EMP-05")!;
    const mahaloStationId = officeIdByName.get("Mahalo Station")!;
    const grantedById = employeeIdByNumber.get("STG-EMP-04")!;
    const { data: existingGrant, error: grantSelErr } = await admin
      .from("multi_office_authority_grants")
      .select("id")
      .eq("grantee_employee_id", granteeId)
      .eq("office_id", mahaloStationId)
      .is("revoked_at", null)
      .maybeSingle();
    if (grantSelErr) throw grantSelErr;
    if (!existingGrant) {
      const { error } = await admin
        .from("multi_office_authority_grants")
        .insert({ grantee_employee_id: granteeId, office_id: mahaloStationId, granted_by: grantedById });
      if (error) throw error;
    }
  }
  console.log("  統括園長=STG-EMP-01 / 統括管理者=STG-EMP-05(Mahalo Station付与) / system_admin=STG-EMP-04 OK");

  // 要件3(PIN簡易ログイン)の実機確認用: BABY MAHALO の登録端末(device_code でペアリング)。
  // PIN自体は本人がアプリでメール+パスワードでログイン後 set_my_pin で設定する(seedでは設定しない)。
  console.log("--- テスト用: PINログイン登録端末(BABY MAHALO) ---");
  {
    const babyId = officeIdByName.get("BABY MAHALO")!;
    const { data: existingDevice, error: devSelErr } = await admin
      .from("devices").select("id").eq("device_code", "TEST-PIN-IPAD-BABY").maybeSingle();
    if (devSelErr) throw devSelErr;
    if (!existingDevice) {
      const { error } = await admin.from("devices").insert({
        device_code: "TEST-PIN-IPAD-BABY", office_id: babyId, status: "enabled",
        note: "要件3 PIN簡易ログインの実機確認用",
      });
      if (error) throw error;
    }
  }
  console.log("  PINログイン登録端末 TEST-PIN-IPAD-BABY OK");

  console.log("完了しました。");
}

main().catch((err) => {
  console.error("シード投入中にエラーが発生しました:", err);
  process.exit(1);
});
