-- Jalankan di Supabase > SQL Editor
create table profiles (
  id uuid primary key references auth.users on delete cascade,
  full_name text, company text, phone text,
  role text not null default 'customer' check (role in ('customer','admin')),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz default now()
);
create table categories (id serial primary key, name text not null);
create table products (
  id uuid primary key default gen_random_uuid(),
  category_id int references categories(id),
  name text not null, price numeric not null,
  stock int,                       -- null = tidak dibatasi
  weight_gr numeric, description text, image_url text,
  is_active boolean default true, created_at timestamptz default now()
);
create table orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id),
  status text not null default 'pending'
    check (status in ('pending','approved','cancel_requested','cancelled','rejected')),
  prev_status text, created_at timestamptz default now()
);
create table order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references orders(id) on delete cascade,
  product_id uuid not null references products(id),
  qty int not null check (qty > 0), price numeric not null
);

-- helper
create function is_admin() returns boolean language sql security definer stable set search_path=public as
$$ select exists(select 1 from profiles where id=auth.uid() and role='admin') $$;
create function is_approved() returns boolean language sql security definer stable set search_path=public as
$$ select exists(select 1 from profiles where id=auth.uid() and status='approved') $$;

-- profil otomatis saat daftar (role selalu customer, status pending)
create function handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into profiles(id, full_name, company, phone)
  values (new.id, new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'company', new.raw_user_meta_data->>'phone');
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
for each row execute function handle_new_user();

-- RLS
alter table profiles enable row level security;
alter table categories enable row level security;
alter table products enable row level security;
alter table orders enable row level security;
alter table order_items enable row level security;

create policy "profil sendiri/admin" on profiles for select using (id=auth.uid() or is_admin());
create policy "admin ubah profil" on profiles for update using (is_admin()) with check (is_admin());

create policy "kategori publik" on categories for select using (true);
create policy "admin kategori" on categories for all using (is_admin()) with check (is_admin());
create policy "produk publik" on products for select using (is_active or is_admin());
create policy "admin produk" on products for all using (is_admin()) with check (is_admin());

create policy "order sendiri/admin" on orders for select using (user_id=auth.uid() or is_admin());
create policy "item order sendiri/admin" on order_items for select using (
  exists(select 1 from orders o where o.id=order_id and (o.user_id=auth.uid() or is_admin())));
-- tidak ada policy insert/update di orders: semua lewat fungsi di bawah

-- Buat pesanan (harga diambil dari database, bukan dari app)
create function place_order(items jsonb) returns uuid language plpgsql security definer set search_path=public as $$
declare oid uuid; it jsonb; p products;
begin
  if not is_approved() then raise exception 'Akun belum disetujui admin'; end if;
  if jsonb_array_length(items)=0 then raise exception 'Keranjang kosong'; end if;
  insert into orders(user_id) values (auth.uid()) returning id into oid;
  for it in select * from jsonb_array_elements(items) loop
    select * into p from products where id=(it->>'product_id')::uuid and is_active;
    if not found then raise exception 'Produk tidak ditemukan'; end if;
    if (it->>'qty')::int <= 0 then raise exception 'Qty tidak valid'; end if;
    insert into order_items(order_id,product_id,qty,price) values (oid,p.id,(it->>'qty')::int,p.price);
  end loop;
  return oid;
end $$;

-- Pembeli ajukan batal
create function request_cancel(oid uuid) returns void language plpgsql security definer set search_path=public as $$
begin
  update orders set prev_status=status, status='cancel_requested'
  where id=oid and user_id=auth.uid() and status in ('pending','approved');
  if not found then raise exception 'Pesanan tidak bisa dibatalkan'; end if;
end $$;

-- Admin ubah status. new_status: approved | rejected | cancelled | reject_cancel
create function admin_set_order_status(oid uuid, new_status text) returns void language plpgsql security definer set search_path=public as $$
declare o orders; it record;
begin
  if not is_admin() then raise exception 'Hanya admin'; end if;
  select * into o from orders where id=oid for update;
  if not found then raise exception 'Pesanan tidak ditemukan'; end if;
  if new_status='reject_cancel' then
    if o.status<>'cancel_requested' then raise exception 'Bukan pengajuan batal'; end if;
    update orders set status=coalesce(o.prev_status,'approved'), prev_status=null where id=oid; return;
  end if;
  if new_status not in ('approved','rejected','cancelled') then raise exception 'Status tidak valid'; end if;
  if new_status='approved' then
    if o.status<>'pending' then raise exception 'Hanya pesanan pending yang bisa disetujui'; end if;
    for it in select * from order_items where order_id=oid loop
      update products set stock=stock-it.qty where id=it.product_id and (stock is null or stock>=it.qty);
      if not found then raise exception 'Stok tidak cukup'; end if;
    end loop;
  elsif new_status='cancelled' and (o.status='approved' or (o.status='cancel_requested' and o.prev_status='approved')) then
    for it in select * from order_items where order_id=oid loop
      update products set stock=stock+it.qty where id=it.product_id;
    end loop;
  end if;
  update orders set status=new_status, prev_status=null where id=oid;
end $$;

-- Laporan penjualan (pesanan approved)
create function report_by_product() returns table(name text, total_qty bigint, total_amount numeric)
language plpgsql security definer set search_path=public as $$
begin
  if not is_admin() then raise exception 'Hanya admin'; end if;
  return query
    select p.name, sum(oi.qty)::bigint, sum(oi.qty*oi.price)
    from order_items oi join orders o on o.id=oi.order_id join products p on p.id=oi.product_id
    where o.status='approved' group by p.name order by 3 desc;
end $$;

revoke all on function place_order(jsonb), request_cancel(uuid), admin_set_order_status(uuid,text), report_by_product() from public, anon;
grant execute on function place_order(jsonb), request_cancel(uuid), admin_set_order_status(uuid,text), report_by_product() to authenticated;

-- Data contoh
insert into categories(name) values ('Pharma & Lab'),('Medical'),('Cosmetic & Healthcare'),('Food'),('Fashion');
insert into products(category_id,name,price,stock,weight_gr,description) values
 (4,'Garpu Lipat (POLOS/UNWRAPPED)',275,1000,2,'Garpu lipat plastik'),
 (4,'Sendok Lipat',175,1000,2,'Sendok lipat plastik'),
 (1,'Pipette Dropper N22 Red',2399,500,5,'Pipette dropper plastik');

-- Jadikan akun lu admin (setelah daftar di app):
-- update profiles set role='admin', status='approved' where id=(select id from auth.users where email='EMAIL_LU');
