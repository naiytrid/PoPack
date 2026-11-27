import 'package:flutter/material.dart';
import '../core.dart';
import '../widgets.dart';
import 'home_shell.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  late Future<Map<String, List>> f = _load();

  void _onSync() {
    if (mounted) setState(() => f = _load()); // auto reload
  }

  @override
  void initState() {
    super.initState();
    sync.addListener(_onSync);
  }

  @override
  void dispose() {
    sync.removeListener(_onSync);
    super.dispose();
  }

  Future<Map<String, List>> _load() async {
    final List orders = await sb
        .from('orders')
        .select('id,status,created_at,profiles(full_name,company),order_items(qty,price,products(name))')
        .order('created_at', ascending: false);
    final List prods = await sb
      .from('products')
      .select('id,name,stock,is_active,product_variants(name,min_order)');
    final List users = await sb.from('profiles').select('id,role');
    return {'orders': orders, 'products': prods, 'users': users};
  }

  num _total(Map o) {
    num t = 0;
    for (final i in (o['order_items'] as List)) {
      t += (i['qty'] as num) * (i['price'] as num);
    }
    return t;
  }

  Widget _stat(double w, IconData icon, String label, String value, int goTo, {bool accent = false}) => SizedBox(
        width: w,
        child: Material(
          color: Colors.white,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: line)),
          child: InkWell(
            onTap: () => HomeShell.adminTab.value = goTo,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: accent ? const Color(0x1AE53935) : const Color(0x141F3A8A), borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, size: 20, color: accent ? brand : navy),
                ),
                const SizedBox(height: 14),
                Text(label, style: const TextStyle(color: muted, fontSize: 13)),
                const SizedBox(height: 2),
                Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: accent ? brand : ink)),
              ]),
            ),
          ),
        ),
      );

  Widget _panel(String title, Widget child, {String? action, int? goTo}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: cardDeco(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5))),
            if (action != null)
              GestureDetector(onTap: () => HomeShell.adminTab.value = goTo!, child: Text(action, style: const TextStyle(color: brand, fontWeight: FontWeight.w600, fontSize: 13))),
          ]),
          const SizedBox(height: 10),
          child,
        ]),
      );

  Widget _recent(List orders) {
    if (orders.isEmpty) return const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: Text('Belum ada pesanan', style: TextStyle(color: muted))));
    return Column(children: [
      for (var k = 0; k < orders.length && k < 5; k++) ...[
        if (k > 0) const Divider(height: 1, color: line),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${orders[k]['profiles']?['full_name'] ?? '-'} • ${orders[k]['profiles']?['company'] ?? '-'}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                const SizedBox(height: 2),
                Text(DateTime.parse(orders[k]['created_at']).toLocal().toString().substring(0, 16), style: const TextStyle(color: muted, fontSize: 12)),
              ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              StatusPill(orders[k]['status']),
              const SizedBox(height: 4),
              Text(rp(_total(orders[k])), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ]),
          ]),
        ),
      ],
    ]);
  }

  Widget _low(List low) {
    if (low.isEmpty) return const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: Text('Semua stok aman', style: TextStyle(color: muted))));
    return Column(children: [
      for (var k = 0; k < low.length; k++) ...[
        if (k > 0) const Divider(height: 1, color: line),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(low[k]['name'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5)),
                const SizedBox(height: 2),
                Text('Min. order ${nf(low[k]['min'])} pcs', style: const TextStyle(color: muted, fontSize: 12)),
              ]),
            ),
            Text(low[k]['stock'] == 0 ? 'Habis' : 'Sisa ${nf(low[k]['stock'])}',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: low[k]['stock'] == 0 ? Colors.red : const Color(0xFFEA580C))),
          ]),
        ),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Dashboard'), centerTitle: false, automaticallyImplyLeading: false),
        body: FutureBuilder<Map<String, List>>(
          future: f,
          builder: (_, s) {
            if (s.hasError) return Center(child: Text('${s.error}'));
            if (!s.hasData) return const Center(child: CircularProgressIndicator());
            final orders = s.data!['orders']!, prods = s.data!['products']!, users = s.data!['users']!;
            final todo = orders.where((o) => const ['pending', 'approved', 'cancel_requested'].contains(o['status'])).length;
            num revenue = 0;
            for (final o in orders) {
              if (const ['approved', 'processing', 'completed'].contains(o['status'])) revenue += _total(o);
            }
            final active = prods.where((p) => p['is_active'] == true).length;
            final customers = users.where((u) => u['role'] != 'admin').length;
            final low = <Map>[];
for (final p in prods) {
  if (p['is_active'] != true || p['stock'] == null) continue; // null = stok tak terbatas
  final stock = p['stock'] as num;
  final vars = (p['product_variants'] as List?) ?? const [];
    // minimal order terkecil dari semua varian
    num minOrder = 1;
    if (vars.isNotEmpty) {
      minOrder = vars.map((v) => (v['min_order'] as num?) ?? 1).reduce((a, b) => a < b ? a : b);
    }
    // stok kurang dari min. order terkecil => tidak ada varian yang bisa dibeli
    if (stock < minOrder) {
      low.add({'name': p['name'], 'stock': stock, 'min': minOrder});
    }
  }
  low.sort((a, b) => (a['stock'] as num).compareTo(b['stock'] as num));
            return RefreshIndicator(
              onRefresh: () async {
                setState(() => f = _load());
                await f;
              },
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: LayoutBuilder(builder: (_, c) {
                    final cols = c.maxWidth >= 700 ? 4 : 2;
                    final cw = (c.maxWidth - 32 - 12 * (cols - 1)) / cols;
                    final wide = c.maxWidth >= 800;
                    final recent = _panel('Pesanan terbaru', _recent(orders), action: 'Lihat semua', goTo: 1);
                    final lowP = _panel('Stok menipis', _low(low.take(6).toList()), action: 'Tambah stok', goTo: 2);
                    return ListView(padding: const EdgeInsets.all(16), children: [
                      Wrap(spacing: 12, runSpacing: 12, children: [
                        _stat(cw, Icons.pending_actions_outlined, 'Perlu tindakan', '$todo', 1, accent: todo > 0),
                        _stat(cw, Icons.payments_outlined, 'Total penjualan', rp(revenue), 4),
                        _stat(cw, Icons.inventory_2_outlined, 'Produk aktif', '$active', 2),
                        _stat(cw, Icons.people_outline, 'Pelanggan', '$customers', 3),
                      ]),
                      const SizedBox(height: 16),
                      if (wide)
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(flex: 3, child: recent),
                          const SizedBox(width: 16),
                          Expanded(flex: 2, child: lowP),
                        ])
                      else ...[recent, const SizedBox(height: 16), lowP],
                    ]);
                  }),
                ),
              ),
            );
          },
        ),
      );
}