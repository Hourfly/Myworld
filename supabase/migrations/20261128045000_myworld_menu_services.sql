-- MyWorld menu services: support, withdrawals, admin applications, feature flags,
-- affiliate attribution, virtual trading, and private gift-card submissions.
-- Edge Functions authenticate the user and call these service-role-only RPCs.

create table if not exists private.support_tickets (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 subject text not null check(char_length(subject) between 4 and 140),
 category text not null check(category in ('account','payments','membership','gift_card','shipment','technical','other')),
 message text not null check(char_length(message) between 10 and 4000),
 status text not null default 'open' check(status in ('open','in_progress','resolved','closed')),
 admin_reply text, replied_by uuid references auth.users(id), replied_at timestamptz,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists support_tickets_user_created_idx on private.support_tickets(user_id,created_at desc);
create index if not exists support_tickets_status_created_idx on private.support_tickets(status,created_at desc);
alter table private.support_tickets enable row level security;
revoke all on private.support_tickets from anon,authenticated;
grant all on private.support_tickets to service_role;

create table if not exists private.withdrawal_requests (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 amount_kobo bigint not null check(amount_kobo>=10000),
 payout_method text not null check(payout_method in ('bank_transfer','other')), destination jsonb not null,
 status text not null default 'pending' check(status in ('pending','approved','rejected','paid')),
 user_note text, admin_note text, reviewed_by uuid references auth.users(id), reviewed_at timestamptz,
 paid_at timestamptz, payout_reference text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists withdrawal_requests_user_created_idx on private.withdrawal_requests(user_id,created_at desc);
create index if not exists withdrawal_requests_status_created_idx on private.withdrawal_requests(status,created_at desc);
alter table private.withdrawal_requests enable row level security;
revoke all on private.withdrawal_requests from anon,authenticated;
grant all on private.withdrawal_requests to service_role;

create table if not exists private.admin_applications (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 full_name text not null check(char_length(full_name) between 2 and 120),
 contact text not null check(char_length(contact) between 5 and 180),
 requested_role text not null check(char_length(requested_role) between 2 and 80),
 experience text not null check(char_length(experience) between 10 and 2000),
 reason text not null check(char_length(reason) between 10 and 2000),
 status text not null default 'pending' check(status in ('pending','approved','rejected')),
 admin_note text, reviewed_by uuid references auth.users(id), reviewed_at timestamptz,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists admin_applications_status_created_idx on private.admin_applications(status,created_at desc);
create unique index if not exists admin_applications_one_pending_per_user_idx on private.admin_applications(user_id) where status='pending';
alter table private.admin_applications enable row level security;
revoke all on private.admin_applications from anon,authenticated;
grant all on private.admin_applications to service_role;

create table if not exists private.myworld_feature_flags (
 feature_key text primary key check(feature_key ~ '^[a-z0-9-]{2,60}$'),
 enabled boolean not null default true, updated_by uuid references auth.users(id), updated_at timestamptz not null default now()
);
alter table private.myworld_feature_flags enable row level security;
revoke all on private.myworld_feature_flags from anon,authenticated;
grant all on private.myworld_feature_flags to service_role;
insert into private.myworld_feature_flags(feature_key,enabled) values
 ('wallet',true),('myworld-card',true),('redeem',true),('withdraw',true),('subscriptions',true),('transactions',true),('trading',true),('affiliate',true),('api',true),('community',true),('admin-request',true),('support',true),('security',true)
on conflict(feature_key) do nothing;

create table if not exists private.affiliate_accounts (
 user_id uuid primary key references auth.users(id) on delete cascade,
 referral_code text not null unique check(referral_code ~ '^[A-Z0-9]{8,16}$'),
 status text not null default 'active' check(status in ('active','paused')), created_at timestamptz not null default now()
);
create table if not exists private.affiliate_referrals (
 id uuid primary key default gen_random_uuid(), affiliate_user_id uuid not null references private.affiliate_accounts(user_id) on delete cascade,
 referred_user_id uuid not null unique references auth.users(id) on delete cascade, referral_code text not null,
 status text not null default 'registered' check(status in ('registered','qualified','void')), created_at timestamptz not null default now()
);
create index if not exists affiliate_referrals_owner_created_idx on private.affiliate_referrals(affiliate_user_id,created_at desc);
alter table private.affiliate_accounts enable row level security;
alter table private.affiliate_referrals enable row level security;
revoke all on private.affiliate_accounts,private.affiliate_referrals from anon,authenticated;
grant all on private.affiliate_accounts,private.affiliate_referrals to service_role;

create table if not exists private.demo_trading_accounts (
 user_id uuid primary key references auth.users(id) on delete cascade,
 balance_kobo bigint not null default 100000000 check(balance_kobo>=0),
 starting_balance_kobo bigint not null default 100000000, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists private.demo_trading_orders (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 symbol text not null check(symbol in ('MW-BTC','MW-ETH','MW-GOLD','MW-TECH')),
 side text not null check(side in ('buy','sell')), quantity numeric(24,8) not null check(quantity>0),
 unit_price_kobo bigint not null check(unit_price_kobo>0), total_kobo bigint not null check(total_kobo>0),
 created_at timestamptz not null default now()
);
create index if not exists demo_trading_orders_user_created_idx on private.demo_trading_orders(user_id,created_at desc);
alter table private.demo_trading_accounts enable row level security;
alter table private.demo_trading_orders enable row level security;
revoke all on private.demo_trading_accounts,private.demo_trading_orders from anon,authenticated;
grant all on private.demo_trading_accounts,private.demo_trading_orders to service_role;

create table if not exists private.gift_card_submissions (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 brand text not null check(char_length(brand) between 2 and 60), denomination numeric(14,2) not null check(denomination>0),
 currency text not null check(currency in ('USD','GBP','EUR','CAD','AUD','NGN')), image_path text not null, user_note text,
 status text not null default 'submitted' check(status in ('submitted','reviewing','rejected','credited')),
 quote_kobo bigint check(quote_kobo is null or quote_kobo>0), admin_note text, reviewed_by uuid references auth.users(id),
 reviewed_at timestamptz, credit_reference text unique, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists gift_card_submissions_user_created_idx on private.gift_card_submissions(user_id,created_at desc);
create index if not exists gift_card_submissions_status_created_idx on private.gift_card_submissions(status,created_at desc);
alter table private.gift_card_submissions enable row level security;
revoke all on private.gift_card_submissions from anon,authenticated;
grant all on private.gift_card_submissions to service_role;

alter table public.payment_transactions drop constraint if exists payment_transactions_provider_check;
alter table public.payment_transactions add constraint payment_transactions_provider_check check(provider=any(array['paystack','myworld_card','withdrawal','admin']::text[]));
alter table public.user_notifications drop constraint if exists user_notifications_type_check;
alter table public.user_notifications add constraint user_notifications_type_check check(type=any(array['wallet_topup','shipment_started','shipment_ended','admin_message']::text[]));

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('myworld-gift-card-submissions','myworld-gift-card-submissions',false,10485760,array['image/jpeg','image/png','image/webp','image/heic'])
on conflict(id) do update set public=false,file_size_limit=10485760,allowed_mime_types=array['image/jpeg','image/png','image/webp','image/heic'];
do $$ begin
 if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='Users upload own gift card images') then
  create policy "Users upload own gift card images" on storage.objects for insert to authenticated with check(bucket_id='myworld-gift-card-submissions' and (storage.foldername(name))[1]=(select auth.uid())::text);
 end if;
 if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='Users read own gift card images') then
  create policy "Users read own gift card images" on storage.objects for select to authenticated using(bucket_id='myworld-gift-card-submissions' and (storage.foldername(name))[1]=(select auth.uid())::text);
 end if;
end $$;

create or replace function private.capture_myworld_referral()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,private,auth as $$
declare v_code text;v_owner uuid;
begin
 v_code=upper(regexp_replace(coalesce(new.raw_user_meta_data->>'myworld_referral_code',''),'[^A-Z0-9]','','g'));
 if length(v_code)<8 or length(v_code)>16 then return new;end if;
 select user_id into v_owner from private.affiliate_accounts where referral_code=v_code and status='active';
 if v_owner is not null and v_owner<>new.id then
  insert into private.affiliate_referrals(affiliate_user_id,referred_user_id,referral_code) values(v_owner,new.id,v_code) on conflict(referred_user_id) do nothing;
 end if;
 return new;
end;
$$;
do $$ begin
 if not exists(select 1 from pg_trigger where tgname='myworld_capture_referral_after_signup' and tgrelid='auth.users'::regclass) then
  create trigger myworld_capture_referral_after_signup after insert on auth.users for each row execute function private.capture_myworld_referral();
 end if;
end $$;

CREATE OR REPLACE FUNCTION private.capture_myworld_referral()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'auth'
AS $function$
declare v_code text; v_owner uuid;
begin
 v_code=upper(regexp_replace(coalesce(new.raw_user_meta_data->>'myworld_referral_code',''),'[^A-Z0-9]','','g'));
 if length(v_code)<8 or length(v_code)>16 then return new; end if;
 select user_id into v_owner from private.affiliate_accounts where referral_code=v_code and status='active';
 if v_owner is not null and v_owner<>new.id then
  insert into private.affiliate_referrals(affiliate_user_id,referred_user_id,referral_code)
  values(v_owner,new.id,v_code) on conflict(referred_user_id) do nothing;
 end if;
 return new;
end;
$function$


CREATE OR REPLACE FUNCTION public.myworld_affiliate_action(p_action text, p_user_id uuid, p_referral_code text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare v_row jsonb;
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service role required'; end if;
 if p_action='create' then
  if p_referral_code !~ '^[A-Z0-9]{8,16}$' then raise exception 'Invalid referral code'; end if;
  insert into private.affiliate_accounts(user_id,referral_code) values(p_user_id,p_referral_code) on conflict(user_id) do nothing;
  select to_jsonb(a) into v_row from private.affiliate_accounts a where user_id=p_user_id;
  return v_row;
 elsif p_action='overview' then
  select jsonb_build_object('account',to_jsonb(a),'referrals',coalesce((select jsonb_agg(jsonb_build_object('status',r.status,'created_at',r.created_at) order by r.created_at desc) from private.affiliate_referrals r where r.affiliate_user_id=p_user_id),'[]'::jsonb),'total_referrals',(select count(*) from private.affiliate_referrals r where r.affiliate_user_id=p_user_id)) into v_row
  from private.affiliate_accounts a where a.user_id=p_user_id;
  return coalesce(v_row,'{}'::jsonb);
 else raise exception 'Unknown affiliate action'; end if;
end;
$function$


CREATE OR REPLACE FUNCTION public.myworld_demo_trade_action(p_action text, p_user_id uuid, p_symbol text DEFAULT NULL::text, p_side text DEFAULT NULL::text, p_quantity numeric DEFAULT NULL::numeric, p_unit_price_kobo bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare v_balance bigint;v_total bigint;v_position numeric;v_orders jsonb;v_positions jsonb;
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service role required';end if;
 if p_user_id is null then raise exception 'User required';end if;
 insert into private.demo_trading_accounts(user_id) values(p_user_id) on conflict(user_id) do nothing;
 if p_action='portfolio' then
  select balance_kobo into v_balance from private.demo_trading_accounts where user_id=p_user_id;
  select coalesce(jsonb_agg(to_jsonb(o) order by o.created_at desc),'[]'::jsonb) into v_orders from (select id,symbol,side,quantity,unit_price_kobo,total_kobo,created_at from private.demo_trading_orders where user_id=p_user_id order by created_at desc limit 50)o;
  select coalesce(jsonb_agg(jsonb_build_object('symbol',p.symbol,'quantity',p.qty,'net_cost_kobo',p.net_cost) order by p.symbol),'[]'::jsonb) into v_positions
  from (select symbol,sum(case when side='buy' then quantity else -quantity end) qty,sum(case when side='buy' then total_kobo else -total_kobo end) net_cost from private.demo_trading_orders where user_id=p_user_id group by symbol having sum(case when side='buy' then quantity else -quantity end)>0)p;
  return jsonb_build_object('balance_kobo',v_balance,'starting_balance_kobo',100000000,'orders',v_orders,'positions',v_positions);
 elsif p_action='trade' then
  if p_symbol not in ('MW-BTC','MW-ETH','MW-GOLD','MW-TECH') or p_side not in ('buy','sell') or p_quantity is null or p_quantity<=0 or p_quantity>100000 then raise exception 'Invalid practice order';end if;
  if p_unit_price_kobo is null or p_unit_price_kobo<=0 then raise exception 'Invalid practice quote';end if;
  v_total=round(p_quantity*p_unit_price_kobo);
  if v_total<=0 then raise exception 'Order value is too small';end if;
  perform pg_advisory_xact_lock(hashtext(p_user_id::text));
  select balance_kobo into v_balance from private.demo_trading_accounts where user_id=p_user_id for update;
  if p_side='buy' then
   if v_total>v_balance then raise exception 'Insufficient virtual funds';end if;
   update private.demo_trading_accounts set balance_kobo=balance_kobo-v_total,updated_at=now() where user_id=p_user_id;
  else
   select coalesce(sum(case when side='buy' then quantity else -quantity end),0) into v_position from private.demo_trading_orders where user_id=p_user_id and symbol=p_symbol;
   if v_position<p_quantity then raise exception 'Not enough units in your demo position to sell';end if;
   update private.demo_trading_accounts set balance_kobo=balance_kobo+v_total,updated_at=now() where user_id=p_user_id;
  end if;
  insert into private.demo_trading_orders(user_id,symbol,side,quantity,unit_price_kobo,total_kobo) values(p_user_id,p_symbol,p_side,p_quantity,p_unit_price_kobo,v_total);
  select balance_kobo into v_balance from private.demo_trading_accounts where user_id=p_user_id;
  return jsonb_build_object('success',true,'balance_kobo',v_balance,'total_kobo',v_total,'symbol',p_symbol,'side',p_side,'quantity',p_quantity);
 else raise exception 'Unknown demo trading action';end if;
end;
$function$


CREATE OR REPLACE FUNCTION public.myworld_feature_action(p_action text, p_user_id uuid, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare v_result jsonb;
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service role required'; end if;
 if p_action='list' then
  select coalesce(jsonb_object_agg(feature_key,enabled),'{}'::jsonb) into v_result from private.myworld_feature_flags;
  return v_result;
 elsif p_action='set' then
  insert into private.myworld_feature_flags(feature_key,enabled,updated_by,updated_at)
  values(p_payload->>'feature_key',(p_payload->>'enabled')::boolean,p_user_id,now())
  on conflict(feature_key) do update set enabled=excluded.enabled,updated_by=excluded.updated_by,updated_at=now();
  return jsonb_build_object('feature_key',p_payload->>'feature_key','enabled',(p_payload->>'enabled')::boolean);
 else raise exception 'Unknown feature action'; end if;
end;
$function$


CREATE OR REPLACE FUNCTION public.myworld_gift_submission_action(p_action text, p_user_id uuid, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare v_row jsonb;v_id uuid;v_target uuid;v_amount bigint;v_ref text;v_actor_email text;
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service role required';end if;
 if p_user_id is null then raise exception 'User required';end if;
 if p_action='create' then
  insert into private.gift_card_submissions(user_id,brand,denomination,currency,image_path,user_note)
  values(p_user_id,left(trim(p_payload->>'brand'),60),(p_payload->>'denomination')::numeric,p_payload->>'currency',left(p_payload->>'image_path',500),left(p_payload->>'user_note',500))
  returning to_jsonb(gift_card_submissions.*) into v_row;return v_row;
 elsif p_action='list' then
  select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at desc),'[]'::jsonb) into v_row from private.gift_card_submissions t where t.user_id=p_user_id;return v_row;
 elsif p_action='admin-list' then
  select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at desc),'[]'::jsonb) into v_row from (select * from private.gift_card_submissions order by created_at desc limit 200)t;return v_row;
 elsif p_action='admin-review' then
  v_id=(p_payload->>'id')::uuid;v_actor_email=lower(trim(p_payload->>'actor_email'));
  if p_payload->>'status' not in ('reviewing','rejected','credited') then raise exception 'Invalid review status';end if;
  select user_id into v_target from private.gift_card_submissions where id=v_id and status in ('submitted','reviewing') for update;
  if v_target is null then raise exception 'Submission not found or already finalized';end if;
  if p_payload->>'status'='credited' then
   v_amount=(p_payload->>'quote_kobo')::bigint;
   if v_amount<10000 or v_amount>100000000000 then raise exception 'Credit quote must be between ₦100 and ₦1,000,000,000';end if;
   v_ref='MWGIFTREVIEW_'||replace(gen_random_uuid()::text,'-','');
   perform private.admin_credit_wallet(p_user_id,v_actor_email,v_target,v_amount,v_ref,'Verified gift card submission credit: '||left(coalesce(p_payload->>'admin_note',''),350));
   update private.gift_card_submissions set status='credited',quote_kobo=v_amount,admin_note=left(p_payload->>'admin_note',1000),reviewed_by=p_user_id,reviewed_at=now(),credit_reference=v_ref,updated_at=now() where id=v_id returning to_jsonb(gift_card_submissions.*) into v_row;
  else
   update private.gift_card_submissions set status=p_payload->>'status',admin_note=left(p_payload->>'admin_note',1000),reviewed_by=p_user_id,reviewed_at=now(),updated_at=now() where id=v_id returning to_jsonb(gift_card_submissions.*) into v_row;
  end if;
  return v_row;
 else raise exception 'Unknown gift submission action';end if;
end;
$function$


CREATE OR REPLACE FUNCTION public.myworld_service_action(p_action text, p_user_id uuid, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare v_id uuid; v_row jsonb; v_status text; v_amount bigint; v_wallet bigint; v_pending bigint; v_ref text;
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service role required'; end if;
 if p_user_id is null then raise exception 'User is required'; end if;
 if p_action='create-support' then
  insert into private.support_tickets(user_id,subject,category,message) values(p_user_id,left(trim(p_payload->>'subject'),140),p_payload->>'category',left(trim(p_payload->>'message'),4000)) returning to_jsonb(support_tickets.*) into v_row; return v_row;
 elsif p_action='list-support' then
  select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at desc),'[]'::jsonb) into v_row from private.support_tickets t where t.user_id=p_user_id; return v_row;
 elsif p_action='admin-list-support' then
  select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at desc),'[]'::jsonb) into v_row from (select * from private.support_tickets order by created_at desc limit 200) t; return v_row;
 elsif p_action='admin-reply-support' then
  v_id=(p_payload->>'id')::uuid;
  update private.support_tickets set admin_reply=left(trim(p_payload->>'reply'),4000),status=case when p_payload->>'status' in ('open','in_progress','resolved','closed') then p_payload->>'status' else 'in_progress' end,replied_by=p_user_id,replied_at=now(),updated_at=now() where id=v_id returning to_jsonb(support_tickets.*) into v_row;
  if v_row is null then raise exception 'Support ticket not found'; end if; return v_row;
 elsif p_action='create-withdrawal' then
  v_amount=round((p_payload->>'amount_naira')::numeric*100);
  if v_amount<10000 then raise exception 'Minimum withdrawal is ₦100'; end if;
  if (p_payload->>'amount_naira')::numeric*100<>v_amount then raise exception 'Maximum 2 decimal places allowed'; end if;
  perform pg_advisory_xact_lock(hashtext(p_user_id::text));
  select coalesce(balance_kobo,0) into v_wallet from public.wallets where user_id=p_user_id for update;
  select coalesce(sum(amount_kobo),0) into v_pending from private.withdrawal_requests where user_id=p_user_id and status in ('pending','approved');
  if v_amount+v_pending>coalesce(v_wallet,0) then raise exception 'Requested amount exceeds your available wallet balance after pending withdrawal requests'; end if;
  insert into private.withdrawal_requests(user_id,amount_kobo,payout_method,destination,user_note) values(p_user_id,v_amount,'bank_transfer',jsonb_build_object('account_name',left(p_payload->>'account_name',120),'account_number',left(p_payload->>'account_number',30),'bank_name',left(p_payload->>'bank_name',120)),left(p_payload->>'note',500)) returning to_jsonb(withdrawal_requests.*) into v_row; return v_row;
 elsif p_action='list-withdrawals' then
  select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at desc),'[]'::jsonb) into v_row from private.withdrawal_requests t where t.user_id=p_user_id; return v_row;
 elsif p_action='admin-list-withdrawals' then
  select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at desc),'[]'::jsonb) into v_row from (select * from private.withdrawal_requests order by created_at desc limit 200) t; return v_row;
 elsif p_action='admin-review-withdrawal' then
  v_id=(p_payload->>'id')::uuid;v_status=p_payload->>'status';
  if v_status not in ('approved','rejected','paid') then raise exception 'Invalid withdrawal status'; end if;
  if v_status='paid' and length(trim(coalesce(p_payload->>'payout_reference','')))<3 then raise exception 'Payout reference is required to mark a withdrawal paid'; end if;
  if v_status='approved' then
   select coalesce(w.balance_kobo,0) into v_wallet from private.withdrawal_requests r join public.wallets w on w.user_id=r.user_id where r.id=v_id for update of w;
   select coalesce(r.amount_kobo,0) into v_amount from private.withdrawal_requests r where r.id=v_id and r.status='pending';
   if v_amount is null then raise exception 'Only pending requests can be approved'; end if;
   select coalesce(sum(amount_kobo),0) into v_pending from private.withdrawal_requests where user_id=(select user_id from private.withdrawal_requests where id=v_id) and status='approved';
   if v_amount+v_pending>coalesce(v_wallet,0) then raise exception 'Wallet balance is no longer sufficient to approve this request'; end if;
  end if;
  if v_status='paid' then
   select r.amount_kobo into v_amount from private.withdrawal_requests r where r.id=v_id and r.status='approved' for update;
   if v_amount is null then raise exception 'Only approved requests can be marked paid'; end if;
   select w.balance_kobo into v_wallet from private.withdrawal_requests r join public.wallets w on w.user_id=r.user_id where r.id=v_id for update of w;
   if coalesce(v_wallet,0)<v_amount then raise exception 'Wallet balance is insufficient to settle this withdrawal'; end if;
   update public.wallets w set balance_kobo=w.balance_kobo-v_amount,updated_at=now() from private.withdrawal_requests r where r.id=v_id and w.user_id=r.user_id;
   v_ref='MW-WD-'||replace(gen_random_uuid()::text,'-','');
   insert into public.payment_transactions(user_id,provider,reference,amount_kobo,currency,status,channel,gateway_response,paid_at,metadata)
   select user_id,'withdrawal',v_ref,v_amount,'NGN','success','manual_payout',left(p_payload->>'payout_reference',500),now(),jsonb_build_object('withdrawal_request_id',id,'payout_reference',left(p_payload->>'payout_reference',120))
   from private.withdrawal_requests where id=v_id;
  end if;
  update private.withdrawal_requests set status=v_status,admin_note=left(p_payload->>'admin_note',1000),reviewed_by=p_user_id,reviewed_at=now(),paid_at=case when v_status='paid' then now() else paid_at end,payout_reference=case when v_status='paid' then left(p_payload->>'payout_reference',120) else payout_reference end,updated_at=now()
  where id=v_id and (v_status<>'paid' or status='approved') returning to_jsonb(withdrawal_requests.*) into v_row;
  if v_row is null then raise exception 'Withdrawal request not found or status has changed'; end if; return v_row;
 elsif p_action='create-admin-application' then
  if exists(select 1 from private.admin_applications where user_id=p_user_id and status='pending') then raise exception 'You already have a pending admin application'; end if;
  insert into private.admin_applications(user_id,full_name,contact,requested_role,experience,reason) values(p_user_id,left(trim(p_payload->>'full_name'),120),left(trim(p_payload->>'contact'),180),left(trim(p_payload->>'requested_role'),80),left(trim(p_payload->>'experience'),2000),left(trim(p_payload->>'reason'),2000)) returning to_jsonb(admin_applications.*) into v_row; return v_row;
 elsif p_action='list-admin-applications' then
  select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at desc),'[]'::jsonb) into v_row from private.admin_applications t where t.user_id=p_user_id; return v_row;
 elsif p_action='admin-list-applications' then
  select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at desc),'[]'::jsonb) into v_row from (select * from private.admin_applications order by created_at desc limit 200) t; return v_row;
 elsif p_action='admin-review-application' then
  v_id=(p_payload->>'id')::uuid;v_status=p_payload->>'status';
  if v_status not in ('approved','rejected') then raise exception 'Invalid application status'; end if;
  update private.admin_applications set status=v_status,admin_note=left(p_payload->>'admin_note',1000),reviewed_by=p_user_id,reviewed_at=now(),updated_at=now() where id=v_id returning to_jsonb(admin_applications.*) into v_row;
  if v_row is null then raise exception 'Application not found'; end if; return v_row;
 elsif p_action='transactions' then
  select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at desc),'[]'::jsonb) into v_row from (select id,provider,reference,amount_kobo,currency,status,channel,paid_at,created_at,metadata from public.payment_transactions where user_id=p_user_id order by created_at desc limit 100) t; return v_row;
 elsif p_action='analytics' then
  select jsonb_build_object('users',(select count(*) from auth.users),'shipments',(select count(*) from public.shipments),'wallets',(select count(*) from public.wallets),'wallet_balance_kobo',(select coalesce(sum(balance_kobo),0) from public.wallets),'successful_payments',(select count(*) from public.payment_transactions where status='success'),'successful_volume_kobo',(select coalesce(sum(amount_kobo),0) from public.payment_transactions where status='success' and provider<>'withdrawal'),'open_support',(select count(*) from private.support_tickets where status in ('open','in_progress')),'pending_withdrawals',(select count(*) from private.withdrawal_requests where status='pending'),'pending_admin_applications',(select count(*) from private.admin_applications where status='pending'),'active_gift_cards',(select count(*) from private.myworld_gift_cards where status='active')) into v_row; return v_row;
 else raise exception 'Unknown service action';
 end if;
end;
$function$



revoke all on function public.myworld_service_action(text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.myworld_service_action(text,uuid,jsonb) to service_role;
revoke all on function public.myworld_feature_action(text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.myworld_feature_action(text,uuid,jsonb) to service_role;
revoke all on function public.myworld_affiliate_action(text,uuid,text) from public,anon,authenticated;
grant execute on function public.myworld_affiliate_action(text,uuid,text) to service_role;
revoke all on function public.myworld_demo_trade_action(text,uuid,text,text,numeric,bigint) from public,anon,authenticated;
grant execute on function public.myworld_demo_trade_action(text,uuid,text,text,numeric,bigint) to service_role;
revoke all on function public.myworld_gift_submission_action(text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.myworld_gift_submission_action(text,uuid,jsonb) to service_role;
