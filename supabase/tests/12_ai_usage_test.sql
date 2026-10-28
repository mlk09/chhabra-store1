\set ON_ERROR_STOP 1
begin;
insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000f1', 'ai@test.in');

select tests.login('ai@test.in');
select tests.fails($$select public.ai_take_quota(auth.uid(), 100)$$, 'app users cannot spend AI quota directly');
select tests.fails($$select * from public.ai_usage$$, 'app users cannot read AI usage');

select tests.as_admin();
select set_config('role', 'service_role', true);
select tests.eq(public.ai_take_quota('00000000-0000-0000-0000-0000000000f1', 2), true, 'first call allowed');
select tests.eq(public.ai_take_quota('00000000-0000-0000-0000-0000000000f1', 2), true, 'second call allowed');
select tests.eq(public.ai_take_quota('00000000-0000-0000-0000-0000000000f1', 2), false, 'third call over the daily limit');
select tests.as_admin();
select tests.eq((select count from public.ai_usage where user_id = '00000000-0000-0000-0000-0000000000f1'), 2, 'refused call is not counted');
rollback;
\echo 'ai usage tests passed'
