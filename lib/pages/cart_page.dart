import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core.dart';
import 'auth_page.dart';
import 'home_shell.dart';
import '../fx.dart';

class CartPage extends StatefulWidget {
  const CartPage({super.key});
  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  bool busy = false;

  Future<void> send() async {
    final ok = await confirmAction(
      context,
      title: 'Yakin kirim pesanan?',
      message: 'Stok langsung dikurangi untuk pesanan ini. Pesanan masih bisa dibatalkan sebelum diproses.',
      confirmText: 'Kirim',
    );
    if (!ok || !mounted) return;
    setState(() => busy = true);
    try {
      await sb.rpc('place_order', params: {
        'items': cart.items.values
            .map((i) => {'product_id': i.p.id, 'variant_id': i.v.id.isEmpty ? null : i.v.id, 'qty': i.qty})
            .toList(),
      });
      cart.clear();
      if (mounted) {
        toast(context, 'Pesanan terkirim, menunggu persetujuan admin');
        HomeShell.tab.value = 3;
      }
    } on PostgrestException catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _editQty(CartItem i) async {
    final c = TextEditingController(text: '${i.qty}');
    final n = await showDialog<int>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Ubah jumlah'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(helperText: 'Minimal ${nf(i.v.minOrder)} pcs', suffixText: 'pcs'),
          onSubmitted: (_) => Navigator.pop(d, int.tryParse(c.text)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Batal')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: brand),
              onPressed: () => Navigator.pop(d, int.tryParse(c.text)),
              child: const Text('Simpan')),
        ],
      ),
    );
    c.dispose();
    if (n != null) cart.setQty(i, n);
  }

  Widget _empty(IconData i, String t, {String? sub, String? btn, VoidCallback? onTap}) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: cardShadow),
              child: Icon(i, size: 52, color: brand)),
          const SizedBox(height: 16),
          Text(t, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          if (sub != null) ...[
            const SizedBox(height: 4),
            Text(sub, style: const TextStyle(color: muted, fontSize: 13)),
          ],
          if (btn != null) ...[
            const SizedBox(height: 18),
            FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: brand, minimumSize: const Size(220, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: onTap,
                child: Text(btn)),
          ],
        ]),
      );

    Widget _stepper(CartItem i) => Container(
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20), border: Border.all(color: line)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(visualDensity: VisualDensity.compact, iconSize: 18, icon: const Icon(Icons.remove), onPressed: i.qty > i.v.minOrder ? () => cart.dec(i) : null),
          InkWell(
            onTap: () => _editQty(i),
            child: SizedBox(
              width: 58,
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (c, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: c)),
                  child: Text(nf(i.qty), key: ValueKey(i.qty), style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ),
          IconButton(visualDensity: VisualDensity.compact, iconSize: 18, icon: const Icon(Icons.add), onPressed: () => cart.inc(i)),
        ]),
      );

  Widget _item(CartItem i) => Dismissible(
        key: ValueKey(i.key),
        direction: DismissDirection.endToStart,
        onDismissed: (_) => cart.remove(i.key),
        background: Container(
            margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(color: Colors.red.shade400, borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.delete_outline, color: Colors.white)),
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          padding: const EdgeInsets.all(12),
          decoration: cardDeco(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 82,
                height: 82,
                color: const Color(0xFFF3F4F6),
                child: (i.p.image == null || i.p.image!.isEmpty)
                    ? const Icon(Icons.inventory_2_outlined, color: Color(0xFF9CA3AF))
                    : Image.network(i.p.image!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: Color(0xFF9CA3AF))),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Text(i.p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.3))),
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => cart.remove(i.key),
                    child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.close, size: 18, color: muted)),
                  ),
                ]),
                if (i.p.hasVariants)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('Jenis: ${i.v.name}', style: const TextStyle(color: navy, fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ),
                const SizedBox(height: 2),
                Text('${rp(i.v.priceFor(i.qty))} / pcs  •  Min. ${nf(i.v.minOrder)}', style: const TextStyle(color: muted, fontSize: 12.5)),
                const SizedBox(height: 8),
                Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 6, children: [
                  _stepper(i),
                  Text(rp(i.v.priceFor(i.qty) * i.qty), style: const TextStyle(color: brand, fontWeight: FontWeight.w800, fontSize: 15)),
                ]),
              ]),
            ),
          ]),
        ),
      );

  Widget _sendBtn() => FilledButton(
        style: FilledButton.styleFrom(
            backgroundColor: brand, minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        onPressed: busy ? null : send,
        child: busy
            ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
            : const Text('Kirim Pesanan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      );

  Widget _row(String l, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(l, style: const TextStyle(color: muted, fontSize: 13.5)),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
        ]),
      );

  // Ringkasan untuk layar lebar (kartu di sisi kanan)
  Widget _summaryCard() => Container(
        padding: const EdgeInsets.all(18),
        decoration: cardDeco(14),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Ringkasan pesanan', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 14),
          _row('Jenis produk', '${cart.count}'),
          _row('Jumlah barang', '${nf(cart.pcs)} pcs'),
          const Divider(height: 24, color: line),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Total', style: TextStyle(fontWeight: FontWeight.w700)),
            Text(rp(cart.total), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: brand)),
          ]),
          const SizedBox(height: 16),
          _sendBtn(),
          const SizedBox(height: 12),
          const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline, size: 15, color: muted),
            SizedBox(width: 6),
            Expanded(child: Text('Pesanan akan ditinjau admin sebelum diproses.', style: TextStyle(color: muted, fontSize: 12, height: 1.4))),
          ]),
        ]),
      );

  // Bar bawah untuk HP
  Widget _bottomBar() => Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24)), boxShadow: cardShadow),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Total (${nf(cart.pcs)} pcs)', style: const TextStyle(color: muted)),
              Text(rp(cart.total), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: brand)),
            ]),
            const SizedBox(height: 12),
            _sendBtn(),
          ]),
        ),
      );

  Widget _list() => ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
        for (final i in cart.items.values) _item(i),
        const Padding(padding: EdgeInsets.all(12), child: Center(child: Text('Geser ke kiri untuk menghapus • ketuk angka untuk mengetik jumlah', style: TextStyle(color: muted, fontSize: 12), textAlign: TextAlign.center))),
      ]);

  @override
  Widget build(BuildContext context) => StreamBuilder(
        stream: sb.auth.onAuthStateChange,
        builder: (_, __) {
          final logged = sb.auth.currentUser != null;
          return Scaffold(
            appBar: AppBar(title: const Text('Keranjang')),
            body: !logged
                ? _empty(Icons.lock_outline, 'Masuk dulu untuk mulai memesan',
                    btn: 'Masuk / Daftar', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AuthPage())))
                : ListenableBuilder(
                    listenable: cart,
                    builder: (_, __) {
                      if (cart.items.isEmpty) {
                        return _empty(Icons.shopping_basket_outlined, 'Keranjang masih kosong',
                            sub: 'Tambahkan produk kemasan yang Anda butuhkan', btn: 'Lihat Produk', onTap: () => HomeShell.tab.value = 1);
                      }
                      final wide = MediaQuery.sizeOf(context).width >= 860;
                      if (wide) {
                        return Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1100),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Expanded(child: _list()),
                              SizedBox(width: 340, child: Padding(padding: const EdgeInsets.fromLTRB(0, 14, 16, 0), child: _summaryCard())),
                            ]),
                          ),
                        );
                      }
                      return Column(children: [Expanded(child: _list()), _bottomBar()]);
                    },
                  ),
          );
        },
      );
}
