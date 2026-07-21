import 'package:flutter/material.dart';
import '../../../core/app_colors.dart';

enum _WebAlertKind { confirm, success }

class WebAlert {
  static Future<bool?> confirm({
    required BuildContext context,
    required String  title,
    required String  message,
    String   confirmLabel = 'Delete',
    String   cancelLabel  = 'Cancel',
    Color    confirmColor = const Color(0xFFEF4444),
    Color    iconColor    = const Color(0xFFEF4444),
    Color    iconBg       = const Color(0xFFFEF2F2),
    IconData icon         = Icons.delete_outline_rounded,
  }) => showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.42),
    builder: (_) => _WebAlertDialog(
      kind:         _WebAlertKind.confirm,
      icon:         icon,
      iconColor:    iconColor,
      iconBg:       iconBg,
      title:        title,
      message:      message,
      confirmLabel: confirmLabel,
      cancelLabel:  cancelLabel,
      confirmColor: confirmColor,
    ),
  );

  static Future<void> success({
    required BuildContext context,
    required String title,
    String   message     = '',
    String   buttonLabel = 'Great!',
  }) => showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.42),
    builder: (_) => _WebAlertDialog(
      kind:         _WebAlertKind.success,
      icon:         Icons.check_rounded,
      iconColor:    const Color(0xFF10B981),
      iconBg:       const Color(0xFFECFDF5),
      title:        title,
      message:      message,
      confirmLabel: buttonLabel,
      confirmColor: const Color(0xFF10B981),
    ),
  );
}

class _WebAlertDialog extends StatefulWidget {
  final _WebAlertKind kind;
  final IconData      icon;
  final Color         iconColor;
  final Color         iconBg;
  final String        title;
  final String        message;
  final String        confirmLabel;
  final String?       cancelLabel;
  final Color         confirmColor;

  const _WebAlertDialog({
    required this.kind,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.cancelLabel,
    required this.confirmColor,
  });

  @override
  State<_WebAlertDialog> createState() => _WebAlertDialogState();
}

class _WebAlertDialogState extends State<_WebAlertDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _scale;
  late final Animation<double>   _fade;

  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
    _scale = Tween<double>(begin: 0.80, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _fade  = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isConfirm = widget.kind == _WebAlertKind.confirm;
    final dark      = Theme.of(context).brightness == Brightness.dark;
    final cardColor = dark ? const Color(0xFF12151B) : Colors.white;
    final borderCol = dark ? const Color(0xFF232833) : kCardBorder;
    final titleCol  = dark ? const Color(0xFFE7EAEE) : kText;
    final subCol    = dark ? const Color(0xFF9AA3B2) : kSubText;
    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(
        scale: _scale,
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Container(
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(22),
                border: dark ? Border.all(color: borderCol) : null,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: dark ? 0.55 : 0.16),
                    blurRadius: 40,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 32),
                  Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      color: widget.iconBg,
                      shape: BoxShape.circle,
                      border: Border.all(color: widget.iconColor.withValues(alpha: 0.18), width: 1.5),
                    ),
                    child: Icon(widget.icon, color: widget.iconColor, size: 34),
                  ),
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Text(widget.title,
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 17, fontWeight: FontWeight.w800, color: titleCol, height: 1.2,
                      ),
                      textAlign: TextAlign.center),
                  ),
                  if (widget.message.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Text(widget.message,
                        style: TextStyle(
                          fontFamily: 'Poppins', fontSize: 12.5, color: subCol, height: 1.6,
                        ),
                        textAlign: TextAlign.center),
                    ),
                  ],
                  const SizedBox(height: 28),
                  Divider(height: 1, color: borderCol),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    child: isConfirm
                      ? Row(children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: borderCol),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(vertical: 13),
                              ),
                              child: Text(widget.cancelLabel ?? 'Cancel',
                                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, color: subCol)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: widget.confirmColor,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(vertical: 13),
                              ),
                              child: Text(widget.confirmLabel,
                                style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ])
                      : SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: widget.confirmColor,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                            ),
                            child: Text(widget.confirmLabel,
                              style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
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
