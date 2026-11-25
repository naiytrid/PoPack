import 'package:flutter/material.dart';
import '../core.dart';
import '../widgets.dart';

class ProductPage extends StatefulWidget {
  final int? categoryId;
  final String? title;
  const ProductPage({super.key, this.categoryId, this.title});
  @override
  State<ProductPage> createState() => _ProductPageState();
}

class _ProductPageState extends State<ProductPage> {
  final ctrl = TextEditingController();
  String q = '', sort = 'new';
  int? cat;
  late Future<List> cats = _loadCats();
  late Future<List<Product>> fut = fetchProducts();

  @override
  void initState() {
    super.initState();
    cat = widget.categoryId;
    sync.addListener(_onSync); // auto reload saat data di database berubah
  }

  @override
  void dispose() {
    sync.removeListener(_onSync);
    ctrl.dispose();
    super.dispose();
  }

  void _onSync() {
    if (!mounted) return;
    setState(() {
      fut = fetchProducts();
      cats = _loadCats();
    });
  }

  Future<List> _loadCats() async => await sb.from('categories').select().order('id');

  List<Product> _apply(List<Product> all) {
    final l = all.where((p) => (cat == null || p.categoryId == cat) && matchProduct(p, q)).toList();
    switch (sort) {
      case 'low':
        l.sort((a, b) => a.price.compareTo(b.price));
      case 'high':
        l.sort((a, b) => b.price.compareTo(a.price));
      case 'name':
        l.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    return l;
  }

  Widget _chip(String label, bool sel, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
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

  PopupMenuItem<String> _opt(String v, String t) => PopupMenuItem(
        value: v,
        child: Row(children: [
          SizedBox(width: 24, child: sort == v ? const Icon(Icons.check, size: 18, color: brand) : null),
          Text(t, style: TextStyle(fontWeight: sort == v ? FontWeight.w700 : FontWeight.w400)),
        ]),
      );

  // Tombol filter/sortir di sisi kanan
  Widget _sortBtn() => Container(
        width: 46,
        height: 46,
        decoration: cardDeco(12),
        child: PopupMenuButton<String>(
          tooltip: 'Filter & urutkan',
          icon: Icon(Icons.tune, color: sort == 'new' ? ink : brand),
          onSelected: (v) => setState(() => sort = v),
          itemBuilder: (_) => [
            _opt('new', 'Terbaru'),
            _opt('low', 'Harga terendah ke tertinggi'),
            _opt('high', 'Harga tertinggi ke terendah'),
            _opt('name', 'Nama A–Z'),
          ],
        ),
      );

  Widget _catHeader(String name, int count, {IconData? icon, Color? iconColor}) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: const Color(0x141F3A8A), borderRadius: BorderRadius.circular(8)),
              child: Icon(icon ?? catIcon(name), size: 18, color: iconColor ?? navy),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: ink))),
            Text('$count produk', style: const TextStyle(color: muted, fontSize: 12.5)),
          ]),
        ),
      );

  List<Widget> _slivers(List<Product> list, List catList) {
    final grouped = cat == null && sort == 'new' && q.trim().isEmpty;
    final out = <Widget>[
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text('${list.length} produk', style: const TextStyle(color: muted, fontSize: 13)),
        ),
      ),
    ];
    if (list.isEmpty) {
      out.add(const SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyState(Icons.search_off, 'Produk tidak ditemukan', sub: 'Coba kata kunci atau kategori lain'),
      ));
      return out;
    }
    SliverPadding grid(List<Product> l) => SliverPadding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), sliver: SliverProducts(l));
    if (!grouped) {
      // Favorit selalu di paling atas
      out.add(const SliverToBoxAdapter(child: SizedBox(height: 8)));
      out.add(grid(favFirst(list)));
    } else {
      final favList = list.where((p) => favs.has(p.id)).toList();
      final used = <String>{...favList.map((e) => e.id)};
      if (favList.isNotEmpty) {
        out..add(_catHeader('Favorit', favList.length, icon: Icons.favorite, iconColor: brand))..add(grid(favList));
      }
      for (final c in catList) {
        final items = list.where((p) => p.categoryId == c['id'] && !used.contains(p.id)).toList();
        if (items.isEmpty) continue;
        used.addAll(items.map((e) => e.id));
        out..add(_catHeader('${c['name']}', items.length))..add(grid(items));
      }
      final rest = list.where((p) => !used.contains(p.id)).toList();
      if (rest.isNotEmpty) out..add(_catHeader('Lainnya', rest.length))..add(grid(rest));
    }
    out.add(const SliverToBoxAdapter(child: SizedBox(height: 24)));
    return out;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.title ?? 'Produk')),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kMaxW),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Row(children: [
                  Expanded(child: SearchBox(controller: ctrl, onChanged: (v) => setState(() => q = v))),
                  const SizedBox(width: 8),
                  _sortBtn(),
                ]),
              ),
              SizedBox(
                height: 44,
                child: FutureBuilder<List>(
                  future: cats,
                  builder: (_, s) {
                    final l = s.data ?? [];
                    return ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                      _chip('Semua', cat == null, () => setState(() => cat = null)),
                      for (final c in l) _chip(c['name'], cat == c['id'], () => setState(() => cat = c['id'])),
                    ]);
                  },
                ),
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: favs, // urutan berubah langsung saat menandai/menghapus favorit
                  builder: (_, __) => FutureBuilder<List<Product>>(
                    future: fut,
                    builder: (_, s) {
                      if (s.hasError) return Center(child: Text('Gagal memuat: ${s.error}'));
                      if (!s.hasData) return const Center(child: CircularProgressIndicator());
                      final list = _apply(s.data!);
                      return FutureBuilder<List>(
                        future: cats,
                        builder: (_, cs) => RefreshIndicator(
                          onRefresh: () async {
                            setState(() => fut = fetchProducts());
                            await fut;
                          },
                          child: CustomScrollView(
                            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                            physics: const AlwaysScrollableScrollPhysics(),
                            slivers: _slivers(list, cs.data ?? []),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
}
