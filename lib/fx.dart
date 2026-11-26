import 'dart:math' as math;
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core.dart';

// =====================================================================
// 1. ANIMASI "LEMPAR BOLA BASKET" KE KERANJANG
// =====================================================================

/// Naik setiap kali bola sampai di keranjang -> ikon keranjang bergoyang.
final cartBump = ValueNotifier<int>(0);
final _targets = <State<CartTarget>>[];

/// Bungkus ikon keranjang (header / navbar) dengan widget ini supaya jadi "ring"-nya.
class CartTarget extends StatefulWidget {
  final Widget child;
  const CartTarget({super.key, required this.child});
  @override
  State<CartTarget> createState() => _CartTargetState();
}

class _CartTargetState extends State<CartTarget> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));

  void _bump() {
    if (mounted) _c.forward(from: 0);
  }

  @override
  void initState() {
    super.initState();
    _targets.add(this);
    cartBump.addListener(_bump);
  }

  @override
  void dispose() {
    _targets.remove(this);
    cartBump.removeListener(_bump);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, child) {
          final scale = 1 + 0.3 * math.sin(_c.value * math.pi); // membesar lalu kembali, satu kali
          return Transform.scale(scale: scale, child: child);
        },
        child: widget.child,
      );
}

Offset? _targetCenter(Size screen) {
  for (final s in _targets.reversed) {
    if (!s.mounted) continue;
    final ro = s.context.findRenderObject();
    if (ro is! RenderBox || !ro.attached || !ro.hasSize) continue;
    final c = ro.localToGlobal(ro.size.center(Offset.zero));
    if (c.dx < 0 || c.dy < 0 || c.dx > screen.width || c.dy > screen.height) continue;
    return c;
  }
  return null;
}

/// Panggil setelah `cart.add(...)`. [from] = context widget asal (tombol / gambar produk).
void flyToCart(BuildContext from, {String? imageUrl}) {
  final screen = MediaQuery.sizeOf(from);
  final ro = from.findRenderObject();
  final end = _targetCenter(screen);
  if (ro is! RenderBox || !ro.attached || end == null) {
    cartBump.value++;
    return;
  }
  var start = ro.localToGlobal(ro.size.center(Offset.zero));
  start = Offset(start.dx.clamp(30.0, screen.width - 30), start.dy.clamp(30.0, screen.height - 30));
  HapticFeedback.selectionClick();
  late OverlayEntry e;
  e = OverlayEntry(
    builder: (_) => _Ball(
      start: start,
      end: end,
      imageUrl: imageUrl,
      onDone: () {
        e.remove();
        cartBump.value++;
        HapticFeedback.lightImpact();
      },
    ),
  );
  Overlay.of(from, rootOverlay: true).insert(e);
}

class _Ball extends StatefulWidget {
  final Offset start, end;
  final String? imageUrl;
  final VoidCallback onDone;
  const _Ball({required this.start, required this.end, required this.imageUrl, required this.onDone});
  @override
  State<_Ball> createState() => _BallState();
}

class _BallState extends State<_Ball> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.start, e = widget.end;
    // titik kontrol kurva: sedikit di atas titik awal/akhir, jadi lintasannya melengkung halus
    final ctrl = Offset((s.dx + e.dx) / 2, math.min(s.dy, e.dy) - 60);
    final url = widget.imageUrl;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = Curves.easeInOutCubic.transform(_c.value);
        final u = 1 - t;
        // kurva bezier
        final x = u * u * s.dx + 2 * u * t * ctrl.dx + t * t * e.dx;
        final y = u * u * s.dy + 2 * u * t * ctrl.dy + t * t * e.dy;
        final size = 58 - 40 * t; // 58 -> 18
        final opacity = _c.value > 0.85 ? ((1 - _c.value) / 0.15).clamp(0.0, 1.0) : 1.0;
        return Positioned(
          left: x - size / 2,
          top: y - size / 2,
          child: IgnorePointer(
            child: Opacity(
              opacity: opacity,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(size * 0.22),
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 10, offset: Offset(0, 3))],
                ),
                clipBehavior: Clip.antiAlias,
                child: (url == null || url.isEmpty)
                    ? const Icon(Icons.inventory_2_outlined, color: brand)
                    : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.inventory_2_outlined, color: brand)),
              ),
            ),
          ),
        );
      },
    );
  }
}

// =====================================================================
// 2. EFEK TEKAN (membal saat disentuh) + MUNCUL BERTAHAP
// =====================================================================

/// Bungkus widget apa pun (tombol, kartu, chip). Tidak mengganggu onTap yang ada.
class PressScale extends StatefulWidget {
  final Widget child;
  final double scale;
  const PressScale({super.key, required this.child, this.scale = 0.95});
  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool down = false;
  void _set(bool v) {
    if (down != v && mounted) setState(() => down = v);
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) => _set(true),
        onPointerUp: (_) => _set(false),
        onPointerCancel: (_) => _set(false),
        child: AnimatedScale(
          scale: down ? widget.scale : 1,
          duration: Duration(milliseconds: down ? 90 : 320),
          curve: down ? Curves.easeOut : Curves.easeOutBack,
          child: widget.child,
        ),
      );
}

/// Muncul pelan + naik sedikit (dipakai di kartu produk).
class FadeSlideIn extends StatelessWidget {
  final Widget child;
  final int index;
  const FadeSlideIn({super.key, required this.child, this.index = 0});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: Duration(milliseconds: 320 + (index % 8) * 45),
        curve: Curves.easeOutCubic,
        builder: (_, v, ch) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, (1 - v) * 18), child: ch)),
        child: child,
      );
}

// =====================================================================
// 3. NAVBAR BAWAH INTERAKTIF
// =====================================================================

class FxNavItem {
  final Widget icon, selIcon;
  final String label;
  const FxNavItem(this.icon, this.selIcon, this.label);
}

class FxBottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final List<FxNavItem> items;
  const FxBottomNav({super.key, required this.index, required this.onTap, required this.items});

  @override
  Widget build(BuildContext context) {
    final alwaysLabel = items.length <= 4;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: line)),
        boxShadow: [BoxShadow(color: Color(0x0F000000), blurRadius: 12, offset: Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 66,
          child: LayoutBuilder(builder: (_, c) {
            final w = c.maxWidth / items.length;
            return Stack(children: [
              // pil yang meluncur ke tab terpilih
              AnimatedPositioned(
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutBack,
                left: index * w + 8,
                top: 7,
                width: w - 16,
                height: 52,
                child: Container(decoration: BoxDecoration(color: const Color(0x1AE53935), borderRadius: BorderRadius.circular(22))),
              ),
              // garis kecil di atas
              AnimatedPositioned(
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutBack,
                left: index * w + w / 2 - 14,
                top: 0,
                width: 28,
                height: 3,
                child: Container(decoration: BoxDecoration(color: brand, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(3)))),
              ),
              Row(children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: _NavTile(
                      item: items[i],
                      sel: i == index,
                      showLabel: alwaysLabel,
                      onTap: () {
                        if (i != index) HapticFeedback.selectionClick();
                        onTap(i);
                      },
                    ),
                  ),
              ]),
            ]);
          }),
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final FxNavItem item;
  final bool sel, showLabel;
  final VoidCallback onTap;
  const _NavTile({required this.item, required this.sel, required this.showLabel, required this.onTap});

  @override
  Widget build(BuildContext context) => PressScale(
        scale: 0.88,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            AnimatedSlide(
              offset: sel ? const Offset(0, -0.06) : Offset.zero,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutBack,
              child: AnimatedScale(
                scale: sel ? 1.2 : 1.0,
                duration: const Duration(milliseconds: 500),
                curve: Curves.elasticOut,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: KeyedSubtree(key: ValueKey(sel), child: sel ? item.selIcon : item.icon),
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              child: (sel || showLabel)
                  ? Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: TextStyle(fontSize: 11.5, fontWeight: sel ? FontWeight.w700 : FontWeight.w500, color: sel ? brand : muted),
                        child: Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ]),
        ),
      );
}

// =====================================================================
// 4. TRANSISI HALAMAN
// =====================================================================

class FxPageTransitions extends PageTransitionsBuilder {
  const FxPageTransitions();
  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation, Animation<double> secondary, Widget child) {
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(position: Tween(begin: const Offset(0.07, 0), end: Offset.zero).animate(curved), child: child),
    );
  }
}

const fxPageTransitionsTheme = PageTransitionsTheme(builders: {
  TargetPlatform.android: FxPageTransitions(),
  TargetPlatform.iOS: CupertinoPageTransitionsBuilder(), // tetap bisa swipe-back di iOS
  TargetPlatform.windows: FxPageTransitions(),
  TargetPlatform.linux: FxPageTransitions(),
  TargetPlatform.macOS: FxPageTransitions(),
});

// =====================================================================
// 5. KONFIRMASI KELUAR
// =====================================================================

Future<bool> confirmExit(BuildContext context) async {
  final r = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Tutup',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 300),
    transitionBuilder: (_, a, __, child) {
      final c = CurvedAnimation(parent: a, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
      return FadeTransition(opacity: a, child: ScaleTransition(scale: Tween<double>(begin: 0.85, end: 1).animate(c), child: child));
    },
    pageBuilder: (c, _, __) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      icon: Container(
        padding: const EdgeInsets.all(14),
        decoration: const BoxDecoration(color: Color(0x1AE53935), shape: BoxShape.circle),
        child: const Icon(Icons.exit_to_app, color: brand, size: 30),
      ),
      title: const Text('Keluar dari PoPack?', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
      content: const Text('Tekan "Keluar" untuk menutup aplikasi.', textAlign: TextAlign.center, style: TextStyle(color: muted)),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Keluar', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: brand),
          onPressed: () => Navigator.pop(c, false),
          child: const Text('Tetap di sini'),
        ),
      ],
    ),
  );
  return r == true;
}