import 'package:flutter/material.dart';
import 'core.dart';
import 'pages/auth_page.dart';
import 'pages/home_shell.dart';
import 'pages/product_detail_page.dart';
import 'pages/notifications_page.dart';
import 'fx.dart';

// Lebar maksimum konten di layar lebar (laptop)
const kMaxW = 1200.0;

/// Jumlah kolom: HP = 2, tablet kecil = 3, tablet = 4, laptop = 5
int gridCols(double w) {
  if (w < 520) return 2;
  if (w < 760) return 3;
  if (w < 900) return 4;
  return 5;
}

/// Grid produk: semua kotak SAMA ukuran (gambar persegi + area teks tinggi tetap).
SliverGridDelegate productGridDelegate(double w, {double gap = 12}) {
  final cols = gridCols(w);
  final cell = (w - gap * (cols - 1)) / cols;
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: cols,
    mainAxisSpacing: gap,
    crossAxisSpacing: gap,
    mainAxisExtent: cell + 84,
  );
}

/// Header tetap di paling atas. Logo "PoPack" mojok di kiri (sejajar dengan menu di bawahnya
/// pada layar lebar). Dipakai di HomeShell dan halaman Detail Produk.
class AppHeader extends StatelessWidget {
  final bool isAdmin, showBack, showCart;
  const AppHeader({super.key, this.isAdmin = false, this.showBack = false, this.showCart = false});

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 800;
    return Material(
      color: Colors.white,
      child: Container(
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: line))),
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: 60,
            child: Padding(
              padding: EdgeInsets.only(left: showBack ? 4 : (wide ? 24 : 16), right: 12),
              child: Row(children: [
                if (showBack) ...[
                  IconButton(icon: const Icon(Icons.arrow_back), tooltip: 'Kembali', onPressed: () => Navigator.maybePop(context)),
                  const SizedBox(width: 4),
                ],
                Image.asset('assets/images/logo.png', height: 36),
                const SizedBox(width: 10),
                const Text('PoPack', style: TextStyle(color: ink, fontSize: 20, fontWeight: FontWeight.w800)),
                if (isAdmin) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: const Color(0x141F3A8A), borderRadius: BorderRadius.circular(20)),
                    child: const Text('Admin', style: TextStyle(color: navy, fontSize: 11.5, fontWeight: FontWeight.w700)),
                  ),
                ],
                const Spacer(),
                ListenableBuilder(
                  listenable: notifs,
                  builder: (_, __) {
                    if (sb.auth.currentUser == null) return const SizedBox.shrink();
                    final n = notifs.unread;
                    return IconButton(
                      tooltip: 'Notifikasi',
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsPage())),
                      icon: Badge(
                        isLabelVisible: n > 0,
                        label: Text(n > 99 ? '99+' : '$n'),
                        child: const Icon(Icons.notifications_outlined, color: ink),
                      ),
                    );
                  },
                ),
                if (!isAdmin && showCart)
                  ListenableBuilder(
                    listenable: cart,
                    builder: (_, __) => IconButton(
                      tooltip: 'Keranjang',
                      onPressed: () {
                        Navigator.of(context).popUntil((r) => r.isFirst);
                        HomeShell.tab.value = 2;
                      },
                      icon: CartTarget(                               
                        child: Badge(
                          isLabelVisible: cart.count > 0,
                          label: Text('${cart.count}'),
                          child: const Icon(Icons.shopping_basket_outlined, color: ink),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Kolom pencarian (dipakai di Beranda & halaman Produk). Hasil dicari langsung saat mengetik.
class SearchBox extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hint;
  const SearchBox({super.key, required this.controller, required this.onChanged, this.hint = 'Cari produk kemasan...'});

  @override
  Widget build(BuildContext context) => Container(
        height: 46,
        decoration: cardDeco(12),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          textAlignVertical: TextAlignVertical.center,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: muted, fontSize: 14),
            prefixIcon: const Icon(Icons.search, size: 22, color: muted),
            suffixIcon: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (_, v, __) => v.text.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () {
                        controller.clear();
                        onChanged('');
                      }),
            ),
            border: InputBorder.none,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? sub;
  const EmptyState(this.icon, this.text, {super.key, this.sub});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: const Color(0xFF9CA3AF)),
            const SizedBox(height: 10),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 15)),
            if (sub != null) ...[
              const SizedBox(height: 4),
              Text(sub!, textAlign: TextAlign.center, style: const TextStyle(color: muted, fontSize: 13)),
            ],
          ]),
        ),
      );
}

/// Tombol hati (favorit). Produk yang ditandai muncul paling atas.
class FavButton extends StatelessWidget {
  final Product p;
  final double size;
  const FavButton(this.p, {super.key, this.size = 18});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: favs,
        builder: (_, __) {
          final on = favs.has(p.id);
          return PressScale(
            scale: 0.85,
            child: Material(
              color: Colors.white.withAlpha(235),
              shape: const CircleBorder(side: BorderSide(color: line)),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () async {
                  if (!await requireLogin(context)) return;
                  favs.toggle(p.id);
                },
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    transitionBuilder: (c, a) => ScaleTransition(
                        scale: CurvedAnimation(parent: a, curve: Curves.elasticOut), child: c),
                    child: Icon(on ? Icons.favorite : Icons.favorite_border,
                        key: ValueKey(on), size: size, color: on ? brand : muted),
                  ),
                ),
              ),
            ),
          );
        },
      );
}

/// Grid produk dalam bentuk sliver (bungkus dengan SliverPadding di pemanggil).
class SliverProducts extends StatelessWidget {
  final List<Product> list;
  const SliverProducts(this.list, {super.key});
  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
        builder: (_, k) => SliverGrid(
          gridDelegate: productGridDelegate(k.crossAxisExtent),
          delegate: SliverChildBuilderDelegate((_, i) => FadeSlideIn(index: i, child: ProductCard(list[i])), childCount: list.length),
        ),
      );
}

class ProductCard extends StatelessWidget {
  final Product p;
  const ProductCard(this.p, {super.key});

  Widget _ph(IconData i) => Container(color: const Color(0xFFF3F4F6), child: Icon(i, size: 36, color: const Color(0xFF9CA3AF)));

  void _open(BuildContext c) => Navigator.push(c, MaterialPageRoute(builder: (_) => ProductDetailPage(p)));

  Future<void> _quickAdd(BuildContext c) async {
    // Produk dengan beberapa jenis: pilih jenisnya di halaman detail
    if (p.hasVariants) return _open(c);
    if (!await requireLogin(c)) return;
    final v = p.variants.first;
    cart.add(p, v);
    if (!c.mounted) return;
    flyToCart(c, imageUrl: p.image); // bola terbang ke keranjang
    toast(c, '${nf(v.minOrder)} pcs ditambahkan ke keranjang');
  }

  @override
  Widget build(BuildContext context) {
    final low = p.ready && p.stock != null && p.stock! <= 10;
    return PressScale( // <-- dibungkus PressScale
      child: Material(
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: line)),
        child: InkWell(
          onTap: () => _open(context),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(fit: StackFit.expand, children: [
                (p.image == null || p.image!.isEmpty)
                    ? _ph(Icons.inventory_2_outlined)
                    : Image.network(p.image!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _ph(Icons.broken_image_outlined)),
                if (low)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: const Color(0xFFEA580C), borderRadius: BorderRadius.circular(20)),
                      child: Text('Sisa ${p.stock}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ),
                if (!p.ready)
                  Container(
                    color: const Color(0x80000000),
                    alignment: Alignment.center,
                    child: const Text('Stok Habis', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                Positioned(top: 6, right: 6, child: FavButton(p, size: 17)),
              ]),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    height: 36,
                    child: Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, height: 1.35, color: ink)),
                  ),
                  const Spacer(),
                  Row(children: [
                    Expanded(
                      child: Text(rp(p.price),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: brand, fontWeight: FontWeight.w800, fontSize: 14.5)),
                    ),
                    if (p.ready)
                      SizedBox(
                        width: 28,
                        height: 28,
                        child: Builder( // <-- Builder supaya dapat context tombol "+"
                          builder: (bc) => PressScale(
                            scale: 0.8,
                            child: Material(
                              color: brand,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () => _quickAdd(bc), // <-- pakai bc, bukan context
                                child: const Icon(Icons.add, size: 18, color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ]),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  final String status;
  const StatusPill(this.status, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.withAlpha(30), borderRadius: BorderRadius.circular(20)),
      child: Text(statusLabel[status] ?? status, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

IconData _statusIcon(String s) => switch (s) {
      'approved' => Icons.check_circle_outline,
      'pending' => Icons.hourglass_top_rounded,
      'cancel_requested' => Icons.undo_rounded,
      'cancelled' => Icons.cancel_outlined,
      _ => Icons.block_outlined,
    };

class OrderCard extends StatelessWidget {
  final Map o;
  final List<Widget> actions;
  final bool admin;
  const OrderCard({super.key, required this.o, this.actions = const [], this.admin = false});

  String _itemName(Map i) {
    final name = '${i['products']?['name'] ?? '-'}';
    final vn = i['variant_name'];
    return (vn is String && vn.isNotEmpty && vn != name) ? '$name • $vn' : name;
  }

  @override
  Widget build(BuildContext context) {
    final items = o['order_items'] as List;
    num total = 0;
    for (final i in items) {
      total += (i['qty'] as num) * (i['price'] as num);
    }
    final s = o['status'] as String;
    final c = statusColor(s);
    final id = '${o['id']}';
    final code = (id.length >= 8 ? id.substring(0, 8) : id).toUpperCase();
    final who = o['profiles'];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      clipBehavior: Clip.antiAlias,
      decoration: cardDeco(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: c.withAlpha(28), borderRadius: BorderRadius.circular(10)),
              child: Icon(_statusIcon(s), size: 20, color: c),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Pesanan #$code', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                const SizedBox(height: 2),
                Text(DateTime.parse(o['created_at']).toLocal().toString().substring(0, 16), style: const TextStyle(color: muted, fontSize: 12.5)),
              ]),
            ),
            const SizedBox(width: 8),
            StatusPill(s),
          ]),
        ),
        if (admin && who != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Row(children: [
              const Icon(Icons.business_outlined, size: 16, color: muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text('${who['full_name'] ?? '-'} • ${who['company'] ?? '-'}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
              ),
            ]),
          ),
        const Divider(height: 1, color: line),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
          child: Column(children: [
            for (final i in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_itemName(i), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text('${nf(i['qty'] as num)} × ${rp(i['price'] as num)}', style: const TextStyle(color: muted, fontSize: 12.5)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Text(rp((i['qty'] as num) * (i['price'] as num)), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                ]),
              ),
          ]),
        ),
        Container(
          color: bg,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Total (${items.length} produk)', style: const TextStyle(color: muted, fontSize: 13)),
            Text(rp(total), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: ink)),
          ]),
        ),
        if (actions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: Align(alignment: Alignment.centerRight, child: Wrap(spacing: 4, children: actions)),
          ),
      ]),
    );
  }
}
