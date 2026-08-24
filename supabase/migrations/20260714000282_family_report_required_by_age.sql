-- 282: 家庭連絡帳の提出必須(クラス基準)を年齢に合わせて修正。
-- 俊指示(2026-08-24): 0〜2歳児クラス=全員必須(クラス基準)、3歳以上クラス=任意(個別に期間設定で必須化)。
-- childcare_classes.family_daily_report_required の default は true(100)で、3歳以上クラスが誤って
-- 必須になっていた/0歳クラスが任意になっていた。age_group('0歳'〜'5歳')から正しく設定し直す。
-- 表示(admin /children の「クラス基準で必須」判定)・登園ゲート is_family_daily_report_required の両方に反映される。

update childcare_classes
set family_daily_report_required = (substring(age_group from '(\d)歳')::int <= 2)
where age_group ~ '(\d)歳';

-- 3歳以上クラスは「クラス基準で必須」を解除するため、そのクラスの児に付いていた
-- 「必須化解除の個別override(=override が false のケースは存在しない設計)」には触れない。
-- 個別の必須化(期間設定)は children.family_daily_report_required_from/until 側で従来どおり有効。
