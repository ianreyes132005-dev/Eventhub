import 'dart:math';
import 'package:flutter/foundation.dart';
import '../friendly_error.dart';
import 'supabase_service.dart';

// ── Data models ───────────────────────────────────────────────────────────────

String _cleanAssistantText(String value) {
  return value
      .replaceAll(
        RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
        ' ',
      )
      .replaceAll(RegExp(r'<\/?think>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<\|[^|]{1,48}\|>'), ' ')
      .replaceAll(RegExp(r'â€™|â€˜|â\u0092|â\u0098'), "'")
      .replaceAll(RegExp(r'â€œ|â€�|â€|â€|â\u0093|â\u0094'), '"')
      .replaceAll(RegExp(r'â€“|â€”|â\u0096|â\u0097'), '-')
      .replaceAll('â€¦', '...')
      .replaceAll('â€¢', '-')
      .replaceAll(
        RegExp(r'J(?:â[\u0080-\u00BF\uFFFD]*|�)Jireh', caseSensitive: false),
        'J-Jireh',
      )
      .replaceAll('**', '')
      .replaceAllMapped(RegExp(r'__([^_]+)__'), (match) => match[1] ?? '')
      .replaceAll(RegExp(r'`{1,3}'), '')
      .replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true), '')
      .replaceAllMapped(
        RegExp(r'\[([^\]]+)\]\([^)]+\)'),
        (match) => match[1] ?? '',
      )
      .replaceAll(RegExp(r'(?:â[\u0080-\u00BF\uFFFD]+|ï¿½|�)'), ' ')
      .replaceAll(
        RegExp(
          r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F\u200B-\u200F\u202A-\u202E\u2060-\u206F\uFFFD]',
        ),
        ' ',
      )
      .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

class ChatMessage {
  final String   id;
  final String   role;       // 'user' | 'assistant'
  final String   content;
  final DateTime createdAt;
  final bool     isError;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.isError = false,
  });

  factory ChatMessage.fromRow(Map<String, dynamic> row) {
    final role = row['role'] as String;
    final content = row['content'] as String;
    return ChatMessage(
      id: row['id'] as String,
      role: role,
      content: role == 'assistant' ? _cleanAssistantText(content) : content,
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
    );
  }

  Map<String, dynamic> toApiMap() => {'role': role, 'content': content};
}

class ChatResult {
  final ChatMessage userMessage;
  final ChatMessage assistantMessage;
  const ChatResult({required this.userMessage, required this.assistantMessage});
}

// ── Service ───────────────────────────────────────────────────────────────────

class ChatService {
  // How many prior messages to include in each API call.
  static const _maxCtx = 20;

  static const _sessionMaxAgeDays = 7;

  static Future<String> getOrCreateSession({String userRole = 'student'}) async {
    final user = SupabaseService.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final cutoff = DateTime.now()
        .toUtc()
        .subtract(const Duration(days: _sessionMaxAgeDays))
        .toIso8601String();

    final existing = await SupabaseService.client
        .from('chat_sessions')
        .select('id')
        .eq('user_id', user.id)
        .gte('created_at', cutoff)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (existing != null) return existing['id'] as String;

    final created = await SupabaseService.client
        .from('chat_sessions')
        .insert({'user_id': user.id, 'user_role': userRole})
        .select('id')
        .single();

    return created['id'] as String;
  }

  static Future<List<ChatMessage>> loadHistory(
    String sessionId, {
    int limit = 100,
  }) async {
    // Fetch the most recent [limit] messages (newest first, so the cutoff
    // lands on the oldest ones), then reverse back to chronological order
    // for display.
    final rows = await SupabaseService.client
        .from('chat_messages')
        .select()
        .eq('session_id', sessionId)
        .order('created_at', ascending: false)
        .limit(limit);

    final messages = (rows as List)
        .map((r) => ChatMessage.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
    return messages.reversed.toList();
  }

  static Future<ChatResult> chat({
    required String            sessionId,
    required String            userMessage,
    required List<ChatMessage> history,
    required String            userRole,
  }) async {
    final userMsg = await _insertMessage(sessionId, 'user', userMessage);

    final start   = max(0, history.length - (_maxCtx - 1));
    final allMsgs = [...history.sublist(start), userMsg];

    String assistantText;
    try {
      assistantText = _cleanAssistantText(
        await _callEdgeFn(allMsgs, userRole),
      );
    } catch (e) {
      debugPrint('[ChatService] Edge function error: $e');
      final reason = friendlyError(e, fallback: 'Please try again in a moment.');
      return ChatResult(
        userMessage: userMsg,
        assistantMessage: ChatMessage(
          id:        'err_${DateTime.now().millisecondsSinceEpoch}',
          role:      'assistant',
          content:   'Sorry, I couldn’t answer that just now.\n\n$reason',
          createdAt: DateTime.now(),
          isError:   true,
        ),
      );
    }

    final assistantMsg = await _insertMessage(sessionId, 'assistant', assistantText);
    return ChatResult(userMessage: userMsg, assistantMessage: assistantMsg);
  }

  static Future<void> clearHistory(String sessionId) async {
    await SupabaseService.client
        .from('chat_messages')
        .delete()
        .eq('session_id', sessionId);
  }

  static Future<String> _callEdgeFn(
    List<ChatMessage> messages,
    String userRole,
  ) async {
    final res = await SupabaseService.client.functions.invoke(
      'ai-chat',
      body: {
        'messages': messages.map((m) => m.toApiMap()).toList(),
        'userRole': userRole,
        // Lets the assistant word answers for the screen in use.
        'platform': kIsWeb ? 'web' : 'mobile',
      },
    );

    final data = res.data;
    if (res.status != 200) {
      // 404 = the ai-chat Edge Function was never deployed.
      if (res.status == 404) {
        throw const FriendlyException(
            'The AI assistant isn’t set up yet. Please contact the system administrator.');
      }
      if (data is Map<String, dynamic>) _throwFromEdgeError(data);
      throw const FriendlyException(
          'The AI assistant isn’t responding right now. Please try again in a moment.');
    }

    if (data is Map<String, dynamic> && data.containsKey('text')) {
      return data['text'] as String? ?? '';
    }
    throw const FriendlyException(
        'The AI assistant sent an unexpected reply. Please try again.');
  }

  static Never _throwFromEdgeError(Map<String, dynamic> data) {
    final code = data['error'] as String? ?? '';
    final msg  = data['message'] as String?;

    switch (code) {
      case 'rate_limited':
        final retry = data['retryAfter'];
        throw Exception(retry != null
            ? 'The AI is busy right now — please wait $retry seconds and try again.'
            : 'Too many requests — please wait a moment and try again.');

      case 'quota_exceeded':
        throw Exception(
          msg ?? 'You\'ve reached your daily message limit. Come back tomorrow!',
        );

      case 'unauthorized':
        throw Exception('Your session has expired. Please log in again.');

      case 'config_error':
        throw Exception(
          'The AI service is not available right now. Contact your administrator.',
        );

      default:
        // The function's own messages are readable; server dumps aren't.
        throw FriendlyException(friendlyError(msg,
            fallback: 'The AI assistant ran into a problem. Please try again.'));
    }
  }

  static Future<ChatMessage> _insertMessage(
    String sessionId,
    String role,
    String content,
  ) async {
    final row = await SupabaseService.client
        .from('chat_messages')
        .insert({'session_id': sessionId, 'role': role, 'content': content})
        .select()
        .single();
    return ChatMessage.fromRow(Map<String, dynamic>.from(row as Map));
  }
}
