// Liquidum's showcase: a small travel and home app that uses every widget
// in the package, light and dark.
//
//   flutter run -t lib/showcase.dart
//
// - Explore: GlassPage (a large title, a bar item with a menu), a
//   GlassSegmentedControl, a panel of Glass with GlassButtons over a photo,
//   GlassContextMenu on each place (hold one); a place's page has a back
//   button, a share action sheet, a menu and a toolbar whose Book item opens
//   a sheet with a GlassGroup.
// - Home: panels of large glass with GlassSwitch, GlassSlider, grouped
//   buttons and interactive glass over a photo for the light and one for
//   the dark.
// - Plan: showGlassPopover, showGlassActionSheet from a button (a popover),
//   showGlassSheet, GlassDatePicker (date and time), GlassEditMenu on the
//   notes (select a word), showGlassAlert with and without a text field.
// - Glass: regular, clear, tinted and dark glass, GlassGroup, every kind of
//   GlassButton, and interactive glass, over a photo.
// - Search: GlassTab.search, which opens into a search field.
//
// The photos are from Unsplash (assets/photos/CREDITS.md).

// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart';
import 'package:liquidum/liquidum.dart';

import 'showcase/explore.dart';
import 'showcase/home.dart';
import 'showcase/plan.dart';
import 'showcase/search.dart';
import 'showcase/studio.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Glass.precache();
  runApp(const ShowcaseApp());
}

class ShowcaseApp extends StatefulWidget {
  const ShowcaseApp({super.key});

  @override
  State<ShowcaseApp> createState() => _ShowcaseAppState();
}

class _ShowcaseAppState extends State<ShowcaseApp> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      title: 'Liquidum',
      debugShowCheckedModeBanner: false,
      home: GlassTabScaffold(
        tabs: <GlassTab>[
          const GlassTab(
            icon: CupertinoIcons.compass,
            selectedIcon: CupertinoIcons.compass_fill,
            label: 'Explore',
            page: ExplorePage(),
          ),
          const GlassTab(
            icon: CupertinoIcons.house_fill,
            label: 'Home',
            page: HomePage(),
          ),
          const GlassTab(
            icon: CupertinoIcons.calendar,
            label: 'Plan',
            badge: '2',
            page: PlanPage(),
          ),
          const GlassTab(
            icon: CupertinoIcons.circle_grid_hex_fill,
            label: 'Glass',
            page: StudioPage(),
          ),
          GlassTab.search(
            controller: _search,
            placeholder: 'Places, countries',
            page: SearchPage(query: _search),
          ),
        ],
      ),
    );
  }
}
