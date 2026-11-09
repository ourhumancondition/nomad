import 'package:flutter/material.dart';

import '../platform/browser_location.dart';
import '../state/app_controller.dart';
import 'calendar_page.dart';
import 'flights_page.dart';
import 'gate_page.dart';
import 'planned_page.dart';
import 'review_page.dart';
import 'rules_page.dart';
import 'stays_page.dart';
import 'summary_page.dart';
import 'theme.dart';
import 'transfer_page.dart';

enum Section {
  summary('/', 'Year', Icons.public),
  calendar('/calendar', 'Calendar', Icons.calendar_month),
  stays('/stays', 'Stays', Icons.luggage),
  flights('/flights', 'Flights', Icons.flight),
  review('/review', 'Review', Icons.rule),
  planned('/planned', 'Planned', Icons.event_note),
  transfer('/transfer', 'Sheet', Icons.table_chart),
  rules('/rules', 'Rules', Icons.tune);

  const Section(this.path, this.label, this.icon);

  final String path;
  final String label;
  final IconData icon;

  static Section fromPath(String path) {
    final name = path.endsWith('/') && path.length > 1
        ? path.substring(0, path.length - 1)
        : path;
    for (final section in Section.values) {
      if (section.path == name) return section;
    }
    return Section.summary;
  }
}

class NomadicApp extends StatefulWidget {
  const NomadicApp({
    super.key,
    this.controller,
    this.initialSection = Section.summary,
    this.initialExample = false,
  });

  final AppController? controller;
  final Section initialSection;
  final bool initialExample;

  @override
  State<NomadicApp> createState() => _NomadicAppState();
}

class _NomadicAppState extends State<NomadicApp> {
  late final AppController controller;
  late Section section;

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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nomadic Residence',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          if (!controller.canEdit) {
            return GatePage(controller: controller);
          }
          return _Shell(
            controller: controller,
            section: section,
            onSelect: _go,
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
    required this.onSelect,
  });

  final AppController controller;
  final Section section;
  final ValueChanged<Section> onSelect;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 980;
    final page = switch (section) {
      Section.summary => SummaryPage(controller: controller),
      Section.calendar => CalendarPage(controller: controller),
      Section.stays => StaysPage(controller: controller),
      Section.flights => FlightsPage(controller: controller),
      Section.review => ReviewPage(controller: controller),
      Section.planned => PlannedPage(controller: controller),
      Section.transfer => TransferPage(controller: controller),
      Section.rules => RulesPage(controller: controller),
    };
    final banner = controller.isExample
        ? _Banner(
            key: const Key('example-banner'),
            text: 'Example dataset. Fictional records in this tab. Not connected to PocketBase.',
            onLeave: controller.leaveExample,
          )
        : _Banner(
            text:
                'Connected to ${controller.instanceOrigin ?? 'the registered database'}${controller.accountEmail == null ? '' : ' as ${controller.accountEmail}'}.',
            onLeave: controller.signOut,
            actionLabel: 'Sign out',
          );
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
                const Expanded(
                  child: Text(
                    'Nomadic Residence',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: 'Previous year',
                  onPressed: () => controller.setYear(controller.year - 1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Text(
                  '${controller.year}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                IconButton(
                  tooltip: 'Next year',
                  onPressed: () => controller.setYear(controller.year + 1),
                  icon: const Icon(Icons.chevron_right),
                ),
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
                    for (final item in Section.values)
                      ListTile(
                        leading: Icon(item.icon),
                        title: Text(item.label),
                        selected: item == section,
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
                    selectedIndex: section.index,
                    onDestinationSelected: (index) =>
                        onSelect(Section.values[index]),
                    labelType: NavigationRailLabelType.all,
                    destinations: [
                      for (final item in Section.values)
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
