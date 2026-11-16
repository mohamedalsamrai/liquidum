// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart';
import 'package:liquidum/liquidum.dart';

import 'art.dart';

/// The Plan tab: a trip with a popover, an action sheet from its button, a
/// sheet, compact date pickers, notes with the edit menu, and alerts.
class PlanPage extends StatefulWidget {
  const PlanPage({super.key});

  @override
  State<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<PlanPage> {
  String _name = 'Northern Lights';
  DateTime _depart = DateTime(2027, 2, 12);
  DateTime _return = DateTime(2027, 2, 19);
  DateTime _flight = DateTime(2027, 2, 12, 7, 40);
  final TextEditingController _notes = TextEditingController(
    text:
        'Flight to Tromsø at 7:40. Chase the aurora with a guide on '
        'Friday night, then huskies on Saturday and a fjord cruise.',
  );

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _rename() async {
    final TextEditingController name = TextEditingController(text: _name);
    final GlassAlertAction? chosen = await showGlassAlert(
      context: context,
      title: 'Rename Trip',
      message: 'Give this trip a name you will remember.',
      textFields: <GlassAlertTextField>[
        GlassAlertTextField(controller: name, placeholder: 'Name'),
      ],
      actions: const <GlassAlertAction>[
        GlassAlertAction(label: 'Cancel', cancel: true),
        GlassAlertAction(label: 'Save'),
      ],
    );
    if (chosen?.label == 'Save' && name.text.isNotEmpty) {
      setState(() => _name = name.text);
    }
    name.dispose();
  }

  void _cancelTrip() => showGlassAlert(
    context: context,
    title: 'Cancel This Trip?',
    message:
        'Your flights and cabin in ${trip.name} will be cancelled. This '
        'cannot be undone.',
    actions: const <GlassAlertAction>[
      GlassAlertAction(label: 'Keep Trip', cancel: true),
      GlassAlertAction(label: 'Cancel Trip', destructive: true),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return GlassPage(
      title: 'Plan',
      largeTitle: true,
      actions: <GlassBarItem>[
        GlassBarItem(
          icon: CupertinoIcons.pencil,
          semanticLabel: 'Rename',
          onPressed: _rename,
        ),
      ],
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
        context,
      ),
      child: Builder(
        builder: (BuildContext context) {
          final EdgeInsets pad = MediaQuery.paddingOf(context);
          return ListView(
            padding: EdgeInsets.fromLTRB(16, pad.top + 4, 16, pad.bottom + 24),
            children: <Widget>[
              _TripCard(name: _name),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  // A popover points at the button it came from.
                  Builder(
                    builder: (BuildContext source) => GlassButton(
                      label: 'Weather',
                      icon: CupertinoIcons.cloud_sun_fill,
                      onPressed: () => showGlassPopover<void>(
                        context: source,
                        builder: (BuildContext context) => const _Forecast(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GlassButton(
                    label: 'Packing',
                    icon: CupertinoIcons.bag_fill,
                    onPressed: () => showGlassSheet<void>(
                      context: context,
                      builder: (BuildContext context) => const _PackingList(),
                    ),
                  ),
                  const Spacer(),
                  // From a source, an action sheet is a popover too.
                  Builder(
                    builder: (BuildContext source) => GlassButton(
                      icon: CupertinoIcons.share,
                      onPressed: () => showGlassActionSheet(
                        context: context,
                        source: source,
                        title: 'Share Trip',
                        message: '${trip.name} · Feb 12 – 19',
                        actions: const <GlassAlertAction>[
                          GlassAlertAction(label: 'Copy Link'),
                          GlassAlertAction(label: 'Invite Friends'),
                          GlassAlertAction(label: 'Export to Calendar'),
                          GlassAlertAction(label: 'Cancel', cancel: true),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const _Header('DATES'),
              _Group(
                children: <Widget>[
                  _Row(
                    label: 'Depart',
                    child: GlassDatePicker(
                      value: _depart,
                      onChanged: (DateTime d) => setState(() => _depart = d),
                    ),
                  ),
                  _Row(
                    label: 'Return',
                    child: GlassDatePicker(
                      value: _return,
                      firstDate: _depart,
                      onChanged: (DateTime d) => setState(() => _return = d),
                    ),
                  ),
                  _Row(
                    label: 'Flight',
                    child: GlassDatePicker(
                      value: _flight,
                      mode: GlassDatePickerMode.time,
                      onChanged: (DateTime d) => setState(() => _flight = d),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const _Header('NOTES'),
              _Group(
                children: <Widget>[
                  // Select a word: the edit menu, on glass.
                  CupertinoTextField(
                    controller: _notes,
                    maxLines: null,
                    padding: const EdgeInsets.all(16),
                    decoration: null,
                    style: TextStyle(
                      fontSize: 17,
                      height: 1.35,
                      color: CupertinoColors.label.resolveFrom(context),
                    ),
                    contextMenuBuilder: GlassEditMenu.builder,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Center(
                child: GlassButton(
                  label: 'Cancel Trip',
                  prominent: true,
                  tint: CupertinoColors.systemRed,
                  onPressed: _cancelTrip,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 230,
      child: Stack(
        children: <Widget>[
          Positioned.fill(child: Photo(trip.photo, radius: 28)),
          Positioned(
            left: 18,
            bottom: 16,
            right: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                    color: Color(0xFFFFFFFF),
                  ),
                ),
                Text(
                  '${trip.name}, ${trip.country} · Feb 12 – 19',
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xCCFFFFFF),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 14,
            right: 14,
            child: Glass(
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: GlassLabel('In 88 days', icon: CupertinoIcons.airplane),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A grouped section, as iOS's Settings.
class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final Color line = CupertinoColors.separator.resolveFrom(context);
    return Container(
      decoration: ShapeDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
          context,
        ),
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(26),
        ),
      ),
      child: Column(
        children: <Widget>[
          for (var i = 0; i < children.length; i++) ...<Widget>[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Container(height: 0.5, color: line),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      child: Row(
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              fontSize: 17,
              color: CupertinoColors.label.resolveFrom(context),
            ),
          ),
          const Spacer(),
          child,
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
        ),
      ),
    );
  }
}

/// The popover's content: the week's weather.
class _Forecast extends StatelessWidget {
  const _Forecast();

  static const List<(String, IconData, int)> _days = <(String, IconData, int)>[
    ('Fri', CupertinoIcons.moon_stars_fill, -6),
    ('Sat', CupertinoIcons.snow, -4),
    ('Sun', CupertinoIcons.cloud_fill, -3),
    ('Mon', CupertinoIcons.moon_stars_fill, -7),
    ('Tue', CupertinoIcons.sun_max_fill, -2),
  ];

  @override
  Widget build(BuildContext context) {
    final Color label = CupertinoColors.label.resolveFrom(context);
    final Color secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Tromsø this week',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: label,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final (String day, IconData icon, int t) in _days)
                SizedBox(
                  width: 52,
                  child: Column(
                    children: <Widget>[
                      Text(
                        day,
                        style: TextStyle(fontSize: 13, color: secondary),
                      ),
                      const SizedBox(height: 8),
                      Icon(icon, size: 24, color: secondary),
                      const SizedBox(height: 8),
                      Text(
                        '$t°',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: label,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The sheet's content: a packing list.
class _PackingList extends StatefulWidget {
  const _PackingList();

  @override
  State<_PackingList> createState() => _PackingListState();
}

class _PackingListState extends State<_PackingList> {
  final Map<String, bool> _items = <String, bool>{
    'Thermal layers': true,
    'Wool socks': true,
    'Hand warmers': false,
    'Headlamp': false,
    'Camera and tripod': true,
  };
  bool _remind = true;

  @override
  Widget build(BuildContext context) {
    final Color label = CupertinoColors.label.resolveFrom(context);
    final Color secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Packing List',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: label,
            ),
          ),
          Text(
            '${_items.values.where((bool v) => v).length} of '
            '${_items.length} packed',
            style: TextStyle(fontSize: 17, color: secondary),
          ),
          const SizedBox(height: 16),
          for (final String item in _items.keys)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _items[item] = !_items[item]!),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(
                  children: <Widget>[
                    Icon(
                      _items[item]!
                          ? CupertinoIcons.checkmark_circle_fill
                          : CupertinoIcons.circle,
                      size: 26,
                      color: _items[item]!
                          ? CupertinoColors.systemBlue.resolveFrom(context)
                          : secondary,
                    ),
                    const SizedBox(width: 12),
                    Text(item, style: TextStyle(fontSize: 17, color: label)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Text(
                'Remind me the night before',
                style: TextStyle(fontSize: 17, color: label),
              ),
              const Spacer(),
              GlassSwitch(
                value: _remind,
                onChanged: (bool v) => setState(() => _remind = v),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
