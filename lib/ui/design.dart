/// Shared visual building blocks for SuperHealth's refreshed interface.
///
/// Everything here is theme-driven: no widget hardcodes a brightness-specific
/// colour, so light, dark, high-contrast, and the deuteranomaly-friendly
/// palette all keep working without per-screen special cases.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import '../app/appearance_settings.dart';

/// Corner radii used across the refreshed surfaces.
class AppRadius {
  const AppRadius._();

  static const small = 12.0;
  static const medium = 18.0;
  static const large = 24.0;
  static const pill = 999.0;
}

/// Consistent spacing steps so screens breathe the same way.
class AppSpacing {
  const AppSpacing._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
}

/// A colour-blind safe qualitative palette.
///
/// These hues stay distinguishable under deuteranomaly because they never rely
/// on separating red from green.
const deuteranomalySafeSeries = <Color>[
  Color(0xFF0072B2),
  Color(0xFFE69F00),
  Color(0xFF56B4E9),
  Color(0xFFCC79A7),
  Color(0xFF8C61FF),
  Color(0xFF9C6B00),
  Color(0xFF3B4CC0),
  Color(0xFFD55E00),
];

/// The standard qualitative palette. Deterministic, and readable on both the
/// light and the dark surface.
const standardSeries = <Color>[
  Color(0xFF00897B),
  Color(0xFF3D5AFE),
  Color(0xFFF9A825),
  Color(0xFFD81B60),
  Color(0xFF7B1FA2),
  Color(0xFF00838F),
  Color(0xFF558B2F),
  Color(0xFFEF6C00),
];

/// The base hues plus a darker and a lighter variant of each.
///
/// A chart draws at most a handful of series, so eight slots leave the hash
/// assignment below crowded enough that most keys get bumped off their own
/// slot. Widening to twenty-four keeps the base hues first — those are the ones
/// a short list actually gets — while leaving enough room that a collision is
/// the exception.
List<Color> _extendedPalette(List<Color> base) => [
  ...base,
  for (final color in base) _shifted(color, -0.12),
  for (final color in base) _shifted(color, 0.12),
];

/// The same hue at a different lightness, clamped to a band that stays legible
/// on both the light and the dark surface.
Color _shifted(Color color, double delta) {
  final hsl = HSLColor.fromColor(color);
  return hsl.withLightness((hsl.lightness + delta).clamp(0.28, 0.66)).toColor();
}

final _standardExtended = _extendedPalette(standardSeries);
final _deuteranomalyExtended = _extendedPalette(deuteranomalySafeSeries);

/// Assigns each key a colour, distinct within the set it is called with.
///
/// Two lines the same colour are unreadable, so distinctness inside one chart
/// is the property that has to hold. Handing out palette entries by position
/// would satisfy it but would recolour every series after the one a person
/// unpins. Instead each key claims the slot its own hash points at and only
/// moves when something else already holds it, which over the widened palette
/// leaves the great majority of colours untouched across a pin or a filter.
/// Keys are visited in sorted order, so the result depends only on the set and
/// not on the caller's iteration order.
Map<String, Color> seriesColors(
  Iterable<String> keys, {
  AppColorMode colorMode = AppColorMode.standard,
}) {
  final palette = colorMode == AppColorMode.deuteranomalyFriendly
      ? _deuteranomalyExtended
      : _standardExtended;
  final ordered = keys.toSet().toList()..sort();
  final taken = <int>{};
  final result = <String, Color>{};
  for (final key in ordered) {
    final preferred = key.hashCode.abs() % palette.length;
    var slot = preferred;
    // Past a full palette every slot is taken, so reuse rather than loop.
    if (taken.length < palette.length) {
      var offset = 0;
      while (taken.contains(slot) && offset < palette.length) {
        offset++;
        slot = (preferred + offset) % palette.length;
      }
    }
    taken.add(slot);
    result[key] = palette[slot];
  }
  return result;
}

/// Black or white, whichever is readable on [background].
///
/// The qualitative palettes span dark blues and mid ambers, so a fixed white
/// label would drop below a usable contrast ratio on the lighter entries.
Color onSeriesColor(Color background) {
  final luminance = relativeLuminance(background);
  final onWhite = 1.05 / (luminance + 0.05);
  final onBlack = (luminance + 0.05) / 0.05;
  return onBlack >= onWhite ? Colors.black : Colors.white;
}

/// A deterministic accent for a single label, used for avatars and dots.
Color seriesColorFor(
  String key, {
  AppColorMode colorMode = AppColorMode.standard,
}) {
  final palette = colorMode == AppColorMode.deuteranomalyFriendly
      ? deuteranomalySafeSeries
      : standardSeries;
  return palette[key.hashCode.abs() % palette.length];
}

/// A rounded surface with a soft tonal fill, the base of the refreshed look.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.margin = const EdgeInsets.symmetric(vertical: 5),
    this.color,
    this.onTap,
    this.borderColor,
    this.semanticLabel,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? color;
  final Color? borderColor;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final content = Padding(padding: padding, child: child);
    final card = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: color ?? colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.large),
        border: Border.all(color: borderColor ?? colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
    if (semanticLabel == null) return card;
    return Semantics(label: semanticLabel, button: onTap != null, child: card);
  }
}

/// The header used at the top of the Today screen.
///
/// Shows the greeting, the day being viewed, and a ring with the share of the
/// day's scheduled doses that are already recorded.
class HeroProgressCard extends StatelessWidget {
  const HeroProgressCard({
    required this.greeting,
    required this.subtitle,
    required this.progress,
    required this.centerLabel,
    this.chips = const [],
    this.trailingAction,
    this.semanticLabel,
    super.key,
  });

  final String greeting;
  final String subtitle;

  /// `null` when nothing is scheduled, so the ring reads as "no target" rather
  /// than as zero adherence.
  final double? progress;
  final String centerLabel;
  final List<Widget> chips;
  final Widget? trailingAction;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Semantics(
      label: semanticLabel,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.large),
          border: Border.all(color: colors.outlineVariant),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colors.primaryContainer.withValues(alpha: 0.75),
              colors.surfaceContainerLow,
            ],
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    greeting,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  if (chips.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: 6,
                      children: chips,
                    ),
                  ],
                  if (trailingAction != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    trailingAction!,
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            ProgressRing(
              value: progress,
              label: centerLabel,
              size: 104,
              strokeWidth: 11,
            ),
          ],
        ),
      ),
    );
  }
}

/// An animated circular progress ring with a value in the middle.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    required this.value,
    required this.label,
    this.size = 72,
    this.strokeWidth = 8,
    this.color,
    super.key,
  });

  final double? value;
  final String label;
  final double size;
  final double strokeWidth;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final target = (value ?? 0).clamp(0.0, 1.0).toDouble();
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: target),
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOutCubic,
        builder: (context, animated, _) => Stack(
          fit: StackFit.expand,
          children: [
            CircularProgressIndicator(
              value: 1,
              strokeWidth: strokeWidth,
              valueColor: AlwaysStoppedAnimation(
                colors.surfaceContainerHighest,
              ),
            ),
            if (value != null)
              CircularProgressIndicator(
                value: animated,
                strokeWidth: strokeWidth,
                strokeCap: StrokeCap.round,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation(color ?? colors.primary),
              ),
            Center(
              child: Padding(
                padding: EdgeInsets.all(strokeWidth + 4),
                child: FittedBox(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
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

/// A compact, tappable metric tile for the Today overview grid.
class StatTile extends StatelessWidget {
  const StatTile({
    required this.label,
    required this.value,
    required this.icon,
    this.detail,
    this.onTap,
    this.tone,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? detail;
  final VoidCallback? onTap;

  /// Optional accent, used to mark a tile that needs attention.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = tone ?? colors.primary;
    return Semantics(
      button: onTap != null,
      label: detail == null ? '$label: $value' : '$label: $value. $detail',
      excludeSemantics: true,
      child: Material(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.large),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.large),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.large),
              border: Border.all(color: colors.outlineVariant),
            ),
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(AppRadius.small),
                      ),
                      child: Icon(icon, size: 18, color: accent),
                    ),
                    const Spacer(),
                    if (onTap != null)
                      Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: colors.onSurfaceVariant,
                      ),
                  ],
                ),
                const Spacer(),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge,
                ),
                if (detail != null)
                  Text(
                    detail!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A horizontally scrolling calendar strip that keeps the selected day in view.
class DayStrip extends StatefulWidget {
  const DayStrip({
    required this.selectedDay,
    required this.onSelected,
    required this.weekdayLabel,
    required this.dayLabel,
    required this.semanticLabel,
    this.daysBefore = 7,
    this.daysAfter = 7,
    this.markerFor,
    super.key,
  });

  final DateTime selectedDay;
  final ValueChanged<DateTime> onSelected;
  final String Function(DateTime day) weekdayLabel;
  final String Function(DateTime day) dayLabel;
  final String Function(DateTime day) semanticLabel;
  final int daysBefore;
  final int daysAfter;

  /// Optional per-day completion share, drawn as a small bar under the number.
  final double? Function(DateTime day)? markerFor;

  @override
  State<DayStrip> createState() => _DayStripState();
}

class _DayStripState extends State<DayStrip> {
  static const _itemWidth = 62.0;
  static const _itemSpacing = 8.0;

  final _controller = ScrollController();
  var _centeredOnce = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _center(animate: false),
    );
  }

  @override
  void didUpdateWidget(DayStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameDay(oldWidget.selectedDay, widget.selectedDay)) {
      _center(animate: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _center({required bool animate}) {
    if (!_controller.hasClients) return;
    if (!animate && _centeredOnce) return;
    _centeredOnce = true;
    final today = _startOfDay(DateTime.now());
    final selected = _startOfDay(widget.selectedDay);
    final index = widget.daysBefore + selected.difference(today).inDays;
    final total = widget.daysBefore + widget.daysAfter + 1;
    if (index < 0 || index >= total) return;
    const stride = _itemWidth + _itemSpacing;
    final viewport = _controller.position.viewportDimension;
    final offset = (index * stride) - (viewport / 2) + (_itemWidth / 2);
    final target = offset.clamp(
      _controller.position.minScrollExtent,
      _controller.position.maxScrollExtent,
    );
    if (animate) {
      _controller.animateTo(
        target,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } else {
      _controller.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final today = _startOfDay(DateTime.now());
    final total = widget.daysBefore + widget.daysAfter + 1;
    return SizedBox(
      height: 88,
      child: ListView.separated(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: total,
        separatorBuilder: (_, _) => const SizedBox(width: _itemSpacing),
        itemBuilder: (context, index) {
          final day = DateTime(
            today.year,
            today.month,
            today.day - widget.daysBefore + index,
          );
          final selected = _sameDay(day, widget.selectedDay);
          final isToday = _sameDay(day, today);
          final marker = widget.markerFor?.call(day);
          return Semantics(
            selected: selected,
            button: true,
            label: widget.semanticLabel(day),
            excludeSemantics: true,
            child: GestureDetector(
              onTap: () => widget.onSelected(day),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                width: _itemWidth,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? colors.primary : colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(AppRadius.medium),
                  border: Border.all(
                    color: selected
                        ? colors.primary
                        : isToday
                        ? colors.primary.withValues(alpha: 0.55)
                        : colors.outlineVariant,
                    width: isToday && !selected ? 1.6 : 1,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.weekdayLabel(day).toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? colors.onPrimary
                            : colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.dayLabel(day),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: selected ? colors.onPrimary : colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 5,
                      width: 26,
                      child: marker == null
                          ? (isToday
                                ? DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? colors.onPrimary
                                          : colors.primary,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  )
                                : const SizedBox.shrink())
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: marker.clamp(0.0, 1.0),
                                backgroundColor: selected
                                    ? colors.onPrimary.withValues(alpha: 0.3)
                                    : colors.surfaceContainerHighest,
                                valueColor: AlwaysStoppedAnimation(
                                  selected ? colors.onPrimary : colors.primary,
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A labelled group of rows, used for the time-of-day dose blocks.
class TimeBlockHeader extends StatelessWidget {
  const TimeBlockHeader({
    required this.icon,
    required this.title,
    required this.trailing,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String trailing;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, AppSpacing.lg, 4, AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colors.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(trailing, style: theme.textTheme.labelMedium),
          ),
          if (action != null) ...[
            const SizedBox(width: AppSpacing.sm),
            action!,
          ],
        ],
      ),
    );
  }
}

/// A tiny inline bar chart used inside cards where a full chart is too heavy.
class MiniBars extends StatelessWidget {
  const MiniBars({
    required this.values,
    required this.semanticLabel,
    this.height = 46,
    this.color,
    super.key,
  });

  final List<double> values;
  final String semanticLabel;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (values.isEmpty) return const SizedBox.shrink();
    final maximum = values.fold<double>(0, math.max);
    return Semantics(
      label: semanticLabel,
      child: SizedBox(
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final value in values)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Container(
                    height: maximum <= 0 ? 2 : (height * value / maximum) + 2,
                    decoration: BoxDecoration(
                      color: color ?? colors.primary,
                      borderRadius: BorderRadius.circular(3),
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

/// A small colour swatch with a label, used as a chart legend entry.
class SeriesLegend extends StatelessWidget {
  const SeriesLegend({
    required this.entries,
    this.onTap,
    this.pinned = const {},
    super.key,
  });

  final Map<String, Color> entries;
  final void Function(String key)? onTap;
  final Set<String> pinned;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: 6,
      children: [
        for (final entry in entries.entries)
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            onTap: onTap == null ? null : () => onTap!(entry.key),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                color: entry.value.withValues(alpha: 0.13),
                border: Border.all(
                  color: pinned.contains(entry.key)
                      ? entry.value
                      : entry.value.withValues(alpha: 0.35),
                  width: pinned.contains(entry.key) ? 1.6 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: entry.value,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(entry.key, style: theme.textTheme.labelMedium),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

DateTime _startOfDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// The SuperHealth mark, shown while the record opens and during onboarding.
class AppMark extends StatelessWidget {
  const AppMark({this.size = 96, super.key});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'SuperHealth',
    image: true,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.24),
      child: Image.asset(
        'assets/branding/app_icon.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        // The mark is decorative; a missing asset must never keep the health
        // record from opening.
        errorBuilder: (context, _, _) => Icon(
          Icons.health_and_safety_outlined,
          size: size * 0.6,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    ),
  );
}
