import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core.dart';
import '../widgets.dart';
import 'auth_page.dart';
import 'home_shell.dart';
import '../fx.dart';

class ProductDetailPage extends StatefulWidget {
  final Product p;
  const ProductDetailPage(this.p, {super.key});
  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  int vi = 0, page = 0, qty = 0;
  final pc = PageController();
  final qc = TextEditingController();
  final imgKey = GlobalKey();   

  Product get p => widget.p;
  Variant get v => p.variants[vi];
  int get step => Cart.stepOf(v);
  bool get canBuy => p.ready && (p.stock == null || p.stock! >= v.minOrder);

  @override
  void initState() {
    super.initState();
    _setQty(v.minOrder, rebuild: false);
  }

  @override
  void dispose() {
    pc.dispose();
    qc.dispose();
    super.dispose();
  }

  void _setQty(int n, {bool rebuild = true}) {
    if (n < v.minOrder) n = v.minOrder;
    if (p.stock != null && n > p.stock!) n = p.stock!;
    qty = n;
    qc.text = '$n';
    if (rebuild) setState(() {});
  }

  /// Ambil angka yang diketik user lalu sesuaikan dengan minimal order & stok
  void _commit() => _setQty(int.tryParse(qc.text.trim()) ?? v.minOrder);

  Future<void> _add({bool goCart = false}) async {
    _commit();
    if (!await requireLogin(context)) return;
    cart.add(p, v, qty);
    if (!mounted) return;
    if (goCart) {
      Navigator.popUntil(context, (r) => r.isFirst);
      HomeShell.tab.value = 2;
    } else {
      flyToCart(imgKey.currentContext ?? context, imageUrl: p.image);
      toast(context, '${p.name}${p.hasVariants ? ' • ${v.name}' : ''} ditambahkan ke keranjang');
    }
  }

  Widget _pill(IconData i, String t, {Color? color}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(i, size: 16, color: color ?? navy),
          const SizedBox(width: 6),
          Text(t, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ]),
      );

  Widget _ph(IconData i, double s) => Center(child: Icon(i, size: s, color: const Color(0xFF9CA3AF)));

  Widget _navBtn(IconData i, VoidCallback onTap) => Material(
        color: Colors.white.withAlpha(230),
        shape: const CircleBorder(side: BorderSide(color: line)),
        child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: Padding(padding: const EdgeInsets.all(6), child: Icon(i, size: 22, color: ink))),
      );

  // Carousel gambar: bisa digeser (sentuh / mouse), ada panah & titik penunjuk
  Widget _image() {
    final imgs = p.images;
    return AspectRatio(
      key: imgKey,
      aspectRatio: 1,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(16), border: Border.all(color: line)),
        child: imgs.isEmpty
            ? _ph(Icons.inventory_2_outlined, 80)
            : Stack(children: [
                ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad, PointerDeviceKind.stylus},
                  ),
                  child: PageView.builder(
                    controller: pc,
                    itemCount: imgs.length,
                    onPageChanged: (i) => setState(() => page = i),
                    itemBuilder: (_, i) => Image.network(imgs[i], fit: BoxFit.contain, errorBuilder: (_, __, ___) => _ph(Icons.broken_image_outlined, 60)),
                  ),
                ),
                if (imgs.length > 1) ...[
                  if (page > 0)
                    Positioned(
                        left: 8,
                        top: 0,
                        bottom: 0,
                        child: Center(child: _navBtn(Icons.chevron_left, () => pc.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut)))),
                  if (page < imgs.length - 1)
                    Positioned(
                        right: 8,
                        top: 0,
                        bottom: 0,
                        child: Center(child: _navBtn(Icons.chevron_right, () => pc.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut)))),
                  Positioned(
                    bottom: 10,
                    left: 0,
                    right: 0,
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      for (var k = 0; k < imgs.length; k++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: k == page ? 18 : 7,
                          height: 7,
                          decoration: BoxDecoration(color: k == page ? brand : const Color(0xFFD1D5DB), borderRadius: BorderRadius.circular(4)),
                        ),
                    ]),
                  ),
                ],
              ]),
      ),
    );
  }

  // Pilihan jenis (mis. Wrapped / Unwrapped), masing-masing punya harga & minimal order
  Widget _variantPicker() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 18),
        const Text('Pilih jenis', style: TextStyle(fontWeight: FontWeight.w700, color: muted)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < p.variants.length; i++)
            ChoiceChip(
              label: Text(p.variants[i].name),
              selected: vi == i,
              showCheckmark: false,
              onSelected: (_) {
                vi = i;
                _setQty(v.minOrder);
              },
              backgroundColor: Colors.white,
              selectedColor: brand,
              side: BorderSide(color: vi == i ? brand : line),
              labelStyle: TextStyle(color: vi == i ? Colors.white : ink, fontWeight: FontWeight.w600, fontSize: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
        ]),
      ]);

  Widget _qtyRow() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Text('Jumlah', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(width: 14),
          Container(
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20), border: Border.all(color: line)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(visualDensity: VisualDensity.compact, iconSize: 20, icon: const Icon(Icons.remove), onPressed: qty > v.minOrder ? () => _setQty(qty - step) : null),
              SizedBox(
                width: 76,
                child: TextField(
                  controller: qc,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  decoration: const InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 8)),
                  onChanged: (t) => setState(() => qty = int.tryParse(t) ?? 0),
                  onSubmitted: (_) => _commit(),
                  onTapOutside: (_) {
                    FocusScope.of(context).unfocus();
                    _commit();
                  },
                ),
              ),
              IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 20,
                  icon: const Icon(Icons.add),
                  onPressed: (p.stock == null || qty + step <= p.stock!) ? () => _setQty(qty + step) : null),
            ]),
          ),
          const Text('  pcs', style: TextStyle(color: muted)),
        ]),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Min. order ${nf(v.minOrder)} pcs', style: const TextStyle(color: muted, fontSize: 12.5)),
          Text(rp(v.priceFor(qty) * qty), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ]),
      ]);

  Widget _actions() => Row(children: [
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                side: const BorderSide(color: brand),
                foregroundColor: brand,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: canBuy ? () => _add(goCart: true) : null,
            child: const Text('Pesan Sekarang', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50), backgroundColor: brand, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: canBuy ? () => _add() : null,
            child: const Text('+ Keranjang', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ]);

  Widget _tierTable() {
    final t = v.tiers;
    if (t.isEmpty) return const SizedBox.shrink();
    int active = 0;
    for (var k = 0; k < t.length; k++) {
      if (qty >= t[k].minQty) active = k;
    }
    Widget cell(String s, {bool bold = false, Color? color}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(s, textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: color ?? ink)),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 18),
      const Text('Harga grosir', style: TextStyle(fontWeight: FontWeight.w700, color: muted)),
      const SizedBox(height: 8),
      Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: line)),
        child: Column(children: [
          Container(
            color: navy,
            child: Row(children: [
              cell('Jumlah beli', bold: true, color: Colors.white),
              cell('Harga / pcs', bold: true, color: Colors.white),
            ]),
          ),
          for (var k = 0; k < t.length; k++)
            Container(
              color: k == active ? const Color(0x1AE53935) : null,
              child: Row(children: [
                cell(k == t.length - 1 ? '≥ ${nf(t[k].minQty)}' : '${nf(t[k].minQty)} - ${nf(t[k + 1].minQty - 1)}', bold: k == active),
                cell(rp(t[k].price), bold: k == active, color: k == active ? brand : null),
              ]),
            ),
        ]),
      ),
    ]);
  }

  Widget _info(bool wide) => Container(
        padding: const EdgeInsets.all(20),
        decoration: cardDeco(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text(p.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.25, color: ink))),
            const SizedBox(width: 8),
            FavButton(p, size: 22),
          ]),
          const SizedBox(height: 8),
          Text(rp(v.priceFor(qty)), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: brand)),
          if (p.hasVariants) _variantPicker(),
          _tierTable(),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            p.ready
                ? _pill(Icons.check_circle_outline, p.stock == null ? 'Stok tersedia' : 'Stok ${nf(p.stock!)}', color: const Color(0xFF16A34A))
                : _pill(Icons.remove_circle_outline, 'Stok habis', color: Colors.red),
            _pill(Icons.scale_outlined, p.weight == null ? 'Berat -' : '${p.weight} gr'),
            _pill(Icons.shopping_bag_outlined, 'Min. order ${nf(v.minOrder)} pcs'),
          ]),
          if (canBuy) ...[
            const SizedBox(height: 18),
            const Divider(height: 1, color: line),
            const SizedBox(height: 14),
            _qtyRow(),
          ] else if (p.ready)
            const Padding(
              padding: EdgeInsets.only(top: 14),
              child: Text('Stok kurang dari minimal order jenis ini.', style: TextStyle(color: Colors.red, fontSize: 13)),
            ),
          if (wide) ...[const SizedBox(height: 18), _actions()],
          if (p.desc != null && p.desc!.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Divider(height: 1, color: line),
            const SizedBox(height: 16),
            const Text('Deskripsi', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(p.desc!, style: const TextStyle(color: muted, height: 1.55)),
          ],
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    return Scaffold(
      body: Column(children: [
        // Header tetap ada: keranjang selalu terlihat & bisa diklik
        const AppHeader(showBack: true, showCart: true),
        Expanded(
          child: SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: wide
                      ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          SizedBox(width: 420, child: _image()),
                          const SizedBox(width: 24),
                          Expanded(child: _info(true)),
                        ])
                      : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: _image())),
                          const SizedBox(height: 16),
                          _info(false),
                        ]),
                ),
              ),
            ),
          ),
        ),
      ]),
      bottomNavigationBar: wide
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: const BoxDecoration(color: Colors.white, boxShadow: cardShadow),
                child: _actions(),
              ),
            ),
    );
  }
}
