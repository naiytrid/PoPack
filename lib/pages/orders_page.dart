import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core.dart';
import '../widgets.dart';
import 'auth_page.dart';
import 'home_shell.dart';
import '../fx.dart';

// ---------------------------------------------------------------------
// Data & helper
// ---------------------------------------------------------------------

const _select = 'id,status,created_at,cancel_reason,'
    'order_items(qty,price,variant_name,products(name,image_url,product_images(url,position))),'
    'order_status_log(status,note,created_at)';

const _filters = <(String, String)>[
  ('all', 'Semua'),
  ('pending', 'Diajukan'),
  ('approved', 'Dipesan'),
  ('processing', 'Diproses'),
  ('completed', 'Selesai'),
  ('cancel', 'Batal / Ditolak'),
];

bool _match(String f, String s) => switch (f) {
      'all' => true,
      'cancel' => s == 'cancel_requested' || s == 'cancelled' || s == 'rejected',
      _ => s == f,
    };

/// Diajukan & Dipesan boleh dibatalkan. Diproses ke atas tidak.
bool _canCancel(String s) => s == 'pending' || s == 'approved';

String _code(Map o) {
  final id = '${o['id']}';
  return (id.length >= 8 ? id.substring(0, 8) : id).toUpperCase();
}

String _fmt(dynamic iso) {
  final d = DateTime.tryParse('$iso')?.toLocal();
  return d == null ? '' : d.toString().substring(0, 16);
}

num _totalOf(Map o) {
  num t = 0;
  for (final i in (o['order_items'] as List)) {
    t += (i['qty'] as num) * (i['price'] as num);
  }
  return t;
}

String _nameOf(Map i) {
  final name = '${i['products']?['name'] ?? '-'}';
  final vn = i['variant_name'];
  return (vn is String && vn.isNotEmpty && vn != name) ? '$name • $vn' : name;
}

String? _imgOf(Map i) {
  final p = i['products'];
  if (p is! Map) return null;
  final imgs = [...((p['product_images'] as List?) ?? const [])]
    ..sort((a, b) => ((a['position'] ?? 0) as num).compareTo((b['position'] ?? 0) as num));
  if (imgs.isNotEmpty) return '${imgs.first['url']}';
  final legacy = p['image_url'];
  return (legacy is String && legacy.isNotEmpty) ? legacy : null;
}

List<Map<String, dynamic>> _logOf(Map o) {
  final l = [for (final e in ((o['order_status_log'] as List?) ?? const [])) Map<String, dynamic>.from(e as Map)];
  l.sort((a, b) => '${a['created_at']}'.compareTo('${b['created_at']}'));
  return l;
}

IconData _icon(String s) => switch (s) {
      'pending' => Icons.hourglass_top_rounded,
      'approved' => Icons.assignment_turned_in_outlined,
      'processing' => Icons.autorenew_rounded,
      'completed' => Icons.verified_outlined,
      'cancel_requested' => Icons.undo_rounded,
      'cancelled' => Icons.cancel_outlined,
      _ => Icons.block_outlined,
    };

const _hint = {
  'pending': 'Menunggu pesanan Anda ditinjau. Pembatalan perlu persetujuan admin.',
  'approved': 'Pesanan sudah disetujui. Pembatalan perlu persetujuan admin.',
  'processing': 'Pesanan sedang diproses dan tidak bisa dibatalkan.',
  'completed': 'Pesanan sudah selesai.',
  'cancel_requested': 'Pengajuan pembatalan menunggu persetujuan admin.',
  'cancelled': 'Pesanan ini sudah dibatalkan.',
  'rejected': 'Pesanan ditolak oleh admin.',
};

const _stepLabel = {
  'pending': 'Pesanan diajukan',
  'approved': 'Pesanan dipesan (disetujui admin)',
  'processing': 'Pesanan diproses',
  'completed': 'Pesanan selesai',
  'cancel_requested': 'Pembatalan diajukan',
  'cancelled': 'Pesanan dibatalkan',
  'rejected': 'Pesanan ditolak',
  'cancel_rejected': 'Pembatalan ditolak admin',
};

// ---------------------------------------------------------------------
// Alasan pembatalan (konteks pemesanan grosir ke pabrik)
// ---------------------------------------------------------------------

const _reasons = [
  'Salah memilih produk atau jenis',
  'Jumlah pesanan perlu diubah',
  'Anggaran / persetujuan pembelian internal belum disetujui',
  'Kebutuhan produksi atau proyek ditunda / dibatalkan',
  'Spesifikasi (ukuran / bahan) tidak sesuai kebutuhan',
  'Pesanan ganda',
  'Lainnya',
];

Future<String?> askCancelReason(BuildContext context, {required bool direct}) => showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => _ReasonSheet(direct: direct),
    );

/// Pesanan Diajukan -> langsung batal. Pesanan Dipesan -> diajukan ke admin.
Future<bool> cancelOrder(BuildContext context, Map o) async {
  const direct = false;
  final reason = await askCancelReason(context, direct: direct);
  if (reason == null || !context.mounted) return false;
  final ok = await confirmAction(
    context,
    title: direct ? 'Yakin batalkan pesanan?' : 'Yakin ajukan pembatalan?',
    message: direct ? 'Pesanan langsung dibatalkan dan stok dikembalikan.' : 'Pengajuan dikirim ke admin untuk disetujui.',
    confirmText: direct ? 'Ya, batalkan' : 'Ya, ajukan',
    danger: true,
  );
  if (!ok || !context.mounted) return false;
  try {
    await sb.rpc('request_cancel', params: {'oid': o['id'], 'reason': reason});
    if (context.mounted) toast(context, direct ? 'Pesanan dibatalkan' : 'Pengajuan batal dikirim, menunggu persetujuan admin');
    return true;
  } on PostgrestException catch (e) {
    if (context.mounted) toast(context, e.message);
    return false;
  }
}

class _ReasonSheet extends StatefulWidget {
  final bool direct;
  const _ReasonSheet({required this.direct});
  @override
  State<_ReasonSheet> createState() => _ReasonSheetState();
}

class _ReasonSheetState extends State<_ReasonSheet> {
  String? sel;
  String? err;
  final other = TextEditingController();

  @override
  void dispose() {
    other.dispose();
    super.dispose();
  }

  void _submit() {
    if (sel == null) {
      setState(() => err = 'Pilih salah satu alasan');
      return;
    }
    if (sel == 'Lainnya') {
      final t = other.text.trim();
      if (t.length < 5) {
        setState(() => err = 'Tulis alasan Anda (minimal 5 karakter)');
        return;
      }
      Navigator.pop(context, 'Lainnya: $t');
      return;
    }
    Navigator.pop(context, sel);
  }

  Widget _tile(String r) {
    final on = sel == r;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() {
        sel = r;
        err = null;
      }),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
        child: Row(children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
            child: Icon(on ? Icons.radio_button_checked : Icons.radio_button_unchecked, key: ValueKey(on), color: on ? brand : muted, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(r, style: TextStyle(fontSize: 14, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: ink, height: 1.3))),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Text(widget.direct ? 'Batalkan pesanan?' : 'Ajukan pembatalan', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                widget.direct ? 'Pilih alasan pembatalan. Pesanan langsung dibatalkan.' : 'Pilih alasan pembatalan. Admin akan meninjau pengajuan Anda.',
                style: const TextStyle(color: muted, fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 10),
              for (final r in _reasons) _tile(r),
              if (sel == 'Lainnya')
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: TextField(
                    controller: other,
                    autofocus: true,
                    maxLines: 3,
                    maxLength: 200,
                    decoration: InputDecoration(
                      hintText: 'Tulis alasan Anda...',
                      filled: true,
                      fillColor: bg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    ),
                  ),
                ),
              if (err != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(err!, style: const TextStyle(color: Colors.red, fontSize: 12.5))),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)), child: const Text('Kembali'))),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Colors.red, minimumSize: const Size.fromHeight(48)),
                    onPressed: _submit,
                    child: Text(widget.direct ? 'Batalkan Pesanan' : 'Kirim Pengajuan'),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      );
}

// ---------------------------------------------------------------------
// Tab "Riwayat" (daftar pesanan + filter)
// ---------------------------------------------------------------------

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});
  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  late final StreamSubscription _sub;
  late Future<List> fut = _load();
  String flt = 'all';

  @override
  void initState() {
    super.initState();
    _sub = sb.auth.onAuthStateChange.listen((_) => _reload());
    sync.addListener(_reload); // otomatis ikut berubah saat admin mengubah status
  }

  @override
  void dispose() {
    sync.removeListener(_reload);
    _sub.cancel();
    super.dispose();
  }

  void _reload() {
    if (mounted) {
      setState(() {
        fut = _load();
      });
    }
  }

  Future<List> _load() async {
    final u = sb.auth.currentUser;
    if (u == null) return [];
    return await sb.from('orders').select(_select).eq('user_id', u.id).order('created_at', ascending: false);
  }

  Future<void> _open(Map o) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailPage('${o['id']}')));
    _reload();
  }

  Future<void> _cancel(Map o) async {
    await cancelOrder(context, o);
    _reload();
  }

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

  Widget _login() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: cardShadow),
              child: const Icon(Icons.receipt_long_outlined, size: 52, color: brand)),
          const SizedBox(height: 16),
          const Text('Masuk untuk melihat riwayat pesanan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: brand, minimumSize: const Size(220, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AuthPage())),
            child: const Text('Masuk / Daftar'),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final logged = sb.auth.currentUser != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Riwayat Pesanan'), centerTitle: false, automaticallyImplyLeading: false),
      body: !logged
          ? _login()
          : FutureBuilder<List>(
              future: fut,
              builder: (_, s) {
                if (s.hasError) return Center(child: Text('Gagal memuat: ${s.error}'));
                if (!s.hasData) return const Center(child: CircularProgressIndicator());
                final all = s.data!;
                final rows = all.where((o) => _match(flt, o['status'])).toList();
                int cnt(String f) => all.where((o) => _match(f, o['status'])).length;
                return Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(children: [
                      SizedBox(
                        height: 54,
                        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(12, 10, 12, 8), children: [
                          for (final f in _filters)
                            _chip(f.$1 != 'all' && cnt(f.$1) > 0 ? '${f.$2} (${cnt(f.$1)})' : f.$2, flt == f.$1, () => setState(() => flt = f.$1)),
                        ]),
                      ),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: () async {
                            _reload();
                            await fut;
                          },
                          child: rows.isEmpty
                              ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
                                  const SizedBox(height: 60),
                                  EmptyState(Icons.receipt_long_outlined, flt == 'all' ? 'Belum ada pesanan' : 'Tidak ada pesanan di status ini',
                                      sub: flt == 'all' ? 'Pesanan Anda akan muncul di sini' : null),
                                  if (flt == 'all')
                                    Center(
                                      child: OutlinedButton(
                                        style: OutlinedButton.styleFrom(foregroundColor: brand, side: const BorderSide(color: brand)),
                                        onPressed: () => HomeShell.tab.value = 1,
                                        child: const Text('Lihat Produk'),
                                      ),
                                    ),
                                ])
                              : ListView.builder(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.only(bottom: 24),
                                  itemCount: rows.length,
                                  itemBuilder: (_, i) => FadeSlideInTile(
                                    index: i,
                                    child: _OrderTile(o: rows[i], onOpen: () => _open(rows[i]), onCancel: () => _cancel(rows[i])),
                                  ),
                                ),
                        ),
                      ),
                    ]),
                  ),
                );
              },
            ),
    );
  }
}

/// Muncul pelan saat daftar dibuka.
class FadeSlideInTile extends StatelessWidget {
  final Widget child;
  final int index;
  const FadeSlideInTile({super.key, required this.child, required this.index});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: Duration(milliseconds: 280 + (index % 6) * 50),
        curve: Curves.easeOutCubic,
        builder: (_, v, ch) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, (1 - v) * 16), child: ch)),
        child: child,
      );
}

class _Thumb extends StatelessWidget {
  final String? url;
  final double size;
  const _Thumb(this.url, this.size);
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: size,
          height: size,
          color: const Color(0xFFF3F4F6),
          child: (url == null || url!.isEmpty)
              ? const Icon(Icons.inventory_2_outlined, color: Color(0xFF9CA3AF))
              : Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: Color(0xFF9CA3AF))),
        ),
      );
}

class _OrderTile extends StatelessWidget {
  final Map o;
  final VoidCallback onOpen, onCancel;
  const _OrderTile({required this.o, required this.onOpen, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final items = (o['order_items'] as List);
    final s = o['status'] as String;
    final c = statusColor(s);
    final first = items.isEmpty ? null : items.first as Map;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      clipBehavior: Clip.antiAlias,
      decoration: cardDeco(14),
      child: Material(
        color: Colors.white,
        child: InkWell(
          onTap: onOpen,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(color: c.withAlpha(28), borderRadius: BorderRadius.circular(10)),
                  child: Icon(_icon(s), size: 18, color: c),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Pesanan #${_code(o)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                    Text(_fmt(o['created_at']), style: const TextStyle(color: muted, fontSize: 12)),
                  ]),
                ),
                StatusPill(s),
              ]),
            ),
            const Divider(height: 1, color: line),
            if (first != null)
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _Thumb(_imgOf(first), 64),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_nameOf(first), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, height: 1.3)),
                      const SizedBox(height: 4),
                      Text('${nf(first['qty'] as num)} × ${rp(first['price'] as num)}', style: const TextStyle(color: muted, fontSize: 12.5)),
                      if (items.length > 1)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('+${items.length - 1} produk lainnya', style: const TextStyle(color: navy, fontSize: 12.5, fontWeight: FontWeight.w600)),
                        ),
                    ]),
                  ),
                ]),
              ),
            Container(
              color: bg,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Total (${items.length} produk)', style: const TextStyle(color: muted, fontSize: 13)),
                Text(rp(_totalOf(o)), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (_canCancel(s))
                  TextButton(onPressed: onCancel, child: const Text('Ajukan Batal', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700))),
                TextButton(onPressed: onOpen, child: const Text('Lihat Detail', style: TextStyle(color: brand, fontWeight: FontWeight.w700))),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Halaman detail pesanan (lini masa + tombol batal)
// ---------------------------------------------------------------------

class OrderDetailPage extends StatefulWidget {
  final String id;
  const OrderDetailPage(this.id, {super.key});
  @override
  State<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends State<OrderDetailPage> {
  late Future<Map<String, dynamic>> fut = _load();

  Future<Map<String, dynamic>> _load() async => await sb.from('orders').select(_select).eq('id', widget.id).single();

  void _reload() {
    if (mounted) {
      setState(() {
        fut = _load();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    sync.addListener(_reload);
  }

  @override
  void dispose() {
    sync.removeListener(_reload);
    super.dispose();
  }

  Widget _card(String title, Widget child) => Container(
        margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        padding: const EdgeInsets.all(16),
        decoration: cardDeco(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 12),
          child,
        ]),
      );

  Widget _banner(Map o) {
    final s = o['status'] as String;
    final c = statusColor(s);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: c.withAlpha(22), borderRadius: BorderRadius.circular(14), border: Border.all(color: c.withAlpha(70))),
      child: Row(children: [
        Icon(_icon(s), color: c, size: 30),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(statusLabel[s] ?? s, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 2),
            Text(_hint[s] ?? '', style: const TextStyle(color: ink, fontSize: 13, height: 1.35)),
            const SizedBox(height: 6),
            Text('#${_code(o)}  •  ${_fmt(o['created_at'])}', style: const TextStyle(color: muted, fontSize: 12)),
          ]),
        ),
      ]),
    );
  }

  Widget _items(Map o) {
    final items = o['order_items'] as List;
    return _card(
      'Produk dipesan',
      Column(children: [
        for (var k = 0; k < items.length; k++) ...[
          if (k > 0) const Divider(height: 20, color: line),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _Thumb(_imgOf(items[k] as Map), 56),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_nameOf(items[k] as Map), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, height: 1.3)),
                const SizedBox(height: 3),
                Text('${nf(items[k]['qty'] as num)} × ${rp(items[k]['price'] as num)}', style: const TextStyle(color: muted, fontSize: 12.5)),
              ]),
            ),
            const SizedBox(width: 8),
            Text(rp((items[k]['qty'] as num) * (items[k]['price'] as num)), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
          ]),
        ],
        const Divider(height: 24, color: line),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Total', style: TextStyle(fontWeight: FontWeight.w700)),
          Text(rp(_totalOf(o)), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: brand)),
        ]),
      ]),
    );
  }

  Widget _step(Map e, {required bool last}) {
    final s = '${e['status']}';
    final c = last ? (s == 'cancel_rejected' ? const Color(0xFFEA580C) : statusColor(s)) : muted;
    final note = '${e['note'] ?? ''}';
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 22,
          child: Column(children: [
            Container(width: 12, height: 12, margin: const EdgeInsets.only(top: 4), decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            if (!last) Expanded(child: Container(width: 2, color: line)),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: last ? 0 : 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_stepLabel[s] ?? s, style: TextStyle(fontWeight: last ? FontWeight.w800 : FontWeight.w600, color: last ? ink : muted, fontSize: 13.5)),
              if (note.isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 2), child: Text('Alasan: $note', style: const TextStyle(color: muted, fontSize: 12.5, height: 1.35))),
              Text(_fmt(e['created_at']), style: const TextStyle(color: muted, fontSize: 12)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _timeline(Map o) {
    var log = _logOf(o);
    if (log.isEmpty) log = [{'status': o['status'], 'created_at': o['created_at']}];
    return _card('Riwayat status', Column(children: [for (var k = 0; k < log.length; k++) _step(log[k], last: k == log.length - 1)]));
  }

  Widget _rejectedNote(Map o) {
    final log = _logOf(o);
    if (log.isEmpty || log.last['status'] != 'cancel_rejected') return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0x1AEA580C), borderRadius: BorderRadius.circular(14)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.info_outline, color: Color(0xFFEA580C), size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Pengajuan pembatalan Anda ditolak admin. Pesanan tetap berjalan dengan status ${statusLabel['${o['status']}'] ?? ''}.',
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
        future: fut,
        builder: (_, s) {
          final o = s.data;
          final status = o?['status'] as String?;
          return Scaffold(
            appBar: AppBar(title: const Text('Detail Pesanan'), centerTitle: false),
            body: s.hasError
                ? Center(child: Text('Gagal memuat: ${s.error}'))
                : o == null
                    ? const Center(child: CircularProgressIndicator())
                    : Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 640),
                          child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
                            _banner(o),
                            _rejectedNote(o),     // <-- tambah baris ini
                            if ('${o['cancel_reason'] ?? ''}'.isNotEmpty && (status == 'cancel_requested' || status == 'cancelled'))
                              _card('Alasan pembatalan', Text('${o['cancel_reason']}', style: const TextStyle(height: 1.4, fontSize: 13.5))),
                            _items(o),
                            _timeline(o),
                          ]),
                        ),
                      ),
            bottomNavigationBar: (status != null && _canCancel(status))
                ? SafeArea(
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: const BoxDecoration(color: Colors.white, boxShadow: cardShadow),
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          await cancelOrder(context, o!);
                          _reload();
                        },
                        child: const Text('Ajukan Pembatalan', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  )
                : null,
          );
        },
      );
}