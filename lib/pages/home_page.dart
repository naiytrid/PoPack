import 'dart:async';
import 'package:flutter/material.dart';
import '../core.dart';
import '../widgets.dart';
import 'home_shell.dart';
import 'product_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List> cats;
  late Future<List<Product>> prods;
  final sc = TextEditingController();
  String q = '';

  @override
  void initState() {
    super.initState();
    _load();
    sync.addListener(_onSync); // auto reload saat data berubah
  }

  void _onSync() {
    if (mounted) setState(_load);
  }

  @override
  void dispose() {
    sync.removeListener(_onSync);
    sc.dispose();
    super.dispose();
  }

  Future<List> _cats() async => await sb.from('categories').select().order('id');

  void _load() {
    cats = _cats();
    prods = fetchProducts(); // semua produk aktif -> pencarian mencakup seluruh katalog
  }

  Future<void> _refresh() async {
    setState(_load);
    try {
      await Future.wait([cats, prods]);
    } catch (_) {}
  }

  bool get _searching => q.trim().isNotEmpty;

  Widget _title(String t, {String? action, VoidCallback? onTap}) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Expanded(child: Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: ink))),
            if (action != null) GestureDetector(onTap: onTap, child: Text(action, style: const TextStyle(color: brand, fontWeight: FontWeight.w600))),
          ]),
        ),
      );

  Widget _searchBar() => SliverAppBar(
        pinned: true,
        automaticallyImplyLeading: false,
        centerTitle: false,
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        toolbarHeight: 66,
        titleSpacing: 16,
        title: SizedBox(
          width: double.infinity,
          child: SearchBox(controller: sc, onChanged: (v) => setState(() => q = v)),
        ),
      );

  Widget _catList() => SizedBox(
        height: 92,
        child: FutureBuilder(
          future: cats,
          builder: (_, s) {
            final l = (s.data as List?) ?? [];
            return ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 10), children: [
              for (final c in l)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductPage(categoryId: c['id'], title: c['name']))),
                  child: SizedBox(
                    width: 84,
                    child: Column(children: [
                      Container(width: 56, height: 56, decoration: cardDeco(14), child: Icon(catIcon(c['name']), color: navy, size: 26)),
                      const SizedBox(height: 6),
                      Text(c['name'], textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, height: 1.2)),
                    ]),
                  ),
                ),
            ]);
          },
        ),
      );

  Widget _grid() => ListenableBuilder(
        listenable: favs, // favorit langsung naik ke atas
        builder: (_, __) => _gridBody(),
      );

  Widget _gridBody() => FutureBuilder<List<Product>>(
        future: prods,
        builder: (_, s) {
          if (s.hasError) return SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(24), child: Center(child: Text('Gagal memuat: ${s.error}'))));
          if (!s.hasData) return const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())));
          final all = s.data!;
          final list = _searching ? favFirst(all.where((p) => matchProduct(p, q)).toList()) : favFirst(all).take(30).toList();
          if (list.isEmpty) {
            return SliverToBoxAdapter(
              child: _searching
                  ? EmptyState(Icons.search_off, 'Produk "${q.trim()}" tidak ditemukan', sub: 'Coba kata kunci lain atau lebih singkat')
                  : const EmptyState(Icons.inventory_2_outlined, 'Belum ada produk'),
            );
          }
          return SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverProducts(list),
          );
        },
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kMaxW),
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: CustomScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  _searchBar(),
                  if (!_searching) ...[
                    const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.fromLTRB(16, 4, 16, 0), child: _Banners())),
                    _title('Kategori'),
                    SliverToBoxAdapter(child: _catList()),
                    _title('Produk Terbaru'),
                  ] else
                    _title('Hasil untuk “${q.trim()}”'),
                  _grid(),
                  if (!_searching)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                        child: Center(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                                foregroundColor: brand,
                                side: const BorderSide(color: brand),
                                minimumSize: const Size(220, 46),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                            onPressed: () => HomeShell.tab.value = 1,
                            child: const Text('Lihat Semua Produk', style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                    )
                  else
                    const SliverToBoxAdapter(child: SizedBox(height: 32)),
                ],
              ),
            ),
          ),
        ),
      );
}

// ===== Banner carousel (otomatis geser tiap 4 detik, bisa di-swipe, titik bisa diklik) =====
class _Banners extends StatefulWidget {
  const _Banners();
  @override
  State<_Banners> createState() => _BannersState();
}

class _BannersState extends State<_Banners> {
  // Ubah teks/warna banner di sini
  static const _slides = [
    (brand, 'Kemasan berkualitas untuk bisnis Anda', 'Pesan langsung dan pantau status pesanan dari aplikasi.', Icons.local_shipping_outlined),
    (navy, 'Beragam kategori kemasan', 'Pharma, medical, cosmetic, food, dan banyak lagi.', Icons.inventory_2_outlined),
    (Color(0xFF111827), 'Ready stock, proses cepat', 'Cek ketersediaan stok langsung di setiap produk.', Icons.bolt_outlined),
  ];

  final pc = PageController();
  int cur = 0;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!pc.hasClients) return;
      pc.animateToPage((cur + 1) % _slides.length, duration: const Duration(milliseconds: 450), curve: Curves.easeInOut);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (_, c) {
        final wide = c.maxWidth > 600;
        final h = (c.maxWidth * 0.26).clamp(140.0, 260.0);
        return SizedBox(
          height: h,
          child: Stack(children: [
            PageView.builder(
              controller: pc,
              itemCount: _slides.length,
              onPageChanged: (i) => setState(() => cur = i),
              itemBuilder: (_, i) {
                final s = _slides[i];
                return Container(
                  decoration: BoxDecoration(color: s.$1, borderRadius: BorderRadius.circular(14)),
                  padding: EdgeInsets.symmetric(horizontal: wide ? 40 : 20),
                  child: Row(children: [
                    Expanded(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s.$2,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.white, fontSize: wide ? 28 : 18, fontWeight: FontWeight.w800, height: 1.2)),
                        const SizedBox(height: 8),
                        Text(s.$3,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: const Color(0xD9FFFFFF), fontSize: wide ? 15 : 12.5, height: 1.35)),
                      ]),
                    ),
                    const SizedBox(width: 16),
                    Icon(s.$4, size: wide ? 110 : 56, color: const Color(0x40FFFFFF)),
                  ]),
                );
              },
            ),
            Positioned(
              bottom: 10,
              left: 0,
              right: 0,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < _slides.length; i++)
                  GestureDetector(
                    onTap: () => pc.animateToPage(i, duration: const Duration(milliseconds: 350), curve: Curves.easeInOut),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: cur == i ? 20 : 7,
                      height: 7,
                      decoration: BoxDecoration(color: cur == i ? Colors.white : const Color(0x80FFFFFF), borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
              ]),
            ),
          ]),
        );
      });
}