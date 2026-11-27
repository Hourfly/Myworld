-- Self-service shipment tracking schema for MyWorld
create extension if not exists pgcrypto with schema extensions;
create table if not exists public.shipments (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade,
 tracking_code text not null unique, title text not null, sender_name text not null, recipient_name text not null,
 recipient_email text, origin text not null, destination text not null,
 transport_type text not null check (transport_type in ('air','sea','road')),
 description text, status text not null default 'preparing' check (status in ('preparing','in_transit','arrived','delivered','cancelled')),
 departure_at timestamptz not null, arrival_at timestamptz not null, password_hash text not null,
 qr_token_hash text not null unique, qr_token_expires_at timestamptz, show_contents boolean not null default true,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 constraint shipment_dates_valid check (arrival_at > departure_at)
);
create index if not exists shipments_owner_created_idx on public.shipments(owner_id,created_at desc);
create table if not exists public.shipment_contents (
 id uuid primary key default gen_random_uuid(), shipment_id uuid not null references public.shipments(id) on delete cascade,
 description text not null, quantity integer not null default 1 check(quantity>0), image_path text,
 created_at timestamptz not null default now()
);
create table if not exists public.shipment_feed (
 id uuid primary key default gen_random_uuid(), shipment_id uuid not null references public.shipments(id) on delete cascade,
 message text not null, publish_at timestamptz not null, published boolean not null default false, created_at timestamptz not null default now()
);
create index if not exists shipment_feed_due_idx on public.shipment_feed(publish_at) where published=false;
alter table public.shipments enable row level security;
alter table public.shipment_contents enable row level security;
alter table public.shipment_feed enable row level security;
create policy "Owners manage their shipments" on public.shipments for all to authenticated using ((select auth.uid())=owner_id) with check ((select auth.uid())=owner_id);
create policy "Owners manage shipment contents" on public.shipment_contents for all to authenticated using (exists(select 1 from public.shipments s where s.id=shipment_id and s.owner_id=(select auth.uid()))) with check (exists(select 1 from public.shipments s where s.id=shipment_id and s.owner_id=(select auth.uid())));
create policy "Owners manage shipment feed" on public.shipment_feed for all to authenticated using (exists(select 1 from public.shipments s where s.id=shipment_id and s.owner_id=(select auth.uid()))) with check (exists(select 1 from public.shipments s where s.id=shipment_id and s.owner_id=(select auth.uid())));
grant select,insert,update,delete on public.shipments,public.shipment_contents,public.shipment_feed to authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('shipment-images','shipment-images',false,10485760,array['image/jpeg','image/png','image/webp']) on conflict(id) do nothing;
create policy "Shipment owners upload images" on storage.objects for insert to authenticated with check(bucket_id='shipment-images' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy "Shipment owners read images" on storage.objects for select to authenticated using(bucket_id='shipment-images' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy "Shipment owners delete images" on storage.objects for delete to authenticated using(bucket_id='shipment-images' and (storage.foldername(name))[1]=(select auth.uid())::text);
-- Scheduled announcements are published once their configured time is reached.
create extension if not exists pg_cron;
select cron.schedule('myworld-publish-shipment-feed','* * * * *',$$update public.shipment_feed set published=true where published=false and publish_at<=now()$$);
