import 'package:flutter/material.dart';
import '../../core/services/chat_service.dart';
import '../../core/app_colors.dart';

// ── Palette ────────────────────────────────────────────────────────────────────
const Color _kBg      = Color(0xFFF7F3EC);
const Color _kText    = Color(0xFF1A1A1A);
const Color _kSub     = Color(0xFF6B7280);
const Color _kMuted   = Color(0xFFB0B7C3);
const Color _kCard    = Color(0xFFFFFFFF);
const Color _kSurface = Color(0xFFF1EDE6);

// ── Time helpers ───────────────────────────────────────────────────────────────
String _msgTime(DateTime t) {
  final h  = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m  = t.minute.toString().padLeft(2, '0');
  final ap = t.hour >= 12 ? 'PM' : 'AM';
  return '$h:$m $ap';
}

String _dayLabel(DateTime t) {
  final now   = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final dt    = DateTime(t.year, t.month, t.day);
  final diff  = today.difference(dt).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  const mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  return '${mo[t.month - 1]} ${t.day}, ${t.year}';
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

// ── Suggestion item model ──────────────────────────────────────────────────────
class _SuggestionItem {
  const _SuggestionItem(this.icon, this.text);
  final IconData icon;
  final String   text;
}

// ── Screen ─────────────────────────────────────────────────────────────────────
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.userRole});

  /// 'student' or 'organizer'
  final String userRole;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final _scrollCtrl = ScrollController();
  final _inputCtrl  = TextEditingController();
  final _inputFocus = FocusNode();

  List<ChatMessage> _messages = [];
  String? _sessionId;
  bool    _loading    = true;
  bool    _sending    = false;
  bool    _inputEmpty = true;
  String? _initError;

  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;

  List<_SuggestionItem> get _suggestions => widget.userRole == 'organizer'
      ? const [
          _SuggestionItem(Icons.add_circle_outline_rounded,  'How do I create an event?'),
          _SuggestionItem(Icons.qr_code_scanner_rounded,     'How do I scan a QR code?'),
          _SuggestionItem(Icons.camera_alt_outlined,         'What is the selfie check-in?'),
          _SuggestionItem(Icons.campaign_outlined,           'How do I post an announcement?'),
          _SuggestionItem(Icons.bar_chart_rounded,           'Where are my event stats?'),
          _SuggestionItem(Icons.delete_outline_rounded,      'How do I delete a registration?'),
        ]
      : const [
          _SuggestionItem(Icons.event_available_rounded,     'How do I register for an event?'),
          _SuggestionItem(Icons.qr_code_2_rounded,           'Where is my QR code?'),
          _SuggestionItem(Icons.how_to_reg_rounded,          'What is the check-in process?'),
          _SuggestionItem(Icons.lock_reset_rounded,          'How do I reset my password?'),
          _SuggestionItem(Icons.camera_front_outlined,       'Why is my status "Awaiting Selfie"?'),
          _SuggestionItem(Icons.history_rounded,             'Can I see my past registrations?'),
        ];

  @override
  void initState() {
    super.initState();
    _inputCtrl.addListener(
      () => setState(() => _inputEmpty = _inputCtrl.text.trim().isEmpty),
    );
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _init();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _inputCtrl.dispose();
    _inputFocus.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() { _loading = true; _initError = null; });
    try {
      final sid     = await ChatService.getOrCreateSession(userRole: widget.userRole);
      final history = await ChatService.loadHistory(sid);
      if (!mounted) return;
      setState(() {
        _sessionId = sid;
        _messages  = history;
        _loading   = false;
      });
      _scrollToBottom(instant: true);
    } catch (e) {
      if (mounted) setState(() { _loading = false; _initError = e.toString(); });
    }
  }

  Future<void> _send([String? quickText]) async {
    final text = (quickText ?? _inputCtrl.text).trim();
    if (text.isEmpty || _sessionId == null || _sending) return;

    final historySnapshot = List<ChatMessage>.from(_messages);
    _inputCtrl.clear();
    setState(() {
      _sending    = true;
      _inputEmpty = true;
      _messages.add(ChatMessage(
        id:        'temp_${DateTime.now().millisecondsSinceEpoch}',
        role:      'user',
        content:   text,
        createdAt: DateTime.now(),
      ));
    });
    _scrollToBottom();

    final result = await ChatService.chat(
      sessionId:   _sessionId!,
      userMessage: text,
      history:     historySnapshot,
      userRole:    widget.userRole,
    );

    if (!mounted) return;
    setState(() {
      _messages.removeLast();
      _messages.add(result.userMessage);
      _messages.add(result.assistantMessage);
      _sending = false;
    });
    _scrollToBottom();
  }

  Future<void> _confirmClear() async {
    if (_sessionId == null || _messages.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: _kCard,
        contentPadding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
        titlePadding: const EdgeInsets.fromLTRB(28, 28, 28, 16),
        title: const Column(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: Color(0xFFFEF2F2),
              child: Icon(Icons.auto_delete_rounded, size: 26, color: Color(0xFFEF4444)),
            ),
            SizedBox(height: 14),
            Text(
              'Clear conversation?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 17,
                color: _kText,
              ),
            ),
          ],
        ),
        content: const Text(
          'All messages will be permanently deleted.\nThis cannot be undone.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Poppins', fontSize: 13,
            color: _kSub, height: 1.65,
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kSub,
                    side: BorderSide(color: Colors.grey.shade200),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  child: const Text(
                    'Clear All',
                    style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ChatService.clearHistory(_sessionId!);
    if (mounted) setState(() => _messages.clear());
  }

  void _scrollToBottom({bool instant = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: instant ? Duration.zero : const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _loading
                  ? _buildLoadingState()
                  : _initError != null
                      ? _buildErrorState()
                      : Column(
                          children: [
                            Expanded(
                              child: _messages.isEmpty
                                  ? _buildWelcome()
                                  : _buildMessageList(),
                            ),
                            if (_sending) _buildTypingBubble(),
                          ],
                        ),
            ),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 14),
      child: Row(
        children: [
          // Back
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => Navigator.pop(context),
              borderRadius: BorderRadius.circular(12),
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: _kText),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Avatar
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              gradient: kGoldGradient,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: kGold.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 21),
          ),
          const SizedBox(width: 11),
          // Title + subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'EventHub AI',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _kText,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (child, anim) =>
                      FadeTransition(opacity: anim, child: child),
                  child: _sending
                      ? Row(
                          key: const ValueKey('typing'),
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            _MiniDots(),
                            SizedBox(width: 6),
                            Text(
                              'Typing…',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: kGold,
                              ),
                            ),
                          ],
                        )
                      : const Text(
                          'Groq AI',
                          key: ValueKey('groq'),
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: _kMuted,
                          ),
                        ),
                ),
              ],
            ),
          ),
          // Clear
          if (_messages.isNotEmpty)
            Tooltip(
              message: 'Clear chat',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _confirmClear,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      color: Color(0xFFEF4444),
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Loading ────────────────────────────────────────────────────────────────

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 68, height: 68,
            decoration: BoxDecoration(
              gradient: kGoldGradient,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: kGold.withValues(alpha: 0.35),
                  blurRadius: 20,
                  spreadRadius: 3,
                ),
              ],
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 30),
          ),
          const SizedBox(height: 22),
          const SizedBox(
            width: 26, height: 26,
            child: CircularProgressIndicator(color: kGold, strokeWidth: 2.5),
          ),
          const SizedBox(height: 14),
          const Text(
            'Starting chat…',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: _kMuted),
          ),
        ],
      ),
    );
  }

  // ── Welcome / empty state ──────────────────────────────────────────────────

  Widget _buildWelcome() {
    final isOrg = widget.userRole == 'organizer';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 24),
      child: Column(
        children: [
          // Pulsing avatar
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, __) => Container(
              width: 96, height: 96,
              decoration: BoxDecoration(
                gradient: kGoldGradient,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: kGold.withValues(alpha: 0.18 + 0.22 * _pulseAnim.value),
                    blurRadius: 22 + 16 * _pulseAnim.value,
                    spreadRadius: 2 + 5 * _pulseAnim.value,
                  ),
                ],
              ),
              child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 42),
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'EventHub AI',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: _kText,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 5),
          // Powered-by badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: kGold.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Powered by Groq AI',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: kGold,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isOrg
                ? 'Ask me anything about managing your events,\nQR scanning, or organizer tools.'
                : 'Ask me anything about events,\nregistrations, or navigating the app.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: _kSub,
              height: 1.65,
            ),
          ),
          const SizedBox(height: 36),
          // Section label
          Row(
            children: [
              Expanded(child: Divider(color: Colors.grey.shade200, height: 1)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'QUICK QUESTIONS',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                    color: _kMuted,
                  ),
                ),
              ),
              Expanded(child: Divider(color: Colors.grey.shade200, height: 1)),
            ],
          ),
          const SizedBox(height: 14),
          // Suggestion rows
          Column(
            children: _suggestions.map(_buildSuggestionRow).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionRow(_SuggestionItem item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => _send(item.text),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade100),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.035),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: kGold.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(item.icon, size: 18, color: kGold),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Text(
                    item.text,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: _kText,
                    ),
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded, size: 13, color: Colors.grey.shade400),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Message list ───────────────────────────────────────────────────────────

  Widget _buildMessageList() {
    return ListView.builder(
      controller:  _scrollCtrl,
      padding:     const EdgeInsets.fromLTRB(16, 16, 16, 8),
      itemCount:   _messages.length,
      itemBuilder: (_, i) {
        final msg  = _messages[i];
        final prev = i > 0 ? _messages[i - 1] : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (prev == null || !_sameDay(prev.createdAt, msg.createdAt))
              _buildDayDivider(msg.createdAt),
            msg.role == 'user'
                ? _buildUserBubble(msg)
                : _buildAssistantBubble(msg),
          ],
        );
      },
    );
  }

  Widget _buildDayDivider(DateTime t) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        children: [
          Expanded(child: Divider(color: Colors.grey.shade200, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: _kCard,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Text(
                _dayLabel(t),
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: _kMuted,
                ),
              ),
            ),
          ),
          Expanded(child: Divider(color: Colors.grey.shade200, height: 1)),
        ],
      ),
    );
  }

  Widget _buildUserBubble(ChatMessage msg) {
    final isTemp = msg.id.startsWith('temp_');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 54),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              gradient: kGoldGradient,
              borderRadius: BorderRadius.only(
                topLeft:     Radius.circular(20),
                topRight:    Radius.circular(20),
                bottomLeft:  Radius.circular(20),
                bottomRight: Radius.circular(5),
              ),
            ),
            child: Text(
              msg.content,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                color: Colors.white,
                height: 1.55,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isTemp) ...[
                SizedBox(
                  width: 10, height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: _kMuted.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Text(
                _msgTime(msg.createdAt),
                style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 10, color: _kMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAssistantBubble(ChatMessage msg) {
    final isErr = msg.isError;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, right: 54),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // AI avatar
          Container(
            width: 30, height: 30,
            margin: const EdgeInsets.only(right: 9, bottom: 20),
            decoration: BoxDecoration(
              gradient: isErr
                  ? const LinearGradient(
                      colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                    )
                  : kGoldGradient,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: kGold.withValues(alpha: 0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              isErr ? Icons.error_outline_rounded : Icons.auto_awesome_rounded,
              color: Colors.white,
              size: 14,
            ),
          ),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  decoration: BoxDecoration(
                    color: isErr ? const Color(0xFFFFF5F5) : _kCard,
                    borderRadius: const BorderRadius.only(
                      topLeft:     Radius.circular(5),
                      topRight:    Radius.circular(20),
                      bottomLeft:  Radius.circular(20),
                      bottomRight: Radius.circular(20),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isErr ? 0.04 : 0.07),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
                    border: isErr
                        ? Border.all(color: const Color(0xFFFECACA))
                        : null,
                  ),
                  child: Text(
                    msg.content,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      height: 1.65,
                      color: isErr ? const Color(0xFFDC2626) : _kText,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _msgTime(msg.createdAt),
                  style: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 10, color: _kMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingBubble() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 30, height: 30,
            margin: const EdgeInsets.only(right: 9),
            decoration: const BoxDecoration(gradient: kGoldGradient, shape: BoxShape.circle),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 14),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: const BorderRadius.only(
                topLeft:     Radius.circular(5),
                topRight:    Radius.circular(20),
                bottomLeft:  Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const _TypingDots(),
          ),
        ],
      ),
    );
  }

  // ── Input bar ──────────────────────────────────────────────────────────────

  Widget _buildInputBar() {
    final canSend = !_inputEmpty && !_sending && _sessionId != null;
    return Container(
      padding: EdgeInsets.fromLTRB(
        16, 10, 16, MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: _kCard,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 14,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: _kSurface,
                borderRadius: BorderRadius.circular(26),
              ),
              child: TextField(
                controller:         _inputCtrl,
                focusNode:          _inputFocus,
                maxLines:           null,
                maxLength:          600,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted:        (_) => canSend ? _send() : null,
                style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 14, color: _kText,
                ),
                decoration: InputDecoration(
                  hintText: _sending ? 'Please wait…' : 'Ask EventHub AI…',
                  hintStyle: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    color: _sending ? kGold.withValues(alpha: 0.5) : _kMuted,
                  ),
                  border:         InputBorder.none,
                  enabledBorder:  InputBorder.none,
                  focusedBorder:  InputBorder.none,
                  contentPadding: const EdgeInsets.fromLTRB(18, 13, 12, 13),
                  counterText:    '',
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 48, height: 48,
            decoration: BoxDecoration(
              gradient: canSend ? kGoldGradient : null,
              color:    canSend ? null : Colors.grey.shade100,
              shape:    BoxShape.circle,
              boxShadow: canSend
                  ? [BoxShadow(color: kGold.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 3))]
                  : null,
            ),
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                onTap:        canSend ? () => _send() : null,
                customBorder: const CircleBorder(),
                child: Icon(
                  Icons.arrow_upward_rounded,
                  size:  20,
                  color: canSend ? Colors.white : Colors.grey.shade400,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Error state ────────────────────────────────────────────────────────────

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 84, height: 84,
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(26),
              ),
              child: const Icon(Icons.cloud_off_rounded, size: 38, color: Color(0xFFEF4444)),
            ),
            const SizedBox(height: 22),
            const Text(
              'Chat unavailable',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: _kText,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _initError ?? 'An unexpected error occurred.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 13,
                color: _kSub, height: 1.55,
              ),
            ),
            const SizedBox(height: 26),
            ElevatedButton.icon(
              onPressed: _init,
              icon:  const Icon(Icons.refresh_rounded, size: 17),
              label: const Text(
                'Try again',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 14),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: kGold,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Mini dots — header typing indicator ───────────────────────────────────────

class _MiniDots extends StatefulWidget {
  const _MiniDots();

  @override
  State<_MiniDots> createState() => _MiniDotsState();
}

class _MiniDotsState extends State<_MiniDots> with TickerProviderStateMixin {
  late final List<AnimationController> _ctrls;
  late final List<Animation<double>>   _anims;

  @override
  void initState() {
    super.initState();
    _ctrls = List.generate(
      3,
      (_) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 380),
      ),
    );
    _anims = _ctrls
        .map((c) => Tween<double>(begin: 0, end: -4).animate(
              CurvedAnimation(parent: c, curve: Curves.easeInOut),
            ))
        .toList();
    _stagger();
  }

  Future<void> _stagger() async {
    for (var i = 0; i < 3; i++) {
      await Future.delayed(Duration(milliseconds: i * 130));
      if (mounted) _ctrls[i].repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        3,
        (i) => AnimatedBuilder(
          animation: _anims[i],
          builder: (_, __) => Transform.translate(
            offset: Offset(0, _anims[i].value),
            child: Container(
              width: 4, height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: const BoxDecoration(color: kGold, shape: BoxShape.circle),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Animated typing dots — chat bubble ────────────────────────────────────────

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with TickerProviderStateMixin {
  late final List<AnimationController> _ctrls;
  late final List<Animation<double>>   _anims;

  @override
  void initState() {
    super.initState();
    _ctrls = List.generate(
      3,
      (_) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 480),
      ),
    );
    _anims = _ctrls
        .map((c) => Tween<double>(begin: 0, end: -7).animate(
              CurvedAnimation(parent: c, curve: Curves.easeInOut),
            ))
        .toList();
    _stagger();
  }

  Future<void> _stagger() async {
    for (var i = 0; i < 3; i++) {
      await Future.delayed(Duration(milliseconds: i * 170));
      if (mounted) _ctrls[i].repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        3,
        (i) => AnimatedBuilder(
          animation: _anims[i],
          builder: (_, __) => Transform.translate(
            offset: Offset(0, _anims[i].value),
            child: Container(
              width: 7, height: 7,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: const BoxDecoration(color: kGold, shape: BoxShape.circle),
            ),
          ),
        ),
      ),
    );
  }
}
