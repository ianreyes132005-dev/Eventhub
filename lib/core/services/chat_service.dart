import 'dart:math';
import 'package:flutter/foundation.dart';
import 'supabase_service.dart';

// ── Data models ───────────────────────────────────────────────────────────────

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

  factory ChatMessage.fromRow(Map<String, dynamic> row) => ChatMessage(
    id:        row['id']        as String,
    role:      row['role']      as String,
    content:   row['content']   as String,
    createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
  );

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
    final rows = await SupabaseService.client
        .from('chat_messages')
        .select()
        .eq('session_id', sessionId)
        .order('created_at', ascending: true)
        .limit(limit);

    return (rows as List)
        .map((r) => ChatMessage.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
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
      assistantText = await _callEdgeFn(allMsgs, userRole);
    } catch (e) {
      debugPrint('[ChatService] Edge function error: $e');
      final detail = e.toString().replaceFirst('Exception: ', '');
      return ChatResult(
        userMessage: userMsg,
        assistantMessage: ChatMessage(
          id:        'err_${DateTime.now().millisecondsSinceEpoch}',
          role:      'assistant',
          content:   'Could not reach the AI service.\n\nReason: $detail',
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
      },
    );

    final data = res.data;
    if (res.status != 200) {
      if (data is Map<String, dynamic>) _throwFromEdgeError(data);
      throw Exception('AI service returned status ${res.status}. Please try again.');
    }

    if (data is Map<String, dynamic> && data.containsKey('text')) {
      return data['text'] as String? ?? '';
    }
    throw Exception('Unexpected response from AI service.');
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
        throw Exception(msg ?? 'AI service error. Please try again.');
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
