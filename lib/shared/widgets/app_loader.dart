import 'package:flutter/material.dart';
import '../../core/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AppFullScreenLoader
// ─────────────────────────────────────────────────────────────────────────────

class AppFullScreenLoader extends StatelessWidget {
  final String? message;
  const AppFullScreenLoader({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: kGoldGradient,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: kGold.withValues(alpha: 0.30),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(Icons.event_rounded, color: Colors.white, size: 36),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                color: kGold,
                strokeWidth: 2.5,
                backgroundColor: kGold.withValues(alpha: 0.15),
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 16),
              Text(
                message!,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: kSubText,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AppShimmerList
// ─────────────────────────────────────────────────────────────────────────────

class AppShimmerList extends StatefulWidget {
  final int  itemCount;
  final bool hasAvatar;
  final bool hasImage;
  const AppShimmerList({
    super.key,
    this.itemCount = 5,
    this.hasAvatar = false,
    this.hasImage  = false,
  });

  @override
  State<AppShimmerList> createState() => _AppShimmerListState();
}

class _AppShimmerListState extends State<AppShimmerList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _shimmerBox(Color c1, Color c2, {double? w, double h = 12, double r = 8}) =>
      Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(r),
          gradient: LinearGradient(
            colors: [
              Color.lerp(c1, c2, _anim.value)!,
              Color.lerp(c2, c1, _anim.value)!,
            ],
          ),
        ),
      );

  Widget _buildItem(AppTk t) {
    final c1 = t.shimmer1;
    final c2 = t.shimmer2;

    if (widget.hasImage) {
      // Event-card style: image placeholder on left + text lines
      return Container(
        height: 96,
        decoration: BoxDecoration(
          color: c1,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 88,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                gradient: LinearGradient(colors: [c1, c2]),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _shimmerBox(c1, c2, h: 13, w: double.infinity),
                  const SizedBox(height: 8),
                  _shimmerBox(c1, c2, h: 11, w: 160),
                  const SizedBox(height: 8),
                  _shimmerBox(c1, c2, h: 10, w: 100),
                ],
              ),
            ),
            const SizedBox(width: 14),
          ],
        ),
      );
    }

    if (widget.hasAvatar) {
      // List-row style: avatar circle + text lines
      return Container(
        height: 80,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: c1,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            _shimmerBox(c1, c2, w: 44, h: 44, r: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _shimmerBox(c1, c2, h: 13, w: double.infinity),
                  const SizedBox(height: 8),
                  _shimmerBox(c1, c2, h: 10, w: 120),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Plain card: just text lines
    return Container(
      height: 88,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: c1,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _shimmerBox(c1, c2, h: 13, w: double.infinity),
          const SizedBox(height: 9),
          _shimmerBox(c1, c2, h: 11, w: 220),
          const SizedBox(height: 9),
          _shimmerBox(c1, c2, h: 10, w: 140),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTk(Theme.of(context).brightness == Brightness.dark);
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: widget.itemCount,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, __) => _buildItem(t),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AppOverlayLoader
// ─────────────────────────────────────────────────────────────────────────────

class AppOverlayLoader extends StatelessWidget {
  final String? message;
  const AppOverlayLoader({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.35),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 20,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  color: kGold,
                  strokeWidth: 3,
                  backgroundColor: kGold.withValues(alpha: 0.15),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message ?? 'Please wait…',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: kSubText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
