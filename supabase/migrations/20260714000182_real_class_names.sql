-- クラス名称の実名化。旧仮名で照合(実名化済みの環境では該当なし=no-op)。age_group は単年表記に統一
-- (162の年齢区分順ソートが 0歳<1歳<…<5歳 で正しく効く)。在籍は改名で維持。0-2歳施設の3歳以上
-- クラスは廃止(is_active=false)、在籍試験児は2歳クラスへ移し替えてから廃止(削除・再作成はしない)。

-- 大和(6→6)
update childcare_classes set class_name='はな組', age_group='0歳' where office_id='c0a7010a-fd37-4cad-971b-6b3f2e80f842' and class_name='ひよこ組';
update childcare_classes set class_name='そら組', age_group='1歳' where office_id='c0a7010a-fd37-4cad-971b-6b3f2e80f842' and class_name='うさぎ組';
update childcare_classes set class_name='かぜ組', age_group='2歳' where office_id='c0a7010a-fd37-4cad-971b-6b3f2e80f842' and class_name='たいよう組／3歳児';
update childcare_classes set class_name='つき組', age_group='3歳' where office_id='c0a7010a-fd37-4cad-971b-6b3f2e80f842' and class_name='くま組';
update childcare_classes set class_name='ほし組', age_group='4歳' where office_id='c0a7010a-fd37-4cad-971b-6b3f2e80f842' and class_name='つばさ組／4歳児';
update childcare_classes set class_name='にじ組', age_group='5歳' where office_id='c0a7010a-fd37-4cad-971b-6b3f2e80f842' and class_name='ほし組／5歳児';

-- BABY MAHALO / Mahalo Station(0-2歳・リコ/ラウ/プア)
update childcare_classes set class_name='リコ', age_group='0歳' where office_id in ('a7865932-08f1-4df4-bfe8-704d8cd9794b','c134824c-a4db-4744-95b8-c252e284ad88') and class_name='ひよこ組';
update childcare_classes set class_name='ラウ', age_group='1歳' where office_id in ('a7865932-08f1-4df4-bfe8-704d8cd9794b','c134824c-a4db-4744-95b8-c252e284ad88') and class_name='うさぎ組';
update childcare_classes set class_name='プア', age_group='2歳' where office_id in ('a7865932-08f1-4df4-bfe8-704d8cd9794b','c134824c-a4db-4744-95b8-c252e284ad88') and class_name='たいよう組／3歳児';

-- Halelea(0-2歳・ナル/カイ/モアナ)
update childcare_classes set class_name='ナル', age_group='0歳' where office_id='14ef175d-20e5-4ebc-a9e7-d3af3d026f10' and class_name='ひよこ組';
update childcare_classes set class_name='カイ', age_group='1歳' where office_id='14ef175d-20e5-4ebc-a9e7-d3af3d026f10' and class_name='うさぎ組';
update childcare_classes set class_name='モアナ', age_group='2歳' where office_id='14ef175d-20e5-4ebc-a9e7-d3af3d026f10' and class_name='たいよう組／3歳児';

-- 3歳以上クラス(0-2歳施設のみ)の在籍児を、同施設の2歳クラスへ移し替え(旧在籍を昨日で終了→今日から2歳へ)
with moved as (
  update child_class_enrollments
  set effective_end_date = current_date - 1
  where effective_end_date is null
    and class_id in (
      select cc.id from childcare_classes cc
      where cc.office_id in ('a7865932-08f1-4df4-bfe8-704d8cd9794b','c134824c-a4db-4744-95b8-c252e284ad88','14ef175d-20e5-4ebc-a9e7-d3af3d026f10')
        and cc.class_name in ('くま組','つばさ組／4歳児','ほし組／5歳児')
    )
  returning child_id, class_id
)
insert into child_class_enrollments (child_id, class_id, effective_start_date)
select distinct m.child_id, tgt.id, current_date
from moved m
join childcare_classes src on src.id = m.class_id
join childcare_classes tgt on tgt.office_id = src.office_id and tgt.age_group = '2歳' and tgt.is_active
where not exists (
  select 1 from child_class_enrollments x
  where x.child_id = m.child_id and x.effective_end_date is null and x.class_id = tgt.id
);

-- 3歳以上クラスを廃止(0-2歳施設のみ)
update childcare_classes set is_active = false
where office_id in ('a7865932-08f1-4df4-bfe8-704d8cd9794b','c134824c-a4db-4744-95b8-c252e284ad88','14ef175d-20e5-4ebc-a9e7-d3af3d026f10')
  and class_name in ('くま組','つばさ組／4歳児','ほし組／5歳児');
