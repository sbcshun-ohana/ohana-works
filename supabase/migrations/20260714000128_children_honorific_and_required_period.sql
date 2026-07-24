-- 1) 呼称サフィックスの解決を一箇所(生成列)に集約する。
--    honorific_suffixが個別設定されていればそれを、無ければ性別既定(女=ちゃん/男=くん)を使う。
--    以後、子ども名を返す全RPC・保護者アプリの直接SELECTはこの列を参照すれば
--    画面ごとに敬称計算ロジックを重複させる必要がなくなる。
alter table children
  add column honorific_suffix_resolved text
  generated always as (
    coalesce(nullif(honorific_suffix, ''), case gender when '女' then 'ちゃん' when '男' then 'くん' else '' end)
  ) stored;

-- 2) 家庭連絡帳の必須設定を「ON/OFFトグル」から「適用期間」に変更する。
--    発達に関する課題等で個別に必須化する園児向け。開始日必須・終了日任意(null=無期限)。
--    0〜2歳児クラスの「クラス全員必須」は引き続きchildcare_classes.family_daily_report_requiredで判定する。
alter table children drop column family_daily_report_required_override;
alter table children add column family_daily_report_required_from date;
alter table children add column family_daily_report_required_until date;
alter table children add constraint children_required_period_check
  check (family_daily_report_required_until is null or family_daily_report_required_from is not null);
