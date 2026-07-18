import 'package:flutter/material.dart';
import '../../../core/app_colors.dart';
import 'web_shared.dart';
import 'profile_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Color presets
// ─────────────────────────────────────────────────────────────────────────────

const _kPrimary = [
  (Color(0xFFD6A742), 'Gold'),
  (Color(0xFF6366F1), 'Indigo'),
  (Color(0xFF8B5CF6), 'Violet'),
  (Color(0xFF3B82F6), 'Blue'),
  (Color(0xFF10B981), 'Emerald'),
  (Color(0xFFEF4444), 'Red'),
  (Color(0xFFF59E0B), 'Amber'),
  (Color(0xFF14B8A6), 'Teal'),
  (Color(0xFFEC4899), 'Pink'),
  (Color(0xFFEA580C), 'Orange'),
];

const _kSecondary = [
  (Color(0xFFF2DD6B), 'Golden'),
  (Color(0xFFF1F5F9), 'Ice White'),
  (Color(0xFFE0D7F6), 'Lavender'),
  (Color(0xFFBFEBFD), 'Sky Blue'),
  (Color(0xFFBBF7D0), 'Mint'),
  (Color(0xFFFDD5D5), 'Rose Mist'),
  (Color(0xFFFFE4BC), 'Peach'),
  (Color(0xFFE8DFD8), 'Warm Sand'),
  (Color(0xFF1E293B), 'Dark Navy'),
  (Color(0xFF3B1F7A), 'Deep Violet'),
];

// ─────────────────────────────────────────────────────────────────────────────
// Settings page
// ─────────────────────────────────────────────────────────────────────────────

enum _Tab { profile, theme, about }

class WebSettingsPage extends StatefulWidget {
  final String?  orgId;
  final String?  name;
  final String?  email;
  final String?  organization;
  final AppTheme theme;
  final void Function(AppTheme)          onThemeChanged;
  final void Function(String?, String?)  onProfileUpdated;

  const WebSettingsPage({
    super.key,
    this.orgId,
    this.name,
    this.email,
    this.organization,
    required this.theme,
    required this.onThemeChanged,
    required this.onProfileUpdated,
  });

  @override
  State<WebSettingsPage> createState() => _WebSettingsPageState();
}

class _WebSettingsPageState extends State<WebSettingsPage> {
  _Tab _tab = _Tab.profile;

  double _tabLabelWidth(String label, bool selected) {
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 13,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.width;
  }

  Widget _tabItem(_Tab t, String label, IconData icon) {
    final selected = _tab == t;
    final color    = selected ? widget.theme.primaryColor : kSubText;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => setState(() => _tab = t),
        child: Padding(
          padding: const EdgeInsets.only(right: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 15,
                    color: selected ? widget.theme.primaryColor : kMuted),
                  const SizedBox(width: 6),
                  Text(label,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: color,
                    )),
                ],
              ),
              const SizedBox(height: 5),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 2.5,
                width: selected ? _tabLabelWidth(label, selected) + 21 : 0,
                decoration: BoxDecoration(
                  color: selected
                    ? widget.theme.primaryColor
                    : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(kWebPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Page header ──
          const Text('Settings',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: kText,
              height: 1.1,
            )),
          const SizedBox(height: 3),
          const Text('Customize your workspace, account, and appearance',
            style: TextStyle(
              fontFamily: 'Poppins', fontSize: 12, color: kSubText)),
          const SizedBox(height: 20),

          // ── Tab bar ──
          Row(children: [
            _tabItem(_Tab.profile, 'Profile', Icons.person_outline_rounded),
            _tabItem(_Tab.theme,   'Theme',   Icons.palette_outlined),
            _tabItem(_Tab.about,   'About',   Icons.info_outline_rounded),
          ]),
          const SizedBox(height: 2),
          const Divider(color: kCardBorder),
          const SizedBox(height: 24),

          // ── Tab content ──
          if (_tab == _Tab.profile)
            WebProfilePage(
              orgId:        widget.orgId,
              name:         widget.name,
              email:        widget.email,
              organization: widget.organization,
              onProfileUpdated: widget.onProfileUpdated,
            )
          else if (_tab == _Tab.theme)
            _ThemeTab(
              theme:     widget.theme,
              onChanged: widget.onThemeChanged,
            )
          else
            _AboutTab(theme: widget.theme),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Theme tab
// ─────────────────────────────────────────────────────────────────────────────

class _ThemeTab extends StatelessWidget {
  final AppTheme                   theme;
  final void Function(AppTheme)    onChanged;
  const _ThemeTab({required this.theme, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, c) {
      final wide = c.maxWidth > 720;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Color theme card ──
          WebCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CardHeader(
                  icon:     Icons.palette_outlined,
                  title:    'Color Theme',
                  subtitle: 'Changes apply live across the dashboard',
                  color:    theme.primaryColor,
                ),
                const SizedBox(height: 20),
                const Divider(color: kCardBorder),
                const SizedBox(height: 22),

                // Primary color
                _ColorSection(
                  label:       'Primary Color',
                  description: 'Active navigation, buttons, and key highlights',
                  swatches:    _kPrimary,
                  selected:    theme.primaryColor,
                  onTap: (c) => onChanged(theme.copyWith(primaryColor: c)),
                ),
                const SizedBox(height: 24),
                const Divider(color: kCardBorder, height: 1),
                const SizedBox(height: 24),

                // Secondary color
                _ColorSection(
                  label:       'Secondary Color',
                  description: 'Sidebar background and gradient base',
                  swatches:    _kSecondary,
                  selected:    theme.secondaryColor,
                  onTap: (c) => onChanged(theme.copyWith(secondaryColor: c)),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Sidebar variant card ──
          WebCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CardHeader(
                  icon:     Icons.view_sidebar_outlined,
                  title:    'Sidebar Style',
                  subtitle: 'Choose how the navigation sidebar appears',
                  color:    theme.primaryColor,
                ),
                const SizedBox(height: 20),
                const Divider(color: kCardBorder),
                const SizedBox(height: 22),

                if (wide)
                  Row(
                    children: [
                      Expanded(child: _VariantCard(
                        value:     SidebarVariant.inset,
                        current:   theme.variant,
                        theme:     theme,
                        onChanged: (v) => onChanged(theme.copyWith(variant: v)),
                      )),
                      const SizedBox(width: 16),
                      Expanded(child: _VariantCard(
                        value:     SidebarVariant.floating,
                        current:   theme.variant,
                        theme:     theme,
                        onChanged: (v) => onChanged(theme.copyWith(variant: v)),
                      )),
                      const SizedBox(width: 16),
                      Expanded(child: _VariantCard(
                        value:     SidebarVariant.minimal,
                        current:   theme.variant,
                        theme:     theme,
                        onChanged: (v) => onChanged(theme.copyWith(variant: v)),
                      )),
                    ],
                  )
                else
                  Column(children: [
                    _VariantCard(
                      value: SidebarVariant.inset, current: theme.variant,
                      theme: theme, onChanged: (v) => onChanged(theme.copyWith(variant: v)),
                    ),
                    const SizedBox(height: 12),
                    _VariantCard(
                      value: SidebarVariant.floating, current: theme.variant,
                      theme: theme, onChanged: (v) => onChanged(theme.copyWith(variant: v)),
                    ),
                    const SizedBox(height: 12),
                    _VariantCard(
                      value: SidebarVariant.minimal, current: theme.variant,
                      theme: theme, onChanged: (v) => onChanged(theme.copyWith(variant: v)),
                    ),
                  ]),

                const SizedBox(height: 20),

                // Live preview note
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: theme.primaryColor.withValues(alpha: 0.20)),
                  ),
                  child: Row(children: [
                    Icon(Icons.auto_awesome_rounded,
                      size: 14, color: theme.primaryColor),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'All changes apply live — no page refresh needed.',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11.5,
                          color: theme.primaryColor,
                          fontWeight: FontWeight.w600,
                        )),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ],
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// About tab
// ─────────────────────────────────────────────────────────────────────────────

class _AboutTab extends StatelessWidget {
  final AppTheme theme;
  const _AboutTab({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WebCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CardHeader(
                icon:     Icons.info_outline_rounded,
                title:    'About EventHub',
                subtitle: 'Application details and version information',
                color:    theme.primaryColor,
              ),
              const SizedBox(height: 20),
              const Divider(color: kCardBorder),
              const SizedBox(height: 20),

              // App identity row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [theme.primaryColor, Color.lerp(theme.primaryColor, Colors.orange, 0.4)!],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [BoxShadow(color: theme.primaryColor.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 5))],
                    ),
                    child: const Icon(Icons.event_rounded, color: Colors.white, size: 36),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('EventHub',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 22, fontWeight: FontWeight.w800, color: kText)),
                        const SizedBox(height: 3),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD6A742).withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFD6A742).withValues(alpha: 0.30)),
                          ),
                          child: const Text('Version 1.0.0',
                            style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFB8861C))),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'J-Jireh Learning Center\'s official event management platform. Browse and register for school events, track your attendance, and scan in with your personal QR code — all in one place.',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, height: 1.65, color: kSubText),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),
              const Divider(color: kCardBorder),
              const SizedBox(height: 20),

              // Info grid
              Wrap(
                spacing: 16, runSpacing: 16,
                children: [
                  _infoChip(Icons.school_rounded,        'School',    'J-Jireh Learning Center', theme.primaryColor),
                  _infoChip(Icons.build_rounded,         'Built with','Flutter · Supabase',       theme.primaryColor),
                  _infoChip(Icons.devices_rounded,       'Platform',  'Android',                  theme.primaryColor),
                  _infoChip(Icons.people_alt_rounded,    'For',       'Students & Organizers',    theme.primaryColor),
                  _infoChip(Icons.calendar_month_rounded,'Released',  '2026',                     theme.primaryColor),
                  _infoChip(Icons.support_agent_rounded, 'Contact',   'See school admin',         theme.primaryColor),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _infoChip(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 10, color: kSubText, fontWeight: FontWeight.w500)),
              Text(value,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: kText, fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Color section
// ─────────────────────────────────────────────────────────────────────────────

class _ColorSection extends StatelessWidget {
  final String                              label;
  final String                              description;
  final List<(Color, String)>               swatches;
  final Color                               selected;
  final void Function(Color)                onTap;
  const _ColorSection({
    required this.label,
    required this.description,
    required this.swatches,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: kText,
          )),
        const SizedBox(height: 3),
        Text(description,
          style: const TextStyle(
            fontFamily: 'Poppins', fontSize: 11.5, color: kSubText)),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: swatches.map((s) {
            final (color, name) = s;
            final isSelected = selected == color;
            return _SwatchBtn(
              color:      color,
              label:      name,
              isSelected: isSelected,
              onTap:      () => onTap(color),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Color swatch button
// ─────────────────────────────────────────────────────────────────────────────

class _SwatchBtn extends StatefulWidget {
  final Color        color;
  final String       label;
  final bool         isSelected;
  final VoidCallback onTap;
  const _SwatchBtn({
    required this.color,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_SwatchBtn> createState() => _SwatchBtnState();
}

class _SwatchBtnState extends State<_SwatchBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final sel = widget.isSelected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: widget.label,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width:  38,
            height: 38,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
              border: Border.all(
                color: sel
                  ? Colors.white
                  : _hovered
                    ? Colors.white.withValues(alpha: 0.80)
                    : Colors.transparent,
                width: sel ? 3 : 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(
                    alpha: sel ? 0.55 : _hovered ? 0.40 : 0.20),
                  blurRadius: sel ? 12 : _hovered ? 8 : 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: sel
              ? const Icon(
                  Icons.check_rounded, size: 16, color: Colors.white)
              : null,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sidebar variant card
// ─────────────────────────────────────────────────────────────────────────────

class _VariantCard extends StatefulWidget {
  final SidebarVariant               value;
  final SidebarVariant               current;
  final AppTheme                     theme;
  final void Function(SidebarVariant) onChanged;
  const _VariantCard({
    required this.value,
    required this.current,
    required this.theme,
    required this.onChanged,
  });

  @override
  State<_VariantCard> createState() => _VariantCardState();
}

class _VariantCardState extends State<_VariantCard> {
  bool _hovered = false;

  static String _label(SidebarVariant v) => switch (v) {
    SidebarVariant.inset    => 'Inset',
    SidebarVariant.floating => 'Floating',
    SidebarVariant.minimal  => 'Minimal',
  };

  static String _desc(SidebarVariant v) => switch (v) {
    SidebarVariant.inset    => 'Classic embedded sidebar, always visible in the layout',
    SidebarVariant.floating => 'Sidebar floats over content with a card shadow and rounded edges',
    SidebarVariant.minimal  => 'Icon-only strip — maximum content space, minimum distraction',
  };

  static IconData _icon(SidebarVariant v) => switch (v) {
    SidebarVariant.inset    => Icons.view_sidebar_outlined,
    SidebarVariant.floating => Icons.layers_outlined,
    SidebarVariant.minimal  => Icons.more_vert_rounded,
  };

  Widget _preview(SidebarVariant v, Color sideColor, Color primary) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        height: 68,
        child: switch (v) {
          SidebarVariant.inset => Row(children: [
            Container(width: 22, color: sideColor),
            Container(width: 1.5, color: sideColor.withValues(alpha: 0.5)),
            Expanded(
              child: Container(
                color: const Color(0xFFF0F3F7),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(height: 6, width: 60,
                        decoration: BoxDecoration(
                          color: kText.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(3),
                        )),
                      const SizedBox(height: 5),
                      Container(height: 4, width: 40,
                        decoration: BoxDecoration(
                          color: kMuted.withValues(alpha: 0.30),
                          borderRadius: BorderRadius.circular(2),
                        )),
                    ],
                  ),
                ),
              ),
            ),
          ]),

          SidebarVariant.floating => Stack(
            children: [
              Positioned.fill(
                child: Container(color: const Color(0xFFF0F3F7))),
              Positioned(
                left: 6, top: 6, bottom: 6, width: 20,
                child: Container(
                  decoration: BoxDecoration(
                    color: sideColor,
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 8,
                        offset: const Offset(2, 0),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 32, top: 16, right: 12,
                child: Column(children: [
                  Container(height: 6, width: double.infinity,
                    decoration: BoxDecoration(
                      color: kText.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(3),
                    )),
                  const SizedBox(height: 5),
                  Container(height: 4, width: 40,
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: kMuted.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(2),
                    )),
                ]),
              ),
            ],
          ),

          SidebarVariant.minimal => Row(children: [
            Container(
              width: 12,
              color: sideColor,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Container(
                    width: 6, height: 6,
                    decoration: BoxDecoration(
                      color: i == 0
                        ? primary.withValues(alpha: 0.90)
                        : Colors.white.withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                    ),
                  ),
                )),
              ),
            ),
            Container(width: 1.5,
              color: sideColor.withValues(alpha: 0.5)),
            Expanded(
              child: Container(
                color: const Color(0xFFF0F3F7),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(height: 6, width: 72,
                        decoration: BoxDecoration(
                          color: kText.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(3),
                        )),
                      const SizedBox(height: 5),
                      Container(height: 4, width: 44,
                        decoration: BoxDecoration(
                          color: kMuted.withValues(alpha: 0.30),
                          borderRadius: BorderRadius.circular(2),
                        )),
                    ],
                  ),
                ),
              ),
            ),
          ]),
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sel     = widget.current == widget.value;
    final primary = widget.theme.primaryColor;
    final sideCol = widget.theme.secondaryColor;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => widget.onChanged(widget.value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: sel
              ? primary.withValues(alpha: 0.05)
              : _hovered
                ? const Color(0xFFF8F9FB)
                : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: sel
                ? primary.withValues(alpha: 0.45)
                : _hovered
                  ? kCardBorder
                  : kCardBorder,
              width: sel ? 2 : 1,
            ),
            boxShadow: sel
              ? [
                  BoxShadow(
                    color: primary.withValues(alpha: 0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Preview illustration
              _preview(widget.value, sideCol, primary),
              const SizedBox(height: 12),

              // Label row
              Row(children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: sel
                      ? primary.withValues(alpha: 0.12)
                      : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _icon(widget.value),
                    size: 14,
                    color: sel ? primary : kSubText,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_label(widget.value),
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: sel ? primary : kText,
                    )),
                ),
                if (sel)
                  Container(
                    width: 20, height: 20,
                    decoration: BoxDecoration(
                      color: primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
              ]),
              const SizedBox(height: 6),
              Text(_desc(widget.value),
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  color: kSubText,
                  height: 1.4,
                )),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card section header (reused from profile_page.dart pattern)
// ─────────────────────────────────────────────────────────────────────────────

class _CardHeader extends StatelessWidget {
  final IconData icon;
  final String   title;
  final String   subtitle;
  final Color    color;
  const _CardHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(
      width: 42, height: 42,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Icon(icon, color: color, size: 20),
    ),
    const SizedBox(width: 12),
    Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: kText,
            )),
          const SizedBox(height: 1),
          Text(subtitle,
            style: const TextStyle(
              fontFamily: 'Poppins', fontSize: 11, color: kSubText)),
        ],
      ),
    ),
  ]);
}
