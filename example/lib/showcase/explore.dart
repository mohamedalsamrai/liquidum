// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart';
import 'package:liquidum/liquidum.dart';

import 'art.dart';

/// The Explore tab: a navigation bar of glass with a sort menu, a segmented
/// control, a featured place under glass, and places with context menus.
class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key});

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  static const List<String> _kinds = <String>[
    'All',
    'Mountains',
    'Coast',
    'Cities',
  ];

  String _kind = 'All';
  String _sort = 'Popular';
  final Set<String> _saved = <String>{'Lofoten'};

  void _toggle(Place p) => setState(
    () => _saved.contains(p.name) ? _saved.remove(p.name) : _saved.add(p.name),
  );

  void _open(BuildContext context, Place p) {
    // Over the tab bar, as UIKit's hidesBottomBarWhenPushed.
    Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute<void>(
        builder: (BuildContext context) => PlacePage(place: p),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Place> shown = <Place>[
      for (final Place p in places)
        if (_kind == 'All' || p.kind == _kind) p,
    ];
    final Place featured = shown.first;
    final List<Place> rest = shown.skip(1).toList();
    return GlassPage(
      title: 'Explore',
      largeTitle: true,
      actions: <GlassBarItem>[
        GlassBarItem(
          icon: CupertinoIcons.line_horizontal_3_decrease,
          semanticLabel: 'Sort',
          menu: <GlassMenuItem>[
            for (final String by in const <String>[
              'Popular',
              'Nearest',
              'Price',
            ])
              GlassMenuItem(
                label: by,
                checked: _sort == by,
                onPressed: () => setState(() => _sort = by),
              ),
            const GlassMenuItem.divider(),
            GlassMenuItem.submenu(
              label: 'Season',
              icon: CupertinoIcons.sun_max,
              items: <GlassMenuItem>[
                for (final String s in const <String>[
                  'Spring',
                  'Summer',
                  'Autumn',
                  'Winter',
                ])
                  GlassMenuItem(label: s, onPressed: () {}),
              ],
            ),
            GlassMenuItem(
              label: 'Saved Only',
              icon: CupertinoIcons.heart,
              onPressed: () {},
            ),
          ],
        ),
        GlassBarItem(
          icon: CupertinoIcons.person_crop_circle,
          semanticLabel: 'Account',
          onPressed: () {},
        ),
      ],
      child: Builder(
        builder: (BuildContext context) {
          final EdgeInsets pad = MediaQuery.paddingOf(context);
          return ListView(
            padding: EdgeInsets.fromLTRB(16, pad.top + 4, 16, pad.bottom + 24),
            children: <Widget>[
              SizedBox(
                width: double.infinity,
                child: GlassSegmentedControl<String>(
                  children: <String, Widget>{
                    for (final String k in _kinds) k: Text(k),
                  },
                  groupValue: _kind,
                  onValueChanged: (String k) => setState(() => _kind = k),
                ),
              ),
              const SizedBox(height: 16),
              _Featured(
                place: featured,
                saved: _saved.contains(featured.name),
                onSave: () => _toggle(featured),
                onOpen: () => _open(context, featured),
              ),
              const SizedBox(height: 28),
              const SectionTitle('Popular this month'),
              for (var i = 0; i < rest.length; i += 2)
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      for (final int j in <int>[i, i + 1]) ...<Widget>[
                        if (j > i) const SizedBox(width: 14),
                        Expanded(
                          child: j < rest.length
                              ? _PlaceTile(
                                  place: rest[j],
                                  saved: _saved.contains(rest[j].name),
                                  onSave: () => _toggle(rest[j]),
                                  onOpen: () => _open(context, rest[j]),
                                )
                              : const SizedBox(),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// The first place: its art with a clear glass button and a panel of glass.
class _Featured extends StatelessWidget {
  const _Featured({
    required this.place,
    required this.saved,
    required this.onSave,
    required this.onOpen,
  });

  final Place place;
  final bool saved;
  final VoidCallback onSave;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 440,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: GestureDetector(
              onTap: onOpen,
              child: Photo(place.photo, radius: 32),
            ),
          ),
          Positioned(
            top: 14,
            right: 14,
            child: GlassButton(
              icon: saved ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
              style: GlassStyle.clear,
              onPressed: onSave,
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Glass(
              radius: 22,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            place.name,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                              color: CupertinoColors.label.resolveFrom(context),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${place.country} · ${place.days} days · '
                            'from \$${place.price}',
                            style: TextStyle(
                              fontSize: 15,
                              color: CupertinoColors.secondaryLabel.resolveFrom(
                                context,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    GlassButton(
                      label: 'Plan',
                      prominent: true,
                      onPressed: onOpen,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A place in the grid: hold it for its context menu.
class _PlaceTile extends StatelessWidget {
  const _PlaceTile({
    required this.place,
    required this.saved,
    required this.onSave,
    required this.onOpen,
  });

  final Place place;
  final bool saved;
  final VoidCallback onSave;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          height: 200,
          child: GlassContextMenu(
            items: <GlassMenuItem>[
              GlassMenuItem(
                label: saved ? 'Saved' : 'Save',
                icon: saved ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
                onPressed: onSave,
              ),
              GlassMenuItem(
                label: 'Share',
                icon: CupertinoIcons.share,
                onPressed: () {},
              ),
              GlassMenuItem(
                label: 'Show on Map',
                icon: CupertinoIcons.map,
                onPressed: () {},
              ),
              const GlassMenuItem.divider(),
              GlassMenuItem(
                label: 'Not Interested',
                icon: CupertinoIcons.hand_thumbsdown,
                destructive: true,
                onPressed: () {},
              ),
            ],
            child: GestureDetector(
              onTap: onOpen,
              child: Photo(place.photo, radius: 22),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            place.name,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: CupertinoColors.label.resolveFrom(context),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            '${place.country} · from \$${place.price}',
            style: TextStyle(
              fontSize: 14,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
        ),
      ],
    );
  }
}

/// A place's page: its art under the navigation bar, glass chips over it,
/// a menu and a toolbar whose Book item opens a sheet.
class PlacePage extends StatefulWidget {
  const PlacePage({super.key, required this.place});

  final Place place;

  @override
  State<PlacePage> createState() => _PlacePageState();
}

class _PlacePageState extends State<PlacePage> {
  bool _saved = false;

  @override
  Widget build(BuildContext context) {
    final Place p = widget.place;
    final Color secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return GlassPage(
      title: p.name,
      onBack: () => Navigator.of(context).pop(),
      actions: <GlassBarItem>[
        GlassBarItem(
          icon: CupertinoIcons.share,
          semanticLabel: 'Share',
          onPressed: () => showGlassActionSheet(
            context: context,
            title: 'Share ${p.name}',
            actions: const <GlassAlertAction>[
              GlassAlertAction(label: 'Messages'),
              GlassAlertAction(label: 'Mail'),
              GlassAlertAction(label: 'Copy Link'),
              GlassAlertAction(label: 'Cancel', cancel: true),
            ],
          ),
        ),
        GlassBarItem(
          icon: CupertinoIcons.ellipsis,
          semanticLabel: 'More',
          menu: <GlassMenuItem>[
            GlassMenuItem(
              label: 'Add to Trip',
              icon: CupertinoIcons.add,
              onPressed: () {},
            ),
            GlassMenuItem(
              label: 'Directions',
              icon: CupertinoIcons.location_fill,
              onPressed: () {},
            ),
            const GlassMenuItem.divider(),
            GlassMenuItem(
              label: 'Report a Problem',
              icon: CupertinoIcons.exclamationmark_bubble,
              onPressed: () {},
            ),
          ],
        ),
      ],
      toolbar: <GlassBarItem>[
        GlassBarItem(
          icon: _saved ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
          semanticLabel: 'Save',
          onPressed: () => setState(() => _saved = !_saved),
        ),
        GlassBarItem(
          icon: CupertinoIcons.map,
          semanticLabel: 'Map',
          onPressed: () {},
        ),
        const GlassBarItem.space(),
        GlassBarItem(
          label: 'Book',
          prominent: true,
          onPressed: () => showGlassSheet<void>(
            context: context,
            builder: (BuildContext context) => BookingSheet(place: p),
          ),
        ),
      ],
      child: Builder(
        builder: (BuildContext context) {
          final EdgeInsets pad = MediaQuery.paddingOf(context);
          return ListView(
            // The art runs under the navigation bar.
            padding: EdgeInsets.only(bottom: pad.bottom + 24),
            children: <Widget>[
              SizedBox(
                height: 520,
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(child: Photo(p.photo)),
                    Positioned(
                      left: 16,
                      bottom: 16,
                      child: Row(
                        children: <Widget>[
                          _Chip(
                            icon: CupertinoIcons.sun_max_fill,
                            text: '${p.temperature}°',
                          ),
                          const SizedBox(width: 8),
                          _Chip(
                            icon: CupertinoIcons.calendar,
                            text: '${p.days} days',
                          ),
                          const SizedBox(width: 8),
                          _Chip(
                            icon: CupertinoIcons.airplane,
                            text: 'from \$${p.price}',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      p.name,
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.6,
                        color: CupertinoColors.label.resolveFrom(context),
                      ),
                    ),
                    Text(
                      p.country,
                      style: TextStyle(fontSize: 17, color: secondary),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      p.about,
                      style: TextStyle(
                        fontSize: 17,
                        height: 1.35,
                        color: CupertinoColors.label.resolveFrom(context),
                      ),
                    ),
                    const SizedBox(height: 28),
                    const SectionTitle('You may also like'),
                    SizedBox(
                      height: 120,
                      child: Row(
                        children: <Widget>[
                          for (final (int i, Place o)
                              in places
                                  .where((Place o) => o != p)
                                  .take(3)
                                  .indexed) ...<Widget>[
                            if (i > 0) const SizedBox(width: 10),
                            Expanded(child: Photo(o.photo, radius: 18)),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A capsule of small glass with an icon and a short text.
class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Glass(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: GlassLabel(text, icon: icon),
      ),
    );
  }
}

/// The sheet the Book item opens: guests in a glass group, a segmented
/// control and a large prominent button.
class BookingSheet extends StatefulWidget {
  const BookingSheet({super.key, required this.place});

  final Place place;

  @override
  State<BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends State<BookingSheet> {
  int _guests = 2;
  String _room = 'Comfort';

  @override
  Widget build(BuildContext context) {
    final Place p = widget.place;
    final Color label = CupertinoColors.label.resolveFrom(context);
    final Color secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final int total =
        p.price * _guests +
        (_room == 'Suite'
            ? 400
            : _room == 'Comfort'
            ? 150
            : 0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Book ${p.name}',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: label,
            ),
          ),
          Text(
            '${p.days} days · ${p.country}',
            style: TextStyle(fontSize: 17, color: secondary),
          ),
          const SizedBox(height: 24),
          Row(
            children: <Widget>[
              Text('Guests', style: TextStyle(fontSize: 17, color: label)),
              const Spacer(),
              // Two buttons in a group melt into one capsule.
              GlassGroup(
                spacing: 12,
                child: Row(
                  children: <Widget>[
                    GlassButton(
                      icon: CupertinoIcons.minus,
                      onPressed: _guests > 1
                          ? () => setState(() => _guests--)
                          : null,
                    ),
                    SizedBox(
                      width: 44,
                      child: Text(
                        '$_guests',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: label,
                        ),
                      ),
                    ),
                    GlassButton(
                      icon: CupertinoIcons.add,
                      onPressed: () => setState(() => _guests++),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: GlassSegmentedControl<String>(
              children: const <String, Widget>{
                'Standard': Text('Standard'),
                'Comfort': Text('Comfort'),
                'Suite': Text('Suite'),
              },
              groupValue: _room,
              onValueChanged: (String r) => setState(() => _room = r),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: <Widget>[
              Text('Total', style: TextStyle(fontSize: 17, color: secondary)),
              const Spacer(),
              Text(
                '\$$total',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: label,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: GlassButton(
              label: 'Reserve',
              prominent: true,
              size: GlassButtonSize.large,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}
