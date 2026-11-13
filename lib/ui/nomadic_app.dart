import 'package:flutter/material.dart';

import '../platform/browser_location.dart';
import '../state/app_controller.dart';
import 'calendar_page.dart';
import 'days_page.dart';
import 'flights_page.dart';
import 'gate_page.dart';
import 'missing_page.dart';
import 'planned_page.dart';
import 'records_page.dart';
import 'review_page.dart';
import 'rules_page.dart';
import 'section.dart';
import 'stays_page.dart';
import 'summary_page.dart';
import 'theme.dart';
import 'transfer_page.dart';
import 'trips_page.dart';

export 'section.dart';

class NomadicApp extends StatefulWidget {
  const NomadicApp({
    super.key,
    this.controller,
    this.initialSection = Section.days,
    this.initialExample = false,
    this.fontFamily,
    this.fontFamilyFallback,
  });

  final AppController? controller;
  final Section initialSection;
  final bool initialExample;

  /// Optional text face for screenshots. The running app leaves this unset.
  final String? fontFamily;
  final List<String>? fontFamilyFallback;

  @override
  State<NomadicApp> createState() => _NomadicAppState();
}

class _NomadicAppState extends State<NomadicApp> {
  late final AppController controller;
  late Section section;
  bool rolling = false;

  @override
  void initState() {
    super.initState();
    controller = widget.controller ?? AppController();
    section = widget.initialSection;
    if (widget.initialExample && controller.kind == SessionKind.unconfigured) {
      controller.openExample();
    }
    if (widget.controller == null) {
      controller.restoreIfSaved();
    }
  }

  @override
  void dispose() {
    if (widget.controller == null) controller.dispose();
    super.dispose();
  }

  void _go(Section next) {
    setState(() => section = next);
    final query = controller.isExample ? '?example=1' : '';
    replaceBrowserLocation('${next.path}$query');
  }

  ThemeData _theme() {
    final base = buildTheme();
    final family = widget.fontFamily;
    if (family == null) return base;
    final text = base.textTheme.apply(
      fontFamily: family,
      fontFamilyFallback: widget.fontFamilyFallback,
    );
    return base.copyWith(textTheme: text, primaryTextTheme: text);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nomadic Residence',
      debugShowCheckedModeBanner: false,
      theme: _theme(),
      home: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          if (!controller.canEdit) {
            return GatePage(controller: controller);
          }
          return _Shell(
            controller: controller,
            section: section,
            rolling: rolling,
            onSelect: _go,
            onRolling: (value) => setState(() => rolling = value),
          );
        },
      ),
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({
    required this.controller,
    required this.section,
    required this.rolling,
    required this.onSelect,
    required this.onRolling,
  });

  final AppController controller;
  final Section section;
  final bool rolling;
  final ValueChanged<Section> onSelect;
  final ValueChanged<bool> onRolling;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 980;
    final page = switch (section) {
      Section.days => DaysPage(
        controller: controller,
        rolling: rolling,
        onRolling: onRolling,
        onFillUnknown: () => onSelect(Section.missing),
        onConfirmTrips: () => onSelect(Section.trips),
      ),
      Section.calendar => CalendarPage(controller: controller),
      Section.records => RecordsPage(onOpen: onSelect),
      Section.missing => MissingPage(controller: controller, rolling: rolling),
      Section.trips => TripsPage(controller: controller, rolling: rolling),
      Section.summary => SummaryPage(controller: controller),
      Section.stays => StaysPage(controller: controller),
      Section.flights => FlightsPage(controller: controller),
      Section.review => ReviewPage(controller: controller),
      Section.planned => PlannedPage(controller: controller),
      Section.transfer => TransferPage(controller: controller),
      Section.rules => RulesPage(controller: controller),
    };
    final signedIn = controller.accountEmail;
    final banner = controller.isExample
        ? _Banner(
            key: const Key('example-banner'),
            text: 'Practice data. These trips are made up and stay in this browser tab.',
            onLeave: controller.leaveExample,
            actionLabel: 'Leave practice data',
          )
        : _Banner(
            text: signedIn == null || signedIn.isEmpty
                ? 'Signed in.'
                : 'Signed in as $signedIn.',
            onLeave: controller.signOut,
            actionLabel: 'Sign out',
          );
    final showYear =
        section != Section.days &&
        section != Section.missing &&
        section != Section.trips;
    final back = section.backTo;
    final header = Material(
      color: paper,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
            child: Row(
              children: [
                if (!wide)
                  Builder(
                    builder: (context) => IconButton(
                      tooltip: 'Sections',
                      onPressed: () => Scaffold.of(context).openDrawer(),
                      icon: const Icon(Icons.menu),
                    ),
                  ),
                if (back != null)
                  TextButton.icon(
                    key: const Key('back-to-list'),
                    onPressed: () => onSelect(back),
                    icon: const Icon(Icons.arrow_back),
                    label: Text(back.label),
                  ),
                const Expanded(
                  child: Text(
                    'Nomadic Residence',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
                if (showYear) ...[
                  IconButton(
                    tooltip: 'Previous year',
                    onPressed: () => controller.setYear(controller.year - 1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text(
                    '${controller.year}',
                    key: const Key('header-year'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  IconButton(
                    tooltip: 'Next year',
                    onPressed: () => controller.setYear(controller.year + 1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ],
            ),
          ),
          banner,
          if (!controller.isExample && controller.notices.isNotEmpty)
            _Banner(
              key: const Key('schema-notice'),
              text: controller.notices.join(' '),
              tone: _BannerTone.notice,
            ),
        ],
      ),
    );
    return Scaffold(
      drawer: wide
          ? null
          : Drawer(
              child: SafeArea(
                child: ListView(
                  children: [
                    const ListTile(title: Text('Nomadic Residence')),
                    for (final item in Section.primary)
                      ListTile(
                        leading: Icon(item.icon),
                        title: Text(item.label),
                        selected:
                            _railIndex(section) ==
                            Section.primary.indexOf(item),
                        onTap: () {
                          Navigator.of(context).pop();
                          onSelect(item);
                        },
                      ),
                  ],
                ),
              ),
            ),
      body: SafeArea(
        child: wide
            ? Row(
                children: [
                  NavigationRail(
                    selectedIndex: _railIndex(section),
                    onDestinationSelected: (index) =>
                        onSelect(Section.primary[index]),
                    labelType: NavigationRailLabelType.all,
                    destinations: [
                      for (final item in Section.primary)
                        NavigationRailDestination(
                          icon: Icon(item.icon),
                          label: Text(item.label),
                        ),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: Column(
                      children: [
                        header,
                        Expanded(child: page),
                      ],
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  header,
                  Expanded(child: page),
                ],
              ),
      ),
    );
  }
}

int _railIndex(Section section) {
  if (section == Section.calendar) {
    return Section.primary.indexOf(Section.calendar);
  }
  if (section.backTo == Section.records || section == Section.records) {
    return Section.primary.indexOf(Section.records);
  }
  return Section.primary.indexOf(Section.days);
}

enum _BannerTone { example, notice }

class _Banner extends StatelessWidget {
  const _Banner({
    super.key,
    required this.text,
    this.onLeave,
    this.actionLabel = 'Leave example',
    this.tone = _BannerTone.example,
  });

  final String text;
  final VoidCallback? onLeave;
  final String actionLabel;
  final _BannerTone tone;

  @override
  Widget build(BuildContext context) {
    final notice = tone == _BannerTone.notice;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: notice ? const Color(0xFFE7EEF2) : const Color(0xFFF6E7C1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: notice ? const Color(0xFFB7C9D4) : const Color(0xFFE2C98A),
        ),
      ),
      child: Row(
        children: [
          Expanded(child: Text(text)),
          if (onLeave != null)
            TextButton(onPressed: onLeave, child: Text(actionLabel)),
        ],
      ),
    );
  }
}
