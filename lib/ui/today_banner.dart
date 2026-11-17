import 'package:flutter/material.dart';

import '../data/countries.dart';
import '../engine/today_presence.dart';
import 'format.dart';
import 'theme.dart';

/// Colors for one status chip in one brightness. Kept public so the
/// contrast test can check every pair.
class TodayChipColors {
  const TodayChipColors(this.background, this.foreground);

  final Color background;
  final Color foreground;
}

String todayStatusLabel(TodayStatus status) => switch (status) {
  TodayStatus.confirmed => 'Confirmed',
  TodayStatus.fromFlights => 'From flights',
  TodayStatus.inTransit => 'In transit',
  TodayStatus.conflict => 'Needs a check',
  TodayStatus.unknown => 'Unknown',
};

TodayChipColors todayChipColors(TodayStatus status, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return switch (status) {
    TodayStatus.confirmed =>
      dark
          ? const TodayChipColors(Color(0xFF143A30), Color(0xFF8FDCC0))
          : const TodayChipColors(Color(0xFFDCEFE7), Color(0xFF0B5A46)),
    TodayStatus.fromFlights =>
      dark
          ? const TodayChipColors(Color(0xFF1A2B45), Color(0xFFA9C7F0))
          : const TodayChipColors(Color(0xFFE3ECF7), Color(0xFF1D4E89)),
    TodayStatus.inTransit =>
      dark
          ? const TodayChipColors(Color(0xFF22303D), Color(0xFFBACBDB))
          : const TodayChipColors(Color(0xFFE6ECF2), Color(0xFF34495E)),
    TodayStatus.conflict =>
      dark
          ? const TodayChipColors(Color(0xFF45231A), Color(0xFFF5B49B))
          : const TodayChipColors(Color(0xFFF8E3D8), Color(0xFF8C3A1E)),
    TodayStatus.unknown =>
      dark
          ? const TodayChipColors(Color(0xFF2E2B27), Color(0xFFD9D2C7))
          : const TodayChipColors(Color(0xFFECE8E1), Color(0xFF4F4942)),
  };
}

/// Muted text for the source line. Checked against the tinted card.
Color todayMutedText(Brightness brightness) => brightness == Brightness.dark
    ? const Color(0xFFC2BBB1)
    : const Color(0xFF59534B);

/// The card surface the banner tints, by brightness.
Color todaySurface(BuildContext context) =>
    Theme.of(context).colorScheme.surface;

/// The tint strength of the optional per-country accent. Kept low so text
/// contrast is set by the surface, not the accent.
const todayAccentAlpha = 0.12;

String _flagOr(String? code, String fallback) {
  if (code == null) return fallback;
  final flag = countryFlag(code);
  return flag.isEmpty ? fallback : flag;
}

String todayHeadline(TodayPresence presence) => switch (presence.status) {
  TodayStatus.confirmed ||
  TodayStatus.fromFlights => 'Today you\'re in ${presence.countryName}',
  TodayStatus.inTransit => 'Today you\'re in transit',
  TodayStatus.conflict => 'Two countries overlap today',
  TodayStatus.unknown => 'Where are you today?',
};

String? todaySubtitle(TodayPresence presence) {
  switch (presence.status) {
    case TodayStatus.confirmed:
    case TodayStatus.fromFlights:
      final since = presence.sinceDate;
      final here = since == null || since == presence.date
          ? 'arrived today'
          : 'here since ${todayMonthDay(since)}';
      return 'Day ${presence.dayCountThisYear} in ${presence.countryName} this year · $here';
    case TodayStatus.inTransit:
      return 'Today\'s wake-up is not added to a country.';
    case TodayStatus.conflict:
      return presence.conflictCountries
          .map((code) => '${countryFlag(code)} ${countryName(code)}'.trim())
          .join(' · ');
    case TodayStatus.unknown:
      final likely = presence.likelyCountry;
      return likely == null
          ? 'Nothing counts for ${shortDate(presence.date)} yet.'
          : 'Your records point to ${countryName(likely)}.';
  }
}

/// "Today you are in Canada, confirmed, day 113 this year".
String todaySemanticLabel(TodayPresence presence) {
  final status = todayStatusLabel(presence.status).toLowerCase();
  switch (presence.status) {
    case TodayStatus.confirmed:
    case TodayStatus.fromFlights:
      return 'Today you are in ${presence.countryName}, $status, '
          'day ${presence.dayCountThisYear} this year';
    case TodayStatus.inTransit:
      return 'Today you are in transit';
    case TodayStatus.conflict:
      return 'Two countries overlap today: '
          '${presence.conflictCountries.map(countryName).join(' and ')}. Needs a check';
    case TodayStatus.unknown:
      final likely = presence.likelyCountry;
      return likely == null
          ? 'Where are you today? No record for today'
          : 'Where are you today? Your records point to ${countryName(likely)}';
  }
}

/// The full "Today I'm in" card at the top of the Days page.
class TodayBanner extends StatelessWidget {
  const TodayBanner({
    super.key,
    required this.presence,
    this.saving = false,
    this.onConfirm,
    this.onElsewhere,
    this.onOpenConflicts,
    this.accentColor,
  });

  final TodayPresence presence;
  final bool saving;

  /// "Yes, I'm here" with the country to confirm.
  final ValueChanged<String>? onConfirm;
  final VoidCallback? onElsewhere;
  final VoidCallback? onOpenConflicts;

  /// Optional per-country accent. Defaults to the app's country color.
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final surface = todaySurface(context);
    final onSurface = theme.colorScheme.onSurface;
    final tint =
        accentColor ??
        (presence.countryCode == null
            ? accentFor(presence.status)
            : countryColor(presence.countryCode!));
    final flag = switch (presence.status) {
      TodayStatus.confirmed ||
      TodayStatus.fromFlights => _flagOr(presence.countryCode, '📍'),
      TodayStatus.inTransit => '✈️',
      TodayStatus.conflict => '⚠️',
      TodayStatus.unknown => '🌍',
    };
    final subtitle = todaySubtitle(presence);
    final candidate = presence.confirmCandidate;
    final buttonStyle = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
      tapTargetSize: MaterialTapTargetSize.padded,
    );

    final actions = <Widget>[
      if (candidate != null && onConfirm != null)
        FilledButton.icon(
          key: const Key('today-confirm'),
          style: buttonStyle,
          onPressed: saving ? null : () => onConfirm!(candidate),
          icon: const Icon(Icons.check),
          label: Text(
            presence.status == TodayStatus.unknown
                ? 'Yes, I\'m in ${countryName(candidate)}'
                : 'Yes, I\'m here',
          ),
        ),
      if (presence.status == TodayStatus.unknown &&
          candidate == null &&
          onElsewhere != null)
        FilledButton.icon(
          key: const Key('today-choose'),
          style: buttonStyle,
          onPressed: saving ? null : onElsewhere,
          icon: const Icon(Icons.public),
          label: const Text('Choose a country'),
        )
      else if (onElsewhere != null)
        TextButton(
          key: const Key('today-elsewhere'),
          style: buttonStyle,
          onPressed: saving ? null : onElsewhere,
          child: const Text('I\'m somewhere else'),
        ),
      if (presence.status == TodayStatus.conflict && onOpenConflicts != null)
        TextButton.icon(
          key: const Key('today-open-conflicts'),
          style: buttonStyle,
          onPressed: onOpenConflicts,
          icon: const Icon(Icons.list_alt),
          label: Text(
            presence.conflictingStays.length == 1
                ? 'See the overlapping record'
                : 'See the ${presence.conflictingStays.isEmpty ? '' : '${presence.conflictingStays.length} '}overlapping records',
          ),
        ),
    ];

    return Container(
      key: Key('today-banner-${presence.status.name}'),
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: brightness == Brightness.dark
              ? tint.withValues(alpha: 0.45)
              : tint.withValues(alpha: 0.28),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(tint.withValues(alpha: todayAccentAlpha), surface),
            surface,
          ],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            key: const Key('today-semantics'),
            container: true,
            label: todaySemanticLabel(presence),
            excludeSemantics: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  flag,
                  key: const Key('today-flag'),
                  style: const TextStyle(fontSize: 44, height: 1.1),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _StatusChip(status: presence.status),
                      const SizedBox(height: 6),
                      Text(
                        todayHeadline(presence),
                        key: const Key('today-headline'),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: onSurface,
                          height: 1.15,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          key: const Key('today-subtitle'),
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: onSurface,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        presence.sourceLabel,
                        key: const Key('today-source'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: todayMutedText(brightness),
                        ),
                      ),
                      if (presence.status == TodayStatus.conflict)
                        for (final stay in presence.conflictingStays)
                          Text(
                            '${countryName(stay.countryCode)}: ${shortRange(stay.start, stay.end)}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: todayMutedText(brightness),
                            ),
                          ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }

  static Color accentFor(TodayStatus status) => switch (status) {
    TodayStatus.inTransit => transit,
    TodayStatus.conflict => gapInk,
    _ => accent,
  };
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, this.dense = false});

  final TodayStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = todayChipColors(status, Theme.of(context).brightness);
    return Container(
      key: Key('today-${dense ? 'compact-' : ''}chip-${status.name}'),
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        todayStatusLabel(status),
        style: TextStyle(
          color: colors.foreground,
          fontSize: dense ? 12 : 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// The slim sticky header shown once the full banner scrolls away.
class TodayCompactBar extends StatelessWidget {
  const TodayCompactBar({super.key, required this.presence, this.onTap});

  final TodayPresence presence;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = presence.countryCode;
    final flag = switch (presence.status) {
      TodayStatus.confirmed || TodayStatus.fromFlights => _flagOr(code, '📍'),
      TodayStatus.inTransit => '✈️',
      TodayStatus.conflict => '⚠️',
      TodayStatus.unknown => '🌍',
    };
    final title = switch (presence.status) {
      TodayStatus.confirmed || TodayStatus.fromFlights => presence.countryName!,
      TodayStatus.inTransit => 'In transit',
      TodayStatus.conflict => 'Two countries today',
      TodayStatus.unknown => 'Where are you today?',
    };
    return Material(
      key: const Key('today-compact'),
      color: todaySurface(context),
      elevation: 2,
      shadowColor: Colors.black26,
      child: Semantics(
        button: onTap != null,
        label: todaySemanticLabel(presence),
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Text(flag, style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  _StatusChip(status: presence.status, dense: true),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A placeholder while today's records load. It never names a country.
class TodayBannerSkeleton extends StatefulWidget {
  const TodayBannerSkeleton({super.key});

  @override
  State<TodayBannerSkeleton> createState() => _TodayBannerSkeletonState();
}

class _TodayBannerSkeletonState extends State<TodayBannerSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = dark ? const Color(0xFF2A2825) : const Color(0xFFEAE4DA);
    final glow = dark ? const Color(0xFF3A3733) : const Color(0xFFF7F3EC);
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
    );
    return Semantics(
      key: const Key('today-skeleton'),
      label: 'Loading today\'s country',
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: _shimmer,
        builder: (context, child) {
          final t = _shimmer.value * 3 - 1;
          return ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (rect) => LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [base, glow, base],
              stops: [
                (t - 0.3).clamp(0.0, 1.0),
                t.clamp(0.0, 1.0),
                (t + 0.3).clamp(0.0, 1.0),
              ],
            ).createShader(rect),
            child: child,
          );
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: todaySurface(context),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: base),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              bar(48, 48),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bar(84, 20),
                    const SizedBox(height: 10),
                    bar(220, 24),
                    const SizedBox(height: 8),
                    bar(180, 16),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What "I'm somewhere else" returns.
class TodayElsewhereChoice {
  const TodayElsewhereChoice(this.country, this.note);

  final String country;
  final String note;
}

/// A searchable country picker with recent countries first, plus a note.
Future<TodayElsewhereChoice?> showTodayElsewhereSheet(
  BuildContext context, {
  required List<String> recentCountries,
  String? exclude,
}) {
  return showModalBottomSheet<TodayElsewhereChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _ElsewhereSheet(
      recent: [
        for (final code in recentCountries)
          if (code != exclude && countryNames.containsKey(code)) code,
      ],
    ),
  );
}

class _ElsewhereSheet extends StatefulWidget {
  const _ElsewhereSheet({required this.recent});

  final List<String> recent;

  @override
  State<_ElsewhereSheet> createState() => _ElsewhereSheetState();
}

class _ElsewhereSheetState extends State<_ElsewhereSheet> {
  final _search = TextEditingController();
  final _note = TextEditingController();
  String? _selected;

  @override
  void dispose() {
    _search.dispose();
    _note.dispose();
    super.dispose();
  }

  List<String> get _options {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) {
      final rest = countryNames.keys.where((c) => !widget.recent.contains(c));
      return [...widget.recent, ...rest];
    }
    return [
      for (final entry in countryNames.entries)
        if (entry.key.toLowerCase() == query ||
            entry.value.toLowerCase().contains(query))
          entry.key,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final options = _options;
    final insets = MediaQuery.viewInsetsOf(context);
    final height = MediaQuery.sizeOf(context).height;
    return Padding(
      padding: EdgeInsets.only(bottom: insets.bottom),
      child: SizedBox(
        height: (height * 0.8).clamp(320.0, 640.0),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Where are you today?',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text('Saves a confirmed stay for today only.'),
              const SizedBox(height: 12),
              TextField(
                key: const Key('today-search'),
                controller: _search,
                autofocus: false,
                decoration: const InputDecoration(
                  labelText: 'Search countries',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              if (_search.text.trim().isEmpty && widget.recent.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 4, bottom: 4),
                  child: Text(
                    'Recent',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  key: const Key('today-country-list'),
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final code = options[index];
                    return ListTile(
                      key: Key('today-option-$code'),
                      minTileHeight: 48,
                      leading: Text(
                        countryFlag(code),
                        style: const TextStyle(fontSize: 22),
                      ),
                      title: Text(countryName(code)),
                      selected: code == _selected,
                      trailing: code == _selected
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () => setState(() => _selected = code),
                    );
                  },
                ),
              ),
              TextField(
                key: const Key('today-note'),
                controller: _note,
                maxLength: 500,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
              ),
              Text(
                _selected == null
                    ? 'Choose a country.'
                    : '${countryFlag(_selected!)} ${countryName(_selected!)}',
                key: const Key('today-elsewhere-selected'),
              ),
              const SizedBox(height: 4),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton(
                    style: const ButtonStyle(
                      minimumSize: WidgetStatePropertyAll(Size(48, 48)),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    key: const Key('today-elsewhere-save'),
                    style: const ButtonStyle(
                      minimumSize: WidgetStatePropertyAll(Size(48, 48)),
                    ),
                    onPressed: _selected == null
                        ? null
                        : () => Navigator.of(
                            context,
                          ).pop(TodayElsewhereChoice(_selected!, _note.text)),
                    child: const Text('Save for today'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
