-- 保育業務 Phase1: AI連絡帳生成の外部送信データをallowlist方式で取得するRPC
--
-- 送信してよいもの: 呼び方(+呼称サフィックス)、クラス名、年齢区分、当日の入力内容
-- (クラス活動+園児個別メモ+個別お知らせチェックのラベル)、直近7日分の承認済み連絡帳本文、
-- 園単位のAIプロフィール(文体設定)。
-- 送信してはいけないもの(本関数では最初から選択しない): 正式氏名、住所、保護者情報、
-- 既往歴・アレルギー・医療情報、児童票の詳細。
--
-- Edge Function(generate-contact-note)は本RPCを呼び出し元職員のJWTで呼び出し、
-- 返却されたjsonbのみをAI APIへの入力プロンプト構築に用いる。

create or replace function fetch_ai_allowed_context(p_child_id uuid, p_business_date date)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_office_id uuid;
  v_display_name text;
  v_gender text;
  v_honorific_suffix text;
  v_effective_honorific text;
  v_class_id uuid;
  v_class_name text;
  v_age_group text;
  v_today_activity jsonb;
  v_today_contact jsonb;
  v_notice_labels text[];
  v_recent_contacts jsonb;
  v_office_tone_settings jsonb;
begin
  select office_id, display_name, gender, honorific_suffix
    into v_office_id, v_display_name, v_gender, v_honorific_suffix
  from children where id = p_child_id;

  if v_office_id is null then
    raise exception 'child not found';
  end if;
  if not has_childcare_office_access(v_office_id) then
    raise exception 'not authorized';
  end if;

  v_effective_honorific := coalesce(
    nullif(v_honorific_suffix, ''),
    case v_gender when '女' then 'ちゃん' when '男' then 'くん' else '' end
  );

  select cce.class_id, cc.class_name, cc.age_group
    into v_class_id, v_class_name, v_age_group
  from child_class_enrollments cce
  join childcare_classes cc on cc.id = cce.class_id
  where cce.child_id = p_child_id
    and cce.effective_start_date <= p_business_date
    and (cce.effective_end_date is null or cce.effective_end_date >= p_business_date)
  order by cce.effective_start_date desc
  limit 1;

  select jsonb_build_object(
    'today_theme', cda.today_theme,
    'activity_content', cda.activity_content,
    'class_overview', cda.class_overview,
    'class_announcement', cda.class_announcement,
    'other_notes', cda.other_notes
  ) into v_today_activity
  from class_daily_activities cda
  where cda.class_id = v_class_id and cda.business_date = p_business_date;

  select jsonb_build_object(
    'guardian_message', cdc.guardian_message,
    'child_today_notes', cdc.child_today_notes,
    'free_notes', cdc.free_notes
  ) into v_today_contact
  from child_daily_contacts cdc
  where cdc.child_id = p_child_id and cdc.business_date = p_business_date;

  select coalesce(array_agg(inm.label order by inm.sort_order), array[]::text[])
    into v_notice_labels
  from child_daily_contacts cdc
  join child_daily_contact_notice_checks cdcnc on cdcnc.contact_id = cdc.id
  join individual_notice_masters inm on inm.id = cdcnc.notice_master_id
  where cdc.child_id = p_child_id and cdc.business_date = p_business_date;

  select coalesce(jsonb_agg(jsonb_build_object('business_date', x.business_date, 'text', x.current_text) order by x.business_date desc), '[]'::jsonb)
    into v_recent_contacts
  from (
    select business_date, current_text
    from child_daily_contacts
    where child_id = p_child_id
      and status = 'approved'
      and business_date >= p_business_date - 7
      and business_date < p_business_date
      and current_text is not null
  ) x;

  select tone_settings into v_office_tone_settings
  from ai_style_profiles
  where scope_type = 'office' and scope_id = v_office_id;

  return jsonb_build_object(
    'display_name', v_display_name,
    'honorific_suffix', v_effective_honorific,
    'class_name', v_class_name,
    'age_group', v_age_group,
    'today_input', jsonb_build_object(
      'class_activity', v_today_activity,
      'child_contact', v_today_contact,
      'individual_notices', to_jsonb(v_notice_labels)
    ),
    'recent_contacts', v_recent_contacts,
    'office_tone_settings', coalesce(v_office_tone_settings, '{}'::jsonb)
  );
end;
$$;
