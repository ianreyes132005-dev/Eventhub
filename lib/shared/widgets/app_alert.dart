import 'package:flutter/material.dart';

// ── Alert type ─────────────────────────────────────────────────────────────────
enum AlertType { success, error, warning, info, confirm }

// ─────────────────────────────────────────────────────────────────────────────
// AppAlert
// SweetAlert-style dialogs with entrance animation. All methods are static.
//
//   AppAlert.success(context, title: 'Done!', message: 'Event published.');
//   AppAlert.error(context, title: 'Failed', message: 'Something went wrong.');
//   AppAlert.warning(context, title: 'Heads up', message: '…', actionText: 'Open Settings', onAction: () => …);
//   AppAlert.confirm(context, title: 'Delete?', message: '…', onConfirm: () => …);
// ─────────────────────────────────────────────────────────────────────────────
class AppAlert {
  AppAlert._();

  static Future<void> success(
    BuildContext context, {
    required String title,
    required String message,
    String buttonText = 'Got it',
    VoidCallback? onDismiss,
  }) =>
      _show(
        context,
        type: AlertType.success,
        title: title,
        message: message,
        confirmText: buttonText,
        onConfirm: onDismiss,
      );

  static Future<void> error(
    BuildContext context, {
    required String title,
    required String message,
    String buttonText = 'Close',
    VoidCallback? onDismiss,
  }) =>
      _show(
        context,
        type: AlertType.error,
        title: title,
        message: message,
        confirmText: buttonText,
        onConfirm: onDismiss,
      );

  static Future<void> warning(
    BuildContext context, {
    required String title,
    required String message,
    String buttonText = 'OK',
    VoidCallback? onDismiss,
    String? actionText,
    VoidCallback? onAction,
  }) =>
      _show(
        context,
        type: AlertType.warning,
        title: title,
        message: message,
        confirmText: buttonText,
        onConfirm: onDismiss,
        actionText: actionText,
        onAction: onAction,
      );

  static Future<void> info(
    BuildContext context, {
    required String title,
    required String message,
    String buttonText = 'Got it',
    VoidCallback? onDismiss,
  }) =>
      _show(
        context,
        type: AlertType.info,
        title: title,
        message: message,
        confirmText: buttonText,
        onConfirm: onDismiss,
      );

  /// Confirm dialog — shows Cancel + coloured Confirm buttons.
  /// [onConfirm] is only called when the user taps the confirm button.
  /// Pass [icon] and [iconColor] to override the default red trash-bin
  /// appearance for non-destructive confirmations.
  static Future<void> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = 'Confirm',
    String cancelText  = 'Cancel',
    Color?    confirmColor,
    IconData? icon,
    Color?    iconColor,
    required VoidCallback onConfirm,
  }) =>
      _show(
        context,
        type: AlertType.confirm,
        title: title,
        message: message,
        confirmText: confirmText,
        cancelText: cancelText,
        confirmColor: confirmColor,
        onConfirm: onConfirm,
        iconOverride:      icon,
        iconColorOverride: iconColor,
      );

  // ── Core ─────────────────────────────────────────────────────────────────────

  static Future<void> _show(
    BuildContext context, {
    required AlertType   type,
    required String      title,
    required String      message,
    required String      confirmText,
    String?              cancelText,
    Color?               confirmColor,
    VoidCallback?        onConfirm,
    String?              actionText,
    VoidCallback?        onAction,
    IconData?            iconOverride,
    Color?               iconColorOverride,
  }) =>
      showDialog<void>(
        context: context,
        barrierDismissible: type != AlertType.confirm,
        builder: (_) => _AppAlertDialog(
          type:              type,
          title:             title,
          message:           message,
          confirmText:       confirmText,
          cancelText:        cancelText,
          confirmColor:      confirmColor,
          onConfirm:         onConfirm,
          actionText:        actionText,
          onAction:          onAction,
          iconOverride:      iconOverride,
          iconColorOverride: iconColorOverride,
        ),
      );
}

// ── Dialog widget ──────────────────────────────────────────────────────────────

class _AppAlertDialog extends StatefulWidget {
  const _AppAlertDialog({
    required this.type,
    required this.title,
    required this.message,
    required this.confirmText,
    this.cancelText,
    this.confirmColor,
    this.onConfirm,
    this.actionText,
    this.onAction,
    this.iconOverride,
    this.iconColorOverride,
  });

  final AlertType     type;
  final String        title;
  final String        message;
  final String        confirmText;
  final String?       cancelText;
  final Color?        confirmColor;
  final VoidCallback? onConfirm;
  final String?       actionText;
  final VoidCallback? onAction;
  final IconData?     iconOverride;
  final Color?        iconColorOverride;

  @override
  State<_AppAlertDialog> createState() => _AppAlertDialogState();
}

class _AppAlertDialogState extends State<_AppAlertDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _scale;
  late Animation<double>   _fade;

  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _scale = Tween<double>(begin: 0.80, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
    _fade  = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  // ── Type palette ─────────────────────────────────────────────────────────────

  Color get _iconBg {
    if (widget.iconColorOverride != null) {
      return widget.iconColorOverride!.withValues(alpha: 0.1);
    }
    switch (widget.type) {
      case AlertType.success: return const Color(0xFFF0FDF4);
      case AlertType.error:   return const Color(0xFFFEF2F2);
      case AlertType.warning: return const Color(0xFFFFFBEB);
      case AlertType.info:    return const Color(0xFFEFF6FF);
      case AlertType.confirm: return const Color(0xFFFEF2F2);
    }
  }

  Color get _iconColor {
    if (widget.iconColorOverride != null) return widget.iconColorOverride!;
    switch (widget.type) {
      case AlertType.success: return const Color(0xFF22C55E);
      case AlertType.error:   return const Color(0xFFEF4444);
      case AlertType.warning: return const Color(0xFFF59E0B);
      case AlertType.info:    return const Color(0xFF3B82F6);
      case AlertType.confirm: return const Color(0xFFEF4444);
    }
  }

  Color get _ringColor {
    if (widget.iconColorOverride != null) return widget.iconColorOverride!;
    switch (widget.type) {
      case AlertType.success: return const Color(0xFF22C55E);
      case AlertType.error:   return const Color(0xFFEF4444);
      case AlertType.warning: return const Color(0xFFF59E0B);
      case AlertType.info:    return const Color(0xFF3B82F6);
      case AlertType.confirm: return const Color(0xFFEF4444);
    }
  }

  IconData get _icon {
    if (widget.iconOverride != null) return widget.iconOverride!;
    switch (widget.type) {
      case AlertType.success: return Icons.check_circle_rounded;
      case AlertType.error:   return Icons.cancel_rounded;
      case AlertType.warning: return Icons.warning_amber_rounded;
      case AlertType.info:    return Icons.info_rounded;
      case AlertType.confirm: return Icons.delete_rounded;
    }
  }

  Color get _confirmBtnColor {
    if (widget.confirmColor != null) return widget.confirmColor!;
    switch (widget.type) {
      case AlertType.success: return const Color(0xFF22C55E);
      case AlertType.error:   return const Color(0xFFEF4444);
      case AlertType.warning: return const Color(0xFFF59E0B);
      case AlertType.info:    return const Color(0xFF3B82F6);
      case AlertType.confirm: return const Color(0xFFEF4444);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasCancel = widget.cancelText != null;

    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(
        scale: _scale,
        child: Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 32, 28, 26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Icon badge ──────────────────────────────────────────────
                Container(
                  width: 82, height: 82,
                  decoration: BoxDecoration(
                    color: _iconBg,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _ringColor.withValues(alpha: 0.22),
                      width: 2,
                    ),
                  ),
                  child: Icon(_icon, size: 42, color: _iconColor),
                ),
                const SizedBox(height: 20),
                // ── Title ───────────────────────────────────────────────────
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A1A1A),
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 10),
                // ── Message ─────────────────────────────────────────────────
                Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    height: 1.65,
                  ),
                ),
                const SizedBox(height: 28),
                // ── Buttons ─────────────────────────────────────────────────
                if (hasCancel)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.grey.shade600,
                            side: BorderSide(color: Colors.grey.shade200),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(
                            widget.cancelText!,
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            widget.onConfirm?.call();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _confirmBtnColor,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(
                            widget.confirmText,
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                else ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onConfirm?.call();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _confirmBtnColor,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                      child: Text(
                        widget.confirmText,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                  if (widget.actionText != null) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          widget.onAction?.call();
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.grey.shade500,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        child: Text(
                          widget.actionText!,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
