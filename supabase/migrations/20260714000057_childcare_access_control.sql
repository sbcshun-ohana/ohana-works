-- 保育業務 Phase0: アクセス制御(施設・クラス単位)とRLS
-- 職員業務(給与・他職員勤怠等)の権限ドメインとは完全に分離した関数群を用いる。
-- is_labor_manager_plus()/manages_office() 等の既存関数は保育業務では参照しない。
-- 逆に、職員業務側のテーブル(payroll_runs等)のRLSは本ファイルの関数を参照しない。

-- 職員ごとの利用可能クラスの明示的な絞り込み。行が無ければ、その職員が
-- 当該施設に所属している限り施設内の全クラスにアクセス可能(既定)。
create table employee_class_access (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id) on delete cascade,
  class_id uuid not null references childcare_classes(id) on delete cascade,
  granted_by uuid references employees(id),
  created_at timestamptz not null default now(),
  unique (employee_id, class_id)
);

-- 保育業務の管理者判定(システム最高管理者、または当該施設にスコープされた
-- 園長・主任・園管理者)。labor_managerは給与専用ロールのため意図的に含めない。
create or replace function manages_childcare(target_office_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from employee_roles er
    join roles r on r.id = er.role_id
    where er.employee_id = my_employee_id()
      and (
        r.code = 'system_admin'
        or (
          r.code in ('director', 'chief', 'office_manager')
          and (er.office_id is null or er.office_id = target_office_id)
        )
      )
  );
$$;

-- 保育業務における施設アクセス可否(当該施設に所属する職員、または当該施設の保育業務管理者)。
create or replace function has_childcare_office_access(target_office_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select manages_childcare(target_office_id) or exists (
    select 1
    from employee_office_assignments eoa
    where eoa.employee_id = my_employee_id()
      and eoa.office_id = target_office_id
      and eoa.start_date <= current_date
      and (eoa.end_date is null or eoa.end_date >= current_date)
  );
$$;

-- クラス単位のアクセス制御。employee_class_accessに当該施設内の明示行が
-- 1件でもあればそれに従い、無ければ施設内の全クラスを許可する。
create or replace function has_childcare_class_access(target_class_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    exists (
      select 1 from childcare_classes cc
      where cc.id = target_class_id
        and has_childcare_office_access(cc.office_id)
    )
    and (
      exists (
        select 1 from employee_class_access eca
        where eca.employee_id = my_employee_id() and eca.class_id = target_class_id
      )
      or not exists (
        select 1
        from employee_class_access eca
        join childcare_classes cc2 on cc2.id = eca.class_id
        where eca.employee_id = my_employee_id()
          and cc2.office_id = (select office_id from childcare_classes where id = target_class_id)
      )
    );
$$;

alter table childcare_classes enable row level security;
create policy childcare_classes_select_scoped on childcare_classes
  for select using (has_childcare_office_access(office_id));
create policy childcare_classes_write_managers on childcare_classes
  for all using (manages_childcare(office_id)) with check (manages_childcare(office_id));

alter table children enable row level security;
create policy children_select_scoped on children
  for select using (has_childcare_office_access(office_id));
create policy children_write_managers on children
  for all using (manages_childcare(office_id)) with check (manages_childcare(office_id));

alter table child_class_enrollments enable row level security;
create policy child_class_enrollments_select_scoped on child_class_enrollments
  for select using (
    exists (
      select 1 from children c
      where c.id = child_class_enrollments.child_id and has_childcare_office_access(c.office_id)
    )
  );
create policy child_class_enrollments_write_managers on child_class_enrollments
  for all using (
    exists (
      select 1 from children c
      where c.id = child_class_enrollments.child_id and manages_childcare(c.office_id)
    )
  ) with check (
    exists (
      select 1 from children c
      where c.id = child_class_enrollments.child_id and manages_childcare(c.office_id)
    )
  );

alter table employee_class_access enable row level security;
create policy employee_class_access_select_self_or_manager on employee_class_access
  for select using (
    employee_id = my_employee_id()
    or exists (
      select 1 from childcare_classes cc
      where cc.id = employee_class_access.class_id and manages_childcare(cc.office_id)
    )
  );
create policy employee_class_access_write_managers on employee_class_access
  for all using (
    exists (
      select 1 from childcare_classes cc
      where cc.id = employee_class_access.class_id and manages_childcare(cc.office_id)
    )
  ) with check (
    exists (
      select 1 from childcare_classes cc
      where cc.id = employee_class_access.class_id and manages_childcare(cc.office_id)
    )
  );

comment on function manages_childcare(uuid) is
  '保育業務専用の管理者権限判定。職員業務(給与等)のmanages_office()/is_labor_manager_plus()とは
   独立した権限ドメインとして扱い、労務管理者(labor_manager)には保育業務の管理権限を渡さない。';
