import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core.dart';
import '../widgets.dart';
import 'product_form.dart';
import 'add_stock_dialog.dart';

class AdminPage extends StatefulWidget {
  final String section; // orders | products | users | report
  const AdminPage({super.key, this.section = 'orders'});
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final _btn = FilledButton.styleFrom(backgroundColor: brand, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)));

  late Future<List> data = _fetch();
  late Future<List> cats = _cats();
  String q = '', flt = 'all'; // kata kunci & filter aktif
  int? cat; // filter kategori (halaman produk)

  @override
  void initState() {
    super.initState();
    sync.addListener(_onSync); // auto reload saat data berubah
  }

  @override
  void dispose() {
    sync.removeListener(_onSync);
    super.dispose();
  }

  void _onSync() {
    if (!mounted) return;
    setState(() {
      data = _fetch();
      cats = _cats();
    });
  }

  Future<List> _cats() async => await sb.from('categories').select().order('id');

  Future<List> _fetch() async {
    switch (widget.section) {
      case 'products':
        return await fetchAdminProducts();
      case 'users':
        return await sb.from('profiles').select().order('created_at', ascending: false);
      case 'report':
        return await sb.from('orders').select('created_at,order_items(qty,price,products(name))').eq('status', 'approved');
      default:
        return await sb
            .from('orders')
            .select('id,status,created_at,profiles(full_name,company),order_items(qty,price,variant_name,products(name))')
            .order('created_at', ascending: false);
    }
  }

  void _reload() => setState(() => data = _fetch());

  Future<void> _run(Future<void> Function() act) async {
    try {
      await act();
    } on PostgrestException catch (e) {
      if (mounted) toast(context, e.message);
    } catch (e) {
      if (mounted) toast(context, 'Gagal: $e');
    }
    if (mounted) _reload();
  }

  Widget _wrap(Widget w) => Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: w));

  // ---------- komponen filter & kerangka ----------
  Widget _chip(String label, bool sel, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label),
          selected: sel,
          showCheckmark: false,
          onSelected: (_) => onTap(),
          backgroundColor: Colors.white,
          selectedColor: brand,
          side: BorderSide(color: sel ? brand : line),
          labelStyle: TextStyle(color: sel ? Colors.white : ink, fontWeight: FontWeight.w600, fontSize: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      );

  Widget _bar(String hint, List<(String, String)> opts, {Widget? extra}) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: Container(
                decoration: cardDeco(10),
                child: TextField(
                  onChanged: (v) => setState(() => q = v.trim().toLowerCase()),
                  decoration: InputDecoration(
                    hintText: hint,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
            if (extra != null) ...[const SizedBox(width: 8), extra],
          ]),
          const SizedBox(height: 10),
          SizedBox(
            height: 36,
            child: ListView(scrollDirection: Axis.horizontal, children: [for (final o in opts) _chip(o.$2, flt == o.$1, () => setState(() => flt = o.$1))]),
          ),
        ]),
      );

  Widget _async(Widget Function(List) build) => FutureBuilder<List>(
        future: data,
        builder: (_, s) {
          if (s.hasError) return Center(child: Text('${s.error}'));
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          return RefreshIndicator(
            onRefresh: () async {
              _reload();
              await data;
            },
            child: build(s.data!),
          );
        },
      );

  Widget _section(String hint, List<(String, String)> opts, Widget Function(List) build, {Widget? extra}) =>
      Column(children: [_bar(hint, opts, extra: extra), Expanded(child: _async(build))]);

  Widget _empty(String t) => ListView(children: [Padding(padding: const EdgeInsets.all(40), child: Center(child: Text(t, style: const TextStyle(color: muted))))]);

  Widget _pill(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: c.withAlpha(28), borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w700)),
      );

  // ================= PESANAN =================
  List<Widget> _acts(Map o) {
    Widget b(String t, String s, [Color? c]) => TextButton(
        onPressed: () => _run(() async => await sb.rpc('admin_set_order_status', params: {'oid': o['id'], 'new_status': s})),
        child: Text(t, style: TextStyle(color: c, fontWeight: FontWeight.w700)));
    switch (o['status']) {
      case 'pending':
        return [b('Tolak', 'rejected', Colors.red), b('Setujui', 'approved', Colors.green)];
      case 'cancel_requested':
        return [b('Tolak Batal', 'reject_cancel'), b('Setujui Batal', 'cancelled', Colors.red)];
      case 'approved':
        return [b('Batalkan', 'cancelled', Colors.red)];
      default:
        return [];
    }
  }

  Widget _orders() => _section(
        'Cari nama / perusahaan',
        const [
          ('all', 'Semua'),
          ('pending', 'Menunggu'),
          ('approved', 'Diterima'),
          ('cancel_requested', 'Minta batal'),
          ('cancelled', 'Dibatalkan'),
          ('rejected', 'Ditolak'),
        ],
        (l) {
          final rows = l.where((o) {
            if (flt != 'all' && o['status'] != flt) return false;
            if (q.isEmpty) return true;
            final w = o['profiles'];
            return '${w?['full_name'] ?? ''} ${w?['company'] ?? ''}'.toLowerCase().contains(q);
          }).toList();
          if (rows.isEmpty) return _empty('Tidak ada pesanan');
          return ListView(padding: const EdgeInsets.only(top: 8, bottom: 24), children: [for (final o in rows) OrderCard(o: o, admin: true, actions: _acts(o))]);
        },
      );

  // ================= PRODUK =================
  Future<void> _saveImages(String pid, List<String> images) async {
    await sb.from('product_images').delete().eq('product_id', pid);
    if (images.isEmpty) return;
    await sb.from('product_images').insert([
      for (var i = 0; i < images.length; i++) {'product_id': pid, 'url': images[i], 'position': i}
    ]);
  }

  Future<void> _saveVariants(String pid, List<Map<String, dynamic>> vs) async {
    final keep = [for (final v in vs) if (v['id'] != null) '${v['id']}'];
    var del = sb.from('product_variants').delete().eq('product_id', pid);
    if (keep.isNotEmpty) del = del.not('id', 'in', '(${keep.join(',')})');
    await del;
    for (var i = 0; i < vs.length; i++) {
      final v = vs[i];
      final tiers = (v['tiers'] as List).cast<Map<String, dynamic>>();
      final row = {'product_id': pid, 'name': v['name'], 'price': v['price'], 'min_order': v['min_order'], 'position': i};
      String vid;
      if (v['id'] != null) {
        await sb.from('product_variants').update(row).eq('id', v['id']);
        vid = '${v['id']}';
      } else {
        final r = await sb.from('product_variants').insert(row).select('id').single();
        vid = '${r['id']}';
      }
      await sb.from('variant_price_tiers').delete().eq('variant_id', vid);
      await sb.from('variant_price_tiers').insert([for (final t in tiers) {'variant_id': vid, ...t}]);
    }
  }

  Future<void> _form([Product? p]) async {
    final List cl = await sb.from('categories').select().order('id');
    if (!mounted) return;
    final d = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => ProductForm(p: p, cats: cl)),
    );
    if (d == null) return;
    await _run(() async {
      final images = (d.remove('images') as List).cast<String>();
      final variants = (d.remove('variants') as List).cast<Map<String, dynamic>>();
      d['price'] = variants.map((v) => v['price'] as num).reduce((a, b) => a < b ? a : b); // harga "mulai dari"
      d['image_url'] = images.isEmpty ? null : images.first; // sampul
      String pid;
      if (p == null) {
        final r = await sb.from('products').insert(d).select('id').single();
        pid = r['id'];
      } else {
        final r = await sb.from('products').update(d).eq('id', p.id).select();
        if (r.isEmpty) {
          if (mounted) toast(context, 'Gagal menyimpan (cek izin/RLS di Supabase)');
          return;
        }
        pid = p.id;
      }
      await _saveImages(pid, images);
      await _saveVariants(pid, variants);
      if (mounted) toast(context, p == null ? 'Produk ditambahkan' : 'Produk diperbarui');
    });
  }

  Future<void> _addStock(Product p) async {
  final n = await showDialog<int>(context: context, builder: (_) => AddStockDialog(p: p));
    if (n == null) return;
    await _run(() async {
      final res = await sb.rpc('admin_add_stock', params: {'pid': p.id, 'amount': n});
      if (mounted) toast(context, '+${nf(n)} pcs. Stok ${p.name} sekarang ${nf(res as num)}');
    });
  }

  bool _isLow(Product p) => p.stock != null && p.stock! < p.variants.map((v) => v.minOrder).reduce((a, b) => a < b ? a : b);

  Future<void> _delete(Product p) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
              title: const Text('Hapus produk?'),
              content: Text('"${p.name}" akan dihapus permanen.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
                TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Hapus', style: TextStyle(color: Colors.red))),
              ],
            ));
    if (ok != true) return;
    await _run(() async {
      try {
        final r = await sb.from('products').delete().eq('id', p.id).select();
        if (mounted) toast(context, r.isEmpty ? 'Gagal menghapus (cek izin/RLS di Supabase)' : 'Produk dihapus');
      } on PostgrestException catch (e) {
        if (e.code == '23503') {
          if (mounted) toast(context, 'Produk sudah pernah dipesan, nonaktifkan saja');
        } else {
          rethrow;
        }
      }
    });
  }

  Widget _thumb(Product p) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 56,
          height: 56,
          child: (p.image == null || p.image!.isEmpty)
              ? Container(color: bg, child: const Icon(Icons.inventory_2_outlined, color: muted))
              : Image.network(p.image!, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(color: bg, child: const Icon(Icons.broken_image_outlined, color: muted))),
        ),
      );

  Widget _productRow(Product p) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Material(
          color: Colors.white,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: line)),
          child: InkWell(
            onTap: () => _form(p),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
              child: Row(children: [
                _thumb(p),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('${p.hasVariants ? 'Mulai ' : ''}${rp(p.price)}  •  Stok ${p.stock == null ? 'tak terbatas' : nf(p.stock!)}',
                        style: const TextStyle(color: muted, fontSize: 12.5)),
                    Text('${p.variants.length} jenis  •  ${p.images.length} gambar', style: const TextStyle(color: muted, fontSize: 12)),
                    if (_isLow(p)) const Text('Stok di bawah min. order', style: TextStyle(color: Color(0xFFEA580C), fontSize: 12, fontWeight: FontWeight.w600)),
                    if (!p.active) const Text('Nonaktif', style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w600)),
                  ]),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'edit') {
                      _form(p);
                    } else if (v == 'stock') {
                      _addStock(p);
                    } else if (v == 'toggle') {
                      // ... (tetap)
                    } else {
                      _delete(p);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'stock', enabled: p.stock != null, child: const Text('Tambah stok')),
                    PopupMenuItem(value: 'toggle', child: Text(p.active ? 'Nonaktifkan' : 'Aktifkan')),
                    const PopupMenuItem(value: 'del', child: Text('Hapus', style: TextStyle(color: Colors.red))),
                  ],
                ),
              ]),
            ),
          ),
        ),
      );

  Widget _catDrop() => FutureBuilder<List>(
        future: cats,
        builder: (_, s) {
          final l = s.data ?? [];
          return Container(
            width: 150,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: cardDeco(10),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int?>(
                value: cat,
                isExpanded: true,
                style: const TextStyle(fontSize: 13, color: ink),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('Semua kategori', overflow: TextOverflow.ellipsis)),
                  for (final c in l) DropdownMenuItem<int?>(value: c['id'] as int, child: Text(c['name'], overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => cat = v),
              ),
            ),
          );
        },
      );

  Widget _products() => _section(
        'Cari produk',
        const [('all', 'Semua'), ('active', 'Aktif'), ('inactive', 'Nonaktif'), ('low', 'Stok menipis'), ('out', 'Stok habis')],
        (l) {
          final rows = l.map((e) => Product.fromMap(e)).where((p) {
            if (flt == 'active' && !p.active) return false;
            if (flt == 'inactive' && p.active) return false;
            if (flt == 'low' && !_isLow(p)) return false;
            if (flt == 'out' && p.ready) return false;
            if (cat != null && p.categoryId != cat) return false;
            return q.isEmpty || p.name.toLowerCase().contains(q);
          }).toList();
          return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
            Row(children: [
              Expanded(child: Text('${rows.length} produk', style: const TextStyle(color: muted))),
              FilledButton.icon(style: _btn, onPressed: () => _form(), icon: const Icon(Icons.add, size: 18), label: const Text('Tambah Produk')),
            ]),
            if (rows.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('Tidak ada produk', style: TextStyle(color: muted)))),
            for (final p in rows) _productRow(p),
          ]);
        },
        extra: _catDrop(),
      );

  // ================= PENGGUNA (hanya lihat + tambah admin) =================
  Future<void> _addAdmin() async {
    final d = await showDialog<Map<String, String>>(context: context, builder: (_) => const _AdminForm());
    if (d == null) return;

    final messenger = ScaffoldMessenger.of(context);
    void say(String m) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));

    final adminId = sb.auth.currentUser?.id;
    final adminRefresh = sb.auth.currentSession?.refreshToken;
    authLocked = true;

    final tmp = SupabaseClient(
      supabaseUrl.replaceAll(RegExp(r'/+$'), ''),
      supabaseAnonKey,
      authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
    );
    try {
      final res = await tmp.auth.signUp(
        email: d['email']!,
        password: d['password']!,
        data: {'full_name': d['name'], 'company': 'PoPack'},
      );
      final uid = res.user?.id;
      if (uid == null) throw const AuthException('Gagal membuat akun');

      await Future.delayed(const Duration(milliseconds: 800));
      if (adminRefresh != null && sb.auth.currentUser?.id != adminId) {
        await sb.auth.setSession(adminRefresh); // kembalikan sesi admin
      }

      // Coba beberapa kali, lalu cek apakah perannya benar-benar sudah admin
      var ok = false;
      String? lastErr;
      for (var k = 0; k < 5 && !ok; k++) {
        try {
          await sb.rpc('admin_set_role', params: {'uid': uid, 'new_role': 'admin'});
        } on PostgrestException catch (e) {
          lastErr = e.message;
        }
        await Future.delayed(const Duration(milliseconds: 700));
        final p = await sb.from('profiles').select('role').eq('id', uid).maybeSingle();
        ok = p?['role'] == 'admin';
      }
      say(ok
          ? 'Akun admin dibuat'
          : 'Akun dibuat, tetapi gagal dijadikan admin${lastErr != null ? ': $lastErr' : ''}');
    } on AuthException catch (e) {
      say(e.message);
    } on PostgrestException catch (e) {
      say(e.message);
    } catch (e) {
      say('Gagal: $e');
    } finally {
      await tmp.dispose();
      authLocked = false;
    }
    if (mounted) _reload();
  }

  Widget _users() => _section(
        'Cari nama / perusahaan',
        const [('all', 'Semua'), ('admin', 'Admin'), ('customer', 'Pelanggan')],
        (l) {
          final me = sb.auth.currentUser?.id;
          final rows = l.where((u) {
            final isAdmin = u['role'] == 'admin';
            if (flt == 'admin' && !isAdmin) return false;
            if (flt == 'customer' && isAdmin) return false;
            return q.isEmpty || '${u['full_name'] ?? ''} ${u['company'] ?? ''} ${u['phone'] ?? ''}'.toLowerCase().contains(q);
          }).toList();
          return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
            Row(children: [
              Expanded(child: Text('${rows.length} pengguna', style: const TextStyle(color: muted))),
              FilledButton.icon(style: _btn, onPressed: _addAdmin, icon: const Icon(Icons.person_add_alt, size: 18), label: const Text('Tambah Admin')),
            ]),
            if (rows.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('Tidak ada pengguna', style: TextStyle(color: muted)))),
            for (final u in rows) _userRow(u, me),
          ]);
        },
      );

  Widget _userRow(Map u, String? me) {
    final isAdmin = u['role'] == 'admin';
    final name = ((u['full_name'] ?? '') as String).trim();
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: cardDeco(10),
      child: ListTile(
        leading: CircleAvatar(
            backgroundColor: isAdmin ? const Color(0x1A1F3A8A) : const Color(0x1AE53935),
            child: Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: TextStyle(color: isAdmin ? navy : brand, fontWeight: FontWeight.w800))),
        title: Text('${name.isEmpty ? '-' : name}${u['id'] == me ? ' (Anda)' : ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${u['company'] ?? '-'} • ${u['phone'] ?? '-'}'),
        trailing: isAdmin
            ? _pill('Admin', navy)
            : (u['status'] == 'approved' ? _pill('Pelanggan', muted) : _pill('Diblokir', Colors.red)),
      ),
    );
  }

  // ================= LAPORAN (tabel sederhana) =================
  Widget _hdr(String t, {int flex = 1, bool right = false}) =>
      Expanded(flex: flex, child: Text(t, textAlign: right ? TextAlign.right : TextAlign.left, style: const TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w700)));

  Widget _kpi(String label, String value, {int flex = 1}) => Expanded(
        flex: flex,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: muted, fontSize: 12.5)),
          const SizedBox(height: 4),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: ink))),
        ]),
      );

  Widget _report() => _section(
        'Cari produk',
        const [('all', 'Semua waktu'), ('today', 'Hari ini'), ('7d', '7 hari'), ('30d', '30 hari')],
        (l) {
          final now = DateTime.now();
          final from = switch (flt) {
            'today' => DateTime(now.year, now.month, now.day),
            '7d' => now.subtract(const Duration(days: 7)),
            '30d' => now.subtract(const Duration(days: 30)),
            _ => null,
          };
          final agg = <String, List<num>>{};
          var orderCount = 0;
          for (final o in l) {
            if (from != null && DateTime.parse(o['created_at']).toLocal().isBefore(from)) continue;
            orderCount++;
            for (final i in (o['order_items'] as List)) {
              final a = agg.putIfAbsent('${i['products']?['name'] ?? '-'}', () => <num>[0, 0]);
              a[0] += i['qty'] as num;
              a[1] += (i['qty'] as num) * (i['price'] as num);
            }
          }
          num totalAmt = 0, totalQty = 0;
          for (final a in agg.values) {
            totalQty += a[0];
            totalAmt += a[1];
          }
          final rows = agg.entries.where((e) => q.isEmpty || e.key.toLowerCase().contains(q)).toList()
            ..sort((a, b) => b.value[1].compareTo(a.value[1]));
          final maxAmt = rows.isEmpty || rows.first.value[1] == 0 ? 1 : rows.first.value[1];
          return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: cardDeco(12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _kpi('Pendapatan', rp(totalAmt), flex: 3),
                _kpi('Item terjual', nf(totalQty), flex: 2),
                _kpi('Pesanan', '$orderCount', flex: 2),
              ]),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: cardDeco(12),
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                Container(
                  color: bg,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(children: [_hdr('PRODUK', flex: 5), _hdr('TERJUAL', flex: 2, right: true), _hdr('PENDAPATAN', flex: 4, right: true)]),
                ),
                if (rows.isEmpty) const Padding(padding: EdgeInsets.all(28), child: Text('Belum ada data penjualan', style: TextStyle(color: muted))),
                for (var k = 0; k < rows.length; k++) ...[
                  if (k > 0) const Divider(height: 1, color: line),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        flex: 5,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(rows[k].key, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(value: (rows[k].value[1] / maxAmt).toDouble(), minHeight: 4, backgroundColor: bg, color: brand),
                            ),
                          ]),
                        ),
                      ),
                      Expanded(flex: 2, child: Text(nf(rows[k].value[0]), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13.5))),
                      Expanded(
                        flex: 4,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(rp(rows[k].value[1]), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ]),
                  ),
                ],
              ]),
            ),
          ]);
        },
      );

  static const _titles = {'orders': 'Pesanan', 'products': 'Produk', 'users': 'Pengguna', 'report': 'Laporan'};

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(_titles[widget.section] ?? 'Admin'), centerTitle: false, automaticallyImplyLeading: false),
        body: _wrap(switch (widget.section) {
          'products' => _products(),
          'users' => _users(),
          'report' => _report(),
          _ => _orders(),
        }),
      );
}

// ===== Form tambah akun admin =====
class _AdminForm extends StatefulWidget {
  const _AdminForm();
  @override
  State<_AdminForm> createState() => _AdminFormState();
}

class _AdminFormState extends State<_AdminForm> {
  final key = GlobalKey<FormState>();
  final name = TextEditingController(), email = TextEditingController(), pass = TextEditingController();

  InputDecoration _d(String l) => InputDecoration(labelText: l, isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)));

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Tambah Akun Admin'),
        content: SizedBox(
          width: 400,
          child: Form(
            key: key,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(controller: name, decoration: _d('Nama lengkap'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null),
              const SizedBox(height: 12),
              TextFormField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: _d('Email'),
                  validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v?.trim() ?? '') ? null : 'Format email tidak valid'),
              const SizedBox(height: 12),
              TextFormField(
                  controller: pass,
                  obscureText: true,
                  decoration: _d('Password (min. 8 karakter)'),
                  validator: (v) => (v == null || v.length < 8) ? 'Minimal 8 karakter' : null),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: brand),
            onPressed: () {
              if (!key.currentState!.validate()) return;
              Navigator.pop(context, {'name': name.text.trim(), 'email': email.text.trim(), 'password': pass.text});
            },
            child: const Text('Buat Admin'),
          ),
        ],
      );
}
