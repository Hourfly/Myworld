-- Add Premium/Coin card classification and backend-calculated rate conversion.
alter table private.myworld_gift_cards
 add column if not exists card_type text not null default 'premium',
 add column if not exists face_value_kobo bigint,
 add column if not exists rate_percent numeric(7,3) not null default 100.000;
update private.myworld_gift_cards set face_value_kobo=amount_kobo where face_value_kobo is null;
alter table private.myworld_gift_cards alter column face_value_kobo set not null;
alter table private.myworld_gift_cards drop constraint if exists myworld_gift_cards_card_type_check;
alter table private.myworld_gift_cards add constraint myworld_gift_cards_card_type_check check(card_type in ('premium','coin'));
alter table private.myworld_gift_cards drop constraint if exists myworld_gift_cards_rate_percent_check;
alter table private.myworld_gift_cards add constraint myworld_gift_cards_rate_percent_check check(rate_percent > 0 and rate_percent <= 1000);
alter table private.myworld_gift_cards drop constraint if exists myworld_gift_cards_face_value_check;
alter table private.myworld_gift_cards add constraint myworld_gift_cards_face_value_check check(face_value_kobo >= 10000 and face_value_kobo <= 1000000000);

drop function if exists public.admin_create_myworld_gift_card(uuid,bigint,text,text,timestamp with time zone,text);
drop function if exists private.admin_create_myworld_gift_card(uuid,bigint,text,text,timestamp with time zone,text);
create or replace function private.admin_create_myworld_gift_card(p_actor_user_id uuid,p_face_value_kobo bigint,p_rate_percent numeric,p_card_type text,p_code_hash text,p_code_prefix text,p_expires_at timestamptz,p_note text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_id uuid;v_reference text;v_credit_kobo bigint;
begin
 if p_actor_user_id is null or p_face_value_kobo<10000 or p_face_value_kobo>1000000000 or p_rate_percent<=0 or p_rate_percent>1000 or p_card_type not in ('premium','coin') or p_code_hash !~ '^[0-9a-f]{64}$' then raise exception 'Invalid MyWorld Card details';end if;
 v_credit_kobo=round(p_face_value_kobo*p_rate_percent/100.0);
 if v_credit_kobo<10000 or v_credit_kobo>1000000000 then raise exception 'Calculated wallet credit must be between ₦100 and ₦10,000,000';end if;
 insert into private.myworld_gift_cards(code_hash,code_prefix,amount_kobo,face_value_kobo,rate_percent,card_type,expires_at,created_by,note)
 values(p_code_hash,p_code_prefix,v_credit_kobo,p_face_value_kobo,p_rate_percent,p_card_type,p_expires_at,p_actor_user_id,left(coalesce(p_note,''),250)) returning id into v_id;
 v_reference:='MWCARD_'||replace(gen_random_uuid()::text,'-','');
 insert into private.admin_action_logs(actor_user_id,actor_email,target_user_id,action,amount_kobo,reference,reason,details)
 values(p_actor_user_id,'ugohjeremiah16@gmail.com',p_actor_user_id,'gift_card_create',v_credit_kobo,v_reference,coalesce(nullif(left(p_note,500),''),'Gift card created'),jsonb_build_object('gift_card_id',v_id,'code_prefix',p_code_prefix,'card_type',p_card_type,'face_value_kobo',p_face_value_kobo,'rate_percent',p_rate_percent,'credit_kobo',v_credit_kobo,'expires_at',p_expires_at));
 return jsonb_build_object('id',v_id,'reference',v_reference,'amount_kobo',v_credit_kobo,'face_value_kobo',p_face_value_kobo,'rate_percent',p_rate_percent,'card_type',p_card_type,'expires_at',p_expires_at,'status','active');
end $$;
create or replace function public.admin_create_myworld_gift_card(p_actor_user_id uuid,p_face_value_kobo bigint,p_rate_percent numeric,p_card_type text,p_code_hash text,p_code_prefix text,p_expires_at timestamptz,p_note text)
returns jsonb language sql security definer set search_path=''
as $$ select private.admin_create_myworld_gift_card(p_actor_user_id,p_face_value_kobo,p_rate_percent,p_card_type,p_code_hash,p_code_prefix,p_expires_at,p_note) $$;
revoke all on function private.admin_create_myworld_gift_card(uuid,bigint,numeric,text,text,text,timestamptz,text) from public,anon,authenticated;
revoke all on function public.admin_create_myworld_gift_card(uuid,bigint,numeric,text,text,text,timestamptz,text) from public,anon,authenticated;
grant execute on function public.admin_create_myworld_gift_card(uuid,bigint,numeric,text,text,text,timestamptz,text) to service_role;

create or replace function private.admin_list_myworld_gift_cards()
returns jsonb language sql stable security definer set search_path=''
as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'code_prefix',code_prefix,'amount_kobo',amount_kobo,'face_value_kobo',face_value_kobo,'rate_percent',rate_percent,'card_type',card_type,'status',case when status='active' and expires_at is not null and expires_at<=now() then 'expired' else status end,'expires_at',expires_at,'created_at',created_at,'redeemed_at',redeemed_at,'redemption_reference',redemption_reference) order by created_at desc),'[]'::jsonb) from private.myworld_gift_cards
$$;

create or replace function private.redeem_myworld_gift_card(p_user_id uuid,p_code_hash text,p_reference text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_card private.myworld_gift_cards%rowtype;v_balance bigint;
begin
 if p_user_id is null or p_code_hash !~ '^[0-9a-f]{64}$' then raise exception 'Invalid redemption request';end if;
 select * into v_card from private.myworld_gift_cards where code_hash=p_code_hash for update;
 if not found then raise exception 'This MyWorld Card code is not valid';end if;
 if v_card.status='redeemed' then raise exception 'This MyWorld Card has already been redeemed';end if;
 if v_card.status='disabled' then raise exception 'This MyWorld Card has been deactivated';end if;
 if v_card.status<>'active' then raise exception 'This MyWorld Card is not active';end if;
 if v_card.expires_at is not null and v_card.expires_at<=now() then update private.myworld_gift_cards set status='expired' where id=v_card.id;raise exception 'This MyWorld Card has expired';end if;
 insert into public.wallets(user_id,balance_kobo,currency) values(p_user_id,v_card.amount_kobo,'NGN') on conflict(user_id) do update set balance_kobo=public.wallets.balance_kobo+excluded.balance_kobo,updated_at=now() returning balance_kobo into v_balance;
 insert into public.payment_transactions(user_id,provider,reference,amount_kobo,currency,status,channel,gateway_response,paid_at,metadata)
 values(p_user_id,'myworld_card',p_reference,v_card.amount_kobo,'NGN','success','gift_card','MyWorld Card redeemed',now(),jsonb_build_object('gift_card_id',v_card.id,'code_prefix',v_card.code_prefix,'card_type',v_card.card_type,'face_value_kobo',v_card.face_value_kobo,'rate_percent',v_card.rate_percent));
 update private.myworld_gift_cards set status='redeemed',redeemed_by=p_user_id,redeemed_at=now(),redemption_reference=p_reference where id=v_card.id;
 insert into private.myworld_gift_card_redemptions(gift_card_id,user_id,amount_kobo,reference) values(v_card.id,p_user_id,v_card.amount_kobo,p_reference);
 return jsonb_build_object('success',true,'credited_kobo',v_card.amount_kobo,'face_value_kobo',v_card.face_value_kobo,'rate_percent',v_card.rate_percent,'card_type',v_card.card_type,'balance_kobo',v_balance,'reference',p_reference);
end $$;
