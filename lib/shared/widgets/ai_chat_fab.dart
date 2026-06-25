import 'dart:async';
import 'package:flutter/material.dart';
import '../../features/chat/chat_screen.dart';
import '../../core/app_colors.dart';

/// Animated "Ask AI Assistant" FAB — starts expanded, auto-collapses after 3.5 s.
class AiChatFab extends StatefulWidget {
  final String userRole; // 'organizer' | 'student'
  const AiChatFab({super.key, required this.userRole});

  @override
  State<AiChatFab> createState() => _AiChatFabState();
}

class _AiChatFabState extends State<AiChatFab>
    with SingleTickerProviderStateMixin {
  bool   _expanded = true;
  Timer? _timer;

  late final AnimationController _labelCtrl;
  late final Animation<double>   _labelFade;
  late final Animation<double>   _labelSlide;

  @override
  void initState() {
    super.initState();
    _labelCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 380))
      ..forward();
    _labelFade  = CurvedAnimation(parent: _labelCtrl, curve: Curves.easeOut);
    _labelSlide = Tween<double>(begin: 10.0, end: 0.0).animate(
      CurvedAnimation(parent: _labelCtrl, curve: Curves.easeOut),
    );
    _timer = Timer(const Duration(milliseconds: 3500), _startCollapse);
  }

  void _startCollapse() {
    if (!mounted || !_expanded) return;
    _labelCtrl.reverse().then((_) {
      if (mounted) setState(() => _expanded = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _labelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (_expanded) {
          _timer?.cancel();
          _startCollapse();
        }
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ChatScreen(userRole: widget.userRole)),
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeInOut,
        height: 52,
        width: _expanded ? 202 : 52,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: const LinearGradient(
            colors: [Color(0xFF1E1408), kGold],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(color: kGold.withValues(alpha: 0.32), blurRadius: 14, offset: const Offset(0, 5)),
          ],
        ),
        clipBehavior: Clip.hardEdge,
        child: Row(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(
              width: 52,
              child: Center(child: Icon(Icons.smart_toy_rounded, color: Colors.white, size: 24)),
            ),
            Expanded(
              child: AnimatedBuilder(
                animation: _labelCtrl,
                builder: (_, child) => Opacity(
                  opacity: _labelFade.value,
                  child: Transform.translate(
                    offset: Offset(_labelSlide.value, 0),
                    child: child,
                  ),
                ),
                child: const Padding(
                  padding: EdgeInsets.only(right: 16),
                  child: Text(
                    'Ask AI Assistant',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.3,
                    ),
                    overflow: TextOverflow.clip,
                    maxLines: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
