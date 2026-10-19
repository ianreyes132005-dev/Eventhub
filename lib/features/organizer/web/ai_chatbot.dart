import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/app_colors.dart';
import '../../../core/services/chat_service.dart';
import '../../../shared/widgets/web/web_alert.dart';
import '../../../shared/widgets/error_alert.dart';
import 'web_layout.dart' show WebTk;

// ── Suggestion model ──────────────────────────────────────────────────────────
class _SuggestionItem {
  const _SuggestionItem(this.icon, this.text);
  final IconData icon;
  final String   text;
}

const List<_SuggestionItem> _kOrgSuggestions = [
  _SuggestionItem(Icons.add_circle_outline_rounded, 'How do I create an event?'),
  _SuggestionItem(Icons.hourglass_top_rounded,      'Why is my event still pending?'),
  _SuggestionItem(Icons.how_to_reg_rounded,         'How do I check students in?'),
  _SuggestionItem(Icons.download_rounded,           'How do I export attendance?'),
  _SuggestionItem(Icons.event_busy_rounded,         'How do I cancel an event?'),
  _SuggestionItem(Icons.campaign_outlined,          'How do I post an announcement?'),
];

// ── Root widget ───────────────────────────────────────────────────────────────

class WebAiChatbot extends StatefulWidget {
  final String? orgId;
  const WebAiChatbot({super.key, this.orgId});

  @override
  State<WebAiChatbot> createState() => _WebAiChatbotState();
}

class _WebAiChatbotState extends State<WebAiChatbot>
    with SingleTickerProviderStateMixin {
  bool    _open         = false;
  bool    _loading      = false;
  bool    _sessionError = false;
  bool    _sending      = false;
  String? _sessionId;

  final _msgCtrl = TextEditingController();
  final _scroll  = ScrollController();
  final List<ChatMessage> _history = [];

  late final AnimationController _anim;
  late final Animation<double>   _scale;
  late final Animation<double>   _fade;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _scale = CurvedAnimation(parent: _anim, curve: Curves.easeOutBack);
    _fade  = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _anim.dispose();
    _msgCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _openChat() async {
    setState(() => _open = true);
    _anim.forward();
    if (_sessionId != null) return;
    await _loadSession();
  }

  Future<void> _loadSession() async {
    setState(() { _loading = true; _sessionError = false; });
    try {
      final sid     = await ChatService.getOrCreateSession(userRole: 'organizer');
      final history = await ChatService.loadHistory(sid);
      if (mounted) {
        setState(() {
          _sessionId = sid;
          _history.addAll(history);
          _loading   = false;
        });
        _scrollToBottom();
      }
    } catch (_) {
      if (mounted) setState(() { _loading = false; _sessionError = true; });
    }
  }

  void _closeChat() {
    _anim.reverse().then((_) {
      if (mounted) setState(() => _open = false);
    });
  }

  // Accepts an optional [quickText] so suggestion chips can bypass the field.
  Future<void> _send([String? quickText]) async {
    final text = (quickText ?? _msgCtrl.text).trim();
    if (text.isEmpty || _sending || _sessionId == null) return;
    if (quickText == null) _msgCtrl.clear();
    final history = List<ChatMessage>.from(_history);
    final pendingMessage = ChatMessage(
      id: 'pending_${DateTime.now().microsecondsSinceEpoch}',
      role: 'user',
      content: text,
      createdAt: DateTime.now(),
    );
    setState(() {
      _sending = true;
      _history.add(pendingMessage);
    });
    _scrollToBottom();

    try {
      final result = await ChatService.chat(
        sessionId:   _sessionId!,
        userMessage: text,
        history:     history,
        userRole:    'organizer',
      );
      if (mounted) {
        setState(() {
          final pendingIndex =
              _history.indexWhere((message) => message.id == pendingMessage.id);
          if (pendingIndex >= 0) {
            _history[pendingIndex] = result.userMessage;
          }
          _history.add(result.assistantMessage);
          _sending = false;
        });
        _scrollToBottom();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _history.add(ChatMessage(
            id:        'err_${DateTime.now().millisecondsSinceEpoch}',
            role:      'assistant',
            content:   'Something went wrong. Please try again.',
            createdAt: DateTime.now(),
            isError:   true,
          ));
          _sending = false;
        });
        _scrollToBottom();
      }
    }
  }

  Future<void> _clear() async {
    if (_sessionId == null) return;
    final ok = await WebAlert.confirm(
      context: context,
      title: 'Clear conversation?',
      message: 'All messages will be permanently deleted. This cannot be undone.',
      confirmLabel: 'Clear All',
    );
    if (ok != true || !mounted) return;
    try {
      await ChatService.clearHistory(_sessionId!);
      if (mounted) setState(() => _history.clear());
    } catch (e) {
      if (mounted) {
        showErrorAlert(context, e,
            title: 'Couldn’t clear the conversation',
            fallback: 'The chat history couldn’t be cleared. Please try again.');
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 24,
      bottom: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_open)
            FadeTransition(
              opacity: _fade,
              child: ScaleTransition(
                scale: _scale,
                alignment: Alignment.bottomRight,
                child: _ChatPanel(
                  loading:      _loading,
                  sessionError: _sessionError,
                  sending:      _sending,
                  history:      _history,
                  scroll:       _scroll,
                  msgCtrl:      _msgCtrl,
                  onSend:       _send,
                  onSendText:   _send,
                  onClose:      _closeChat,
                  onClear:      _clear,
                  onRetry:      _loadSession,
                ),
              ),
            ),
          const SizedBox(height: 12),
          _ChatFab(
            open:  _open,
            onTap: _open ? _closeChat : _openChat,
          ),
        ],
      ),
    );
  }
}

// ── AI Bot Logo ───────────────────────────────────────────────────────────────

class _AiBotLogo extends StatelessWidget {
  final double size;
  const _AiBotLogo({this.size = 36});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: kGoldGradient,
      boxShadow: [
        BoxShadow(
          color: kGold.withValues(alpha: 0.30),
          blurRadius: size * 0.28,
          offset: Offset(0, size * 0.08),
        ),
      ],
    ),
    child: Icon(Icons.auto_awesome_rounded, color: Colors.white, size: size * 0.48),
  );
}

// ── Chat panel ────────────────────────────────────────────────────────────────

class _ChatPanel extends StatelessWidget {
  final bool                  loading;
  final bool                  sessionError;
  final bool                  sending;
  final List<ChatMessage>     history;
  final ScrollController      scroll;
  final TextEditingController msgCtrl;
  final VoidCallback          onSend;
  final ValueChanged<String>  onSendText;   // for suggestion chips
  final VoidCallback          onClose;
  final VoidCallback          onClear;
  final VoidCallback          onRetry;

  const _ChatPanel({
    required this.loading,
    required this.sessionError,
    required this.sending,
    required this.history,
    required this.scroll,
    required this.msgCtrl,
    required this.onSend,
    required this.onSendText,
    required this.onClose,
    required this.onClear,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return Material(
    elevation: 0,
    borderRadius: BorderRadius.circular(20),
    clipBehavior: Clip.antiAlias,
    child: Container(
      width: 364,
      height: 540,
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: t.dark ? 0.40 : 0.13),
            blurRadius: 30,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildHeader(t),
          Expanded(child: _buildBody(t)),
          _buildInput(t),
        ],
      ),
    ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader(WebTk t) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
    decoration: BoxDecoration(
      color: t.card,
      boxShadow: [
        BoxShadow(
          color: t.shadow,
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Row(
      children: [
        const _AiBotLogo(size: 36),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'EventHub AI',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: t.text,
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, anim) =>
                    FadeTransition(opacity: anim, child: child),
                child: sending
                    ? Row(
                        key: const ValueKey('typing'),
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          _MiniDots(),
                          SizedBox(width: 5),
                          Text(
                            'Typing…',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: kGold,
                            ),
                          ),
                        ],
                      )
                    : Text(
                        'Groq AI',
                        key: const ValueKey('groq'),
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: t.muted,
                        ),
                      ),
              ),
            ],
          ),
        ),
        // Clear button
        Tooltip(
          message: 'Clear chat',
          child: GestureDetector(
            onTap: onClear,
            child: Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.delete_outline_rounded,
                color: Color(0xFFEF4444),
                size: 16,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        // Close button
        Tooltip(
          message: 'Close',
          child: GestureDetector(
            onTap: onClose,
            child: Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: t.divider,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.close_rounded, color: t.sub, size: 16),
            ),
          ),
        ),
      ],
    ),
  );

  // ── Body (messages / welcome / loading / error) ───────────────────────────

  Widget _buildBody(WebTk t) {
    if (loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _AiBotLogo(size: 54),
            const SizedBox(height: 18),
            const SizedBox(
              width: 22, height: 22,
              child: CircularProgressIndicator(color: kGold, strokeWidth: 2),
            ),
            const SizedBox(height: 12),
            Text(
              'Starting chat…',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: t.muted),
            ),
          ],
        ),
      );
    }

    if (sessionError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 54, height: 54,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.cloud_off_rounded,
                    color: Color(0xFFEF4444), size: 26),
              ),
              const SizedBox(height: 14),
              Text(
                'Could not connect',
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 13,
                  fontWeight: FontWeight.w600, color: t.text,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Check your connection and try again.',
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 11.5,
                  color: t.sub, height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 15, color: kGold),
                label: const Text(
                  'Retry',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 12,
                    fontWeight: FontWeight.w600, color: kGold,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (history.isEmpty) return _buildWelcome(t);

    return ListView.builder(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      itemCount: history.length + (sending ? 1 : 0),
      itemBuilder: (_, i) {
        if (sending && i == history.length) return const _TypingBubble();
        return _MessageBubble(msg: history[i]);
      },
    );
  }

  // ── Welcome / empty state with suggestions ────────────────────────────────

  Widget _buildWelcome(WebTk t) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(16, 22, 16, 16),
    child: Column(
      children: [
        // Avatar
        const _AiBotLogo(size: 60),
        const SizedBox(height: 14),
        // Title
        Text(
          'EventHub AI',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: t.text,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 5),
        // Powered-by badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: kGold.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text(
            'Powered by Groq AI',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: kGold,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'I answer questions about using EventHub:\nevents, check-in, announcements and more.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 11.5,
            color: t.sub,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 20),
        // Section divider label
        Row(
          children: [
            Expanded(child: Divider(color: t.border, height: 1)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                'QUICK QUESTIONS',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                  color: t.muted,
                ),
              ),
            ),
            Expanded(child: Divider(color: t.border, height: 1)),
          ],
        ),
        const SizedBox(height: 12),
        // Suggestion rows
        ..._kOrgSuggestions.map((item) => _SuggestionRow(
          item:      item,
          onTap:     () => onSendText(item.text),
        )),
      ],
    ),
  );

  // ── Input bar ─────────────────────────────────────────────────────────────

  Widget _buildInput(WebTk t) => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
    decoration: BoxDecoration(
      color: t.card,
      boxShadow: [
        BoxShadow(
          color: t.shadow,
          blurRadius: 10,
          offset: const Offset(0, -2),
        ),
      ],
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Container(
            constraints: const BoxConstraints(maxHeight: 100),
            decoration: BoxDecoration(
              color: t.inputBg,
              borderRadius: BorderRadius.circular(22),
            ),
            child: TextField(
              controller: msgCtrl,
              onSubmitted: (_) => onSend(),
              maxLines: null,
              maxLength: 600,
              style: TextStyle(
                fontFamily: 'Poppins', fontSize: 12.5, color: t.text,
              ),
              decoration: InputDecoration(
                hintText: 'Ask EventHub AI…',
                hintStyle: TextStyle(
                  fontFamily: 'Poppins', fontSize: 12.5, color: t.muted,
                ),
                contentPadding: const EdgeInsets.fromLTRB(16, 11, 12, 11),
                border:        InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                counterText:   '',
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _SendBtn(onTap: onSend, sending: sending),
      ],
    ),
  );
}

// ── Suggestion row ────────────────────────────────────────────────────────────

class _SuggestionRow extends StatefulWidget {
  final _SuggestionItem item;
  final VoidCallback    onTap;
  const _SuggestionRow({required this.item, required this.onTap});

  @override
  State<_SuggestionRow> createState() => _SuggestionRowState();
}

class _SuggestionRowState extends State<_SuggestionRow> {
  bool _h = false;

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _h = true),
      onExit:  (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: _h ? kGold.withValues(alpha: 0.04) : t.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _h
                  ? kGold.withValues(alpha: 0.22)
                  : t.border,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                    alpha: t.dark ? (_h ? 0.15 : 0.30) : (_h ? 0.02 : 0.04)),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: kGold.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(widget.item.icon, size: 16, color: kGold),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  widget.item.text,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: t.text,
                  ),
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded,
                  size: 11, color: t.muted),
            ],
          ),
        ),
      ),
    ),
    );
  }
}

// ── Message bubble ────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final ChatMessage msg;
  const _MessageBubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final t      = WebTk(Theme.of(context).brightness == Brightness.dark);
    final isUser = msg.role == 'user';
    final isErr  = msg.isError;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            const _AiBotLogo(size: 28),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              decoration: BoxDecoration(
                gradient: isUser ? kGoldGradient : null,
                color: isUser
                    ? null
                    : isErr
                        ? const Color(0xFFFFF5F5)
                        : t.card,
                borderRadius: BorderRadius.only(
                  topLeft:     const Radius.circular(18),
                  topRight:    const Radius.circular(18),
                  bottomLeft:  Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
                border: isErr
                    ? Border.all(color: const Color(0xFFFECACA))
                    : !isUser
                        ? Border.all(color: t.border)
                        : null,
                boxShadow: isUser
                    ? [
                        BoxShadow(
                          color: kGold.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: isErr
                              ? Colors.black.withValues(alpha: 0.04)
                              : t.shadow,
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Text(
                msg.content,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12.5,
                  color: isUser
                      ? Colors.white
                      : isErr
                          ? const Color(0xFFDC2626)
                          : t.text,
                  height: 1.5,
                ),
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 4),
        ],
      ),
    );
  }
}

// ── Typing bubble ─────────────────────────────────────────────────────────────

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const _AiBotLogo(size: 28),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: const BorderRadius.only(
              topLeft:     Radius.circular(4),
              topRight:    Radius.circular(18),
              bottomRight: Radius.circular(18),
              bottomLeft:  Radius.circular(18),
            ),
            border: Border.all(color: t.border),
            boxShadow: [
              BoxShadow(
                color: t.shadow,
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Dot(delay: 0),
              const SizedBox(width: 4),
              _Dot(delay: 170),
              const SizedBox(width: 4),
              _Dot(delay: 340),
            ],
          ),
        ),
      ],
    ),
    );
  }
}

class _Dot extends StatefulWidget {
  final int delay;
  const _Dot({required this.delay});

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _anim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, _) => Transform.translate(
      offset: Offset(0, -5 * _anim.value),
      child: Container(
        width: 7, height: 7,
        decoration: BoxDecoration(
          color: kGold.withValues(alpha: 0.50 + 0.50 * _anim.value),
          shape: BoxShape.circle,
        ),
      ),
    ),
  );
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
    for (final c in _ctrls) { c.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: List.generate(
      3,
      (i) => AnimatedBuilder(
        animation: _anims[i],
        builder: (_, _) => Transform.translate(
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

// ── Send button ───────────────────────────────────────────────────────────────

class _SendBtn extends StatefulWidget {
  final VoidCallback onTap;
  final bool         sending;
  const _SendBtn({required this.onTap, required this.sending});

  @override
  State<_SendBtn> createState() => _SendBtnState();
}

class _SendBtnState extends State<_SendBtn> {
  bool _h = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _h = true),
    onExit:  (_) => setState(() => _h = false),
    child: GestureDetector(
      onTap: widget.sending ? null : widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        width: 44, height: 44,
        decoration: BoxDecoration(
          gradient: widget.sending
              ? null
              : LinearGradient(
                  colors: _h
                    ? [const Color(0xFFB8892A), kGold]
                    : [const Color(0xFFC49230), kGold],
                  begin: Alignment.topLeft,
                  end:   Alignment.bottomRight,
                ),
          color: widget.sending ? Colors.grey.shade100 : null,
          shape: BoxShape.circle,
          boxShadow: widget.sending
              ? null
              : [
                  BoxShadow(
                    color: kGold.withValues(alpha: _h ? 0.40 : 0.22),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
        ),
        child: widget.sending
            ? Padding(
                padding: const EdgeInsets.all(13),
                child: CircularProgressIndicator(
                  color: Colors.grey.shade400, strokeWidth: 2,
                ))
            : const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20),
      ),
    ),
  );
}

// ── FAB ───────────────────────────────────────────────────────────────────────

class _ChatFab extends StatefulWidget {
  final bool         open;
  final VoidCallback onTap;
  const _ChatFab({required this.open, required this.onTap});

  @override
  State<_ChatFab> createState() => _ChatFabState();
}

class _ChatFabState extends State<_ChatFab> with SingleTickerProviderStateMixin {
  bool   _h        = false;
  bool   _expanded = true;
  Timer? _timer;

  late final AnimationController _labelCtrl;
  late final Animation<double>   _labelFade;
  late final Animation<double>   _labelSlide;

  @override
  void initState() {
    super.initState();
    _labelCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    )..forward();
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
    final isOpen       = widget.open;
    final showExpanded = _expanded && !isOpen;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _h = true),
      onExit:  (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: () {
          if (showExpanded) {
            _timer?.cancel();
            _startCollapse();
          }
          widget.onTap();
        },
        child: Tooltip(
          message: isOpen ? 'Close assistant' : 'Ask AI Assistant',
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeInOut,
            height: 52,
            width: showExpanded ? 202 : 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: LinearGradient(
                colors: _h
                  ? [const Color(0xFF241A0C), const Color(0xFFB8892A)]
                  : [const Color(0xFF1E1408), kGold],
                begin: Alignment.topLeft,
                end:   Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: kGold.withValues(alpha: _h ? 0.50 : 0.32),
                  blurRadius: _h ? 22 : 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            clipBehavior: Clip.hardEdge,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: isOpen
                  ? const Center(
                      key: ValueKey('close'),
                      child: Icon(Icons.keyboard_arrow_down_rounded,
                          color: Colors.white, size: 26),
                    )
                  : Row(
                      key: const ValueKey('logo'),
                      mainAxisSize: MainAxisSize.max,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 52,
                          child: Center(
                            child: Icon(Icons.auto_awesome_rounded,
                                color: Colors.white, size: 24),
                          ),
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
          ),
        ),
      ),
    );
  }
}
