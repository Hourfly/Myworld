create table if not exists private.wallet_transfers (
 id uuid primary key default gen_random_uuid(),
 reference text not null unique,
 sender_id uuid not null references auth.users(id) on delete restrict,
 receiver_id uuid not null references auth.users(id) on delete restrict,
 amount_kobo bigint not null check(amount_kobo>0),
 note text not null default '',
 status text not null default 'success' check(status='success'),
 created_at timestamptz not null default now(),
 constraint wallet_transfers_different_accounts check(sender_id<>receiver_id)
);
create index if not exists wallet_transfers_sender_created_idx on private.wallet_transfers(sender_id,created_at desc);
create index if not exists wallet_transfers_receiver_created_idx on private.wallet_transfers(receiver_id,created_at desc);
alter table public.payment_transactions drop constraint if exists payment_transactions_provider_check;
alter table public.payment_transactions add constraint payment_transactions_provider_check check(provider=any(array['paystack','myworld_card','withdrawal','admin','wallet_transfer']::text[]));
alter table private.wallet_transfers enable row level security;
revoke all on private.wallet_transfers from anon,authenticated;
create or replace function public.myworld_wallet_transfer_action(p_action text,p_user_id uuid,p_payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare
 v_target uuid; v_amount bigint; v_balance bigint; v_ref text; v_transfer private.wallet_transfers; v_sender_email text; v_receiver_email text; v_note text;
begin
 if p_user_id is null then raise exception 'Sign in to use your wallet.'; end if;
 if p_action='send' then
  v_target:=nullif(p_payload->>'target_user_id','')::uuid;
  v_amount:=nullif(p_payload->>'amount_kobo','')::bigint;
  v_note:=left(coalesce(p_payload->>'note',''),140);
  v_sender_email:=left(coalesce(p_payload->>'sender_email',''),254);
  v_receiver_email:=left(coalesce(p_payload->>'receiver_email',''),254);
  if v_target is null or v_target=p_user_id then raise exception 'Choose another MyWorld account.'; end if;
  if v_amount is null or v_amount<1 or v_amount>1000000000 then raise exception 'Enter a valid transfer amount.'; end if;
  insert into public.wallets(user_id,balance_kobo,currency) values(p_user_id,0,'NGN') on conflict(user_id) do nothing;
  insert into public.wallets(user_id,balance_kobo,currency) values(v_target,0,'NGN') on conflict(user_id) do nothing;
  perform 1 from public.wallets where user_id in (p_user_id,v_target) order by user_id for update;
  select balance_kobo into v_balance from public.wallets where user_id=p_user_id;
  if coalesce(v_balance,0)<v_amount then raise exception 'Insufficient wallet balance.'; end if;
  update public.wallets set balance_kobo=balance_kobo-v_amount,updated_at=now() where user_id=p_user_id;
  update public.wallets set balance_kobo=balance_kobo+v_amount,updated_at=now() where user_id=v_target;
  v_ref:='MWT-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,18));
  insert into private.wallet_transfers(reference,sender_id,receiver_id,amount_kobo,note) values(v_ref,p_user_id,v_target,v_amount,v_note) returning * into v_transfer;
  insert into public.payment_transactions(user_id,provider,reference,amount_kobo,currency,status,channel,gateway_response,paid_at,metadata)
   values(p_user_id,'wallet_transfer',v_ref||'-S',v_amount,'NGN','success','internal_wallet','MyWorld account transfer',now(),jsonb_build_object('direction','out','counterparty_email',v_receiver_email,'transfer_reference',v_ref,'note',v_note));
  insert into public.payment_transactions(user_id,provider,reference,amount_kobo,currency,status,channel,gateway_response,paid_at,metadata)
   values(v_target,'wallet_transfer',v_ref||'-R',v_amount,'NGN','success','internal_wallet','MyWorld account transfer',now(),jsonb_build_object('direction','in','counterparty_email',v_sender_email,'transfer_reference',v_ref,'note',v_note));
  insert into public.user_notifications(user_id,event_key,type,title,body,data)
   values(v_target,'wallet_received_'||v_ref,'admin_message','Money received','You received '||to_char(v_amount::numeric/100,'FM999G999G999G990D00')||' NGN from a MyWorld account.',jsonb_build_object('reference',v_ref,'amount_kobo',v_amount));
  insert into public.user_notifications(user_id,event_key,type,title,body,data)
   values(p_user_id,'wallet_sent_'||v_ref,'admin_message','Transfer sent','Your MyWorld wallet transfer was completed.',jsonb_build_object('reference',v_ref,'amount_kobo',v_amount));
  return jsonb_build_object('reference',v_ref,'amount_kobo',v_amount,'sender_balance_kobo',v_balance-v_amount,'receiver_id',v_target,'created_at',v_transfer.created_at);
 elsif p_action='history' then
  return coalesce((select jsonb_agg(to_jsonb(t) order by t.created_at desc) from (select reference,amount_kobo,note,status,created_at,case when sender_id=p_user_id then 'out' else 'in' end as direction,case when sender_id=p_user_id then receiver_id else sender_id end as counterparty_id from private.wallet_transfers where sender_id=p_user_id or receiver_id=p_user_id order by created_at desc limit 50) t),'[]'::jsonb);
 end if;
 raise exception 'Unknown wallet transfer action.';
end $$;
revoke all on function public.myworld_wallet_transfer_action(text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.myworld_wallet_transfer_action(text,uuid,jsonb) to service_role;
