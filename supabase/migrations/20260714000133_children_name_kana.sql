-- 園児マスタの新規登録UIでふりがなを入力できるようにする(他テーブルのname_kana命名規則に合わせる)。
alter table children add column name_kana text;
