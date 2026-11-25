import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Touch-friendly, scrollable Autocomplete options overlay designed for both
/// Android mobile (handles soft keyboard insets & nested scrollables) and Windows desktop.
class ScrollableAutocompleteOptions<T extends Object> extends StatefulWidget {
  final Iterable<T> options;
  final AutocompleteOnSelected<T> onSelected;
  final Widget Function(BuildContext context, T option) itemBuilder;
  final double maxHeight;
  final double? preferredWidth;

  const ScrollableAutocompleteOptions({
    super.key,
    required this.options,
    required this.onSelected,
    required this.itemBuilder,
    this.maxHeight = 200,
    this.preferredWidth,
  });

  @override
  State<ScrollableAutocompleteOptions<T>> createState() =>
      _ScrollableAutocompleteOptionsState<T>();
}

class _ScrollableAutocompleteOptionsState<T extends Object>
    extends State<ScrollableAutocompleteOptions<T>> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final visibleHeight = math.max(200.0, media.size.height - media.viewInsets.bottom);
    final effectiveMaxHeight = math.max(
      110.0,
      math.min(widget.maxHeight, visibleHeight * 0.34),
    );

    return Material(
      elevation: 8,
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFCBD5E1)),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: widget.preferredWidth ?? double.infinity,
          maxHeight: effectiveMaxHeight,
        ),
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          interactive: true,
          child: ListView.separated(
            controller: _scrollController,
            primary: false,
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 4),
            physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics(),
            ),
            itemCount: widget.options.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
            itemBuilder: (BuildContext context, int index) {
              final option = widget.options.elementAt(index);
              return InkWell(
                onTap: () => widget.onSelected(option),
                child: widget.itemBuilder(context, option),
              );
            },
          ),
        ),
      ),
    );
  }
}
