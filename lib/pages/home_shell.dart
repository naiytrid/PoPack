import 'dart:async';
import 'package:flutter/material.dart';
import '../core.dart';
import '../widgets.dart';
import 'home_page.dart';
import 'product_page.dart';
import 'cart_page.dart';
import 'account_page.dart';
import 'admin_dashboard.dart';
import 'admin_page.dart';
import '../fx.dart';
import 'package:flutter/services.dart'; 
import 'orders_page.dart';

class _D {
  final Widget icon, sel;
  final String label;
  const _D(this.icon, this.sel, this.label);
}

_D _d(IconData i, IconData s, String l) => _D(Icon(i), Icon(s, color: brand), l);



class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  static final tab = ValueNotifier<int>(0); // tab pelanggan
  static final adminTab = ValueNotifier<int>(0); // tab admin
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _pages = [HomePage(), ProductPage(), CartPage(), OrdersPage(), AccountPage()];
  bool checked = false, isAdmin = false;
  late final StreamSubscription _sub;

  @override
  void initState() {
    super.initState();
    _check();
    _sub = sb.auth.onAuthStateChange.listen((_) => _check());
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (authLocked) return;
    var a = false;
    try {
      final p = await myProfile();
      a = p?['role'] == 'admin';
    } catch (_) {}
    if (!mounted) return;
    if (!checked || a != isAdmin) {
      setState(() {
        checked = true;
        isAdmin = a;
      });
      HomeShell.tab.value = 0;
      HomeShell.adminTab.value = 0;
    }
  }

  Future<void> _onBack() async {
    final tab = isAdmin ? HomeShell.adminTab : HomeShell.tab;
    if (tab.value != 0) { tab.value = 0; return; }   // back dari tab lain -> ke Beranda dulu
    if (await confirmExit(context)) SystemNavigator.pop();
  }

  Widget _cartIcon(bool selected) => ListenableBuilder(
        listenable: cart,
        builder: (_, __) => CartTarget(
          child: Badge(
            isLabelVisible: cart.count > 0,
            label: Text('${cart.count}'),
            child: Icon(selected ? Icons.shopping_basket : Icons.shopping_basket_outlined, color: selected ? brand : null),
          ),
        ),
      );

  List<_D> get _custDest => [
        _d(Icons.home_outlined, Icons.home, 'Beranda'),
        _d(Icons.grid_view_outlined, Icons.grid_view_rounded, 'Produk'),
        _D(_cartIcon(false), _cartIcon(true), 'Keranjang'),
        _d(Icons.receipt_long_outlined, Icons.receipt_long, 'Riwayat'),
        _d(Icons.person_outline, Icons.person, 'Akun'),
      ];

  static final _adminDest = [
    _d(Icons.dashboard_outlined, Icons.dashboard, 'Dashboard'),
    _d(Icons.receipt_long_outlined, Icons.receipt_long, 'Pesanan'),
    _d(Icons.inventory_2_outlined, Icons.inventory_2, 'Produk'),
    _d(Icons.people_outline, Icons.people, 'Pengguna'),
    _d(Icons.bar_chart_outlined, Icons.bar_chart, 'Laporan'),
    _d(Icons.person_outline, Icons.person, 'Akun'),
  ];

  Widget _adminBody(int i) => KeyedSubtree(
        key: ValueKey(i),
        child: switch (i) {
          0 => const AdminDashboard(),
          1 => const AdminPage(section: 'orders'),
          2 => const AdminPage(section: 'products'),
          3 => const AdminPage(section: 'users'),
          4 => const AdminPage(section: 'report'),
          _ => const AccountPage(),
        },
      );

  Widget _frame(bool wide, int i, ValueChanged<int> on, List<_D> d, Widget body) {
    final content = MediaQuery.removePadding(context: context, removeTop: true, child: body);
    // Header selebar layar, logo mojok kiri (sejajar dengan menu di bawahnya)
    final header = AppHeader(isAdmin: isAdmin, showCart: !isAdmin && wide);
    if (wide) {
      final row = Row(children: [
        NavigationRail(
          selectedIndex: i,
          onDestinationSelected: on,
          backgroundColor: Colors.white,
          indicatorColor: const Color(0x1AE53935),
          labelType: NavigationRailLabelType.all,
          selectedLabelTextStyle: const TextStyle(color: brand, fontWeight: FontWeight.w700, fontSize: 12),
          destinations: [for (final x in d) NavigationRailDestination(icon: x.icon, selectedIcon: x.sel, label: Text(x.label))],
        ),
        const VerticalDivider(width: 1, color: line),
        Expanded(child: content),
      ]);
      return Scaffold(body: Column(children: [header, Expanded(child: row)]));
    }
    return Scaffold(
      body: Column(children: [header, Expanded(child: content)]),
      bottomNavigationBar: FxBottomNav(
        index: i,
        onTap: on,
        items: [for (final x in d) FxNavItem(x.icon, x.sel, x.label)],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!checked) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: LayoutBuilder(builder: (_, c) {
        final wide = c.maxWidth >= 800;
        if (isAdmin) {
          return ValueListenableBuilder<int>(
            valueListenable: HomeShell.adminTab,
            builder: (_, i, __) => _frame(wide, i, (v) => HomeShell.adminTab.value = v, _adminDest, _adminBody(i)),
          );
        }
        return ValueListenableBuilder<int>(
          valueListenable: HomeShell.tab,
          builder: (_, i, __) => _frame(wide, i, (v) => HomeShell.tab.value = v, _custDest, IndexedStack(index: i, children: _pages)),
        );
      }),
    );
  }
}
