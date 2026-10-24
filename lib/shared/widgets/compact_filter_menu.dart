import 'package:flutter/material.dart';
import '../../core/app_colors.dart';

class CompactFilterOption<T> {
  final T value;
  final String label;
  final int count;
  final Color? color;

  const CompactFilterOption({
    required this.value,
    required this.label,
    required this.count,
    this.color,
  });
}

/// A compact filter trigger with a mobile-friendly, searchable option sheet.
class CompactFilterMenu<T> extends StatelessWidget {
  final String label;
  final List<CompactFilterOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelect;
  final AppTk t;
  final Color accent;
  final IconData icon;
  final bool searchable;

  const CompactFilterMenu({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelect,
    required this.t,
    required this.accent,
    required this.icon,
    this.searchable = false,
  });

  Future<void> _showOptions(BuildContext context) async {
    final selection = await showModalBottomSheet<T>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: t.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CompactFilterSheet<T>(
        label: label,
        options: options,
        selected: selected,
        accent: accent,
        icon: icon,
        searchable: searchable,
        t: t,
      ),
    );
    if (selection != null) onSelect(selection);
  }

  @override
  Widget build(BuildContext context) {
    final current = options.firstWhere(
      (option) => option.value == selected,
      orElse: () => options.first,
    );
    final active = current.value != options.first.value;
    return Material(
      color: active ? accent.withValues(alpha: 0.10) : t.card,
      shape: StadiumBorder(
        side: BorderSide(
          color: active ? accent.withValues(alpha: 0.55) : t.border,
          width: active ? 1.4 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _showOptions(context),
              child: SizedBox(
                height: 44,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Icon(icon, size: 17, color: active ? accent : t.sub),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          '$label · ${current.label} ${current.count}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            fontWeight: active
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: active ? accent : t.text,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 19,
                        color: active ? accent : t.sub,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (active)
            IconButton(
              tooltip: 'Clear $label filter',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 40, height: 44),
              onPressed: () => onSelect(options.first.value),
              icon: Icon(Icons.close_rounded, size: 17, color: accent),
            ),
        ],
      ),
    );
  }
}

class _CompactFilterSheet<T> extends StatefulWidget {
  final String label;
  final List<CompactFilterOption<T>> options;
  final T selected;
  final Color accent;
  final IconData icon;
  final bool searchable;
  final AppTk t;

  const _CompactFilterSheet({
    required this.label,
    required this.options,
    required this.selected,
    required this.accent,
    required this.icon,
    required this.searchable,
    required this.t,
  });

  @override
  State<_CompactFilterSheet<T>> createState() => _CompactFilterSheetState<T>();
}

class _CompactFilterSheetState<T> extends State<_CompactFilterSheet<T>> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final filtered = widget.options.where((option) {
      return _query.isEmpty ||
          option.label.toLowerCase().contains(_query.toLowerCase());
    }).toList();
    final maxHeight = MediaQuery.sizeOf(context).height * 0.7;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Row(
              children: [
                Icon(widget.icon, color: widget.accent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${widget.label} filter',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: t.text,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close_rounded, color: t.sub),
                ),
              ],
            ),
          ),
          if (widget.searchable)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (value) => setState(() => _query = value.trim()),
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  color: t.text,
                ),
                decoration: InputDecoration(
                  hintText: 'Search ${widget.label.toLowerCase()}…',
                  prefixIcon: Icon(Icons.search_rounded, color: t.muted),
                  filled: true,
                  fillColor: t.bg,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: t.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: t.border),
                  ),
                ),
              ),
            ),
          Flexible(
            child: filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No matching ${widget.label.toLowerCase()}.',
                      style: TextStyle(fontFamily: 'Poppins', color: t.muted),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final option = filtered[index];
                      final isSelected = option.value == widget.selected;
                      final isEmpty = option.count == 0;
                      return ListTile(
                        minVerticalPadding: 4,
                        leading: option.color == null
                            ? Icon(widget.icon, color: widget.accent, size: 18)
                            : Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: option.color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                        title: Text(
                          option.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 14,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isEmpty ? t.muted : t.text,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${option.count}',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 13,
                                color: isEmpty ? t.muted : t.sub,
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 20,
                              child: isSelected
                                  ? Icon(
                                      Icons.check_rounded,
                                      size: 19,
                                      color: widget.accent,
                                    )
                                  : null,
                            ),
                          ],
                        ),
                        onTap: () => Navigator.pop(context, option.value),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
