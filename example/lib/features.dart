// iOS 26's tab bar extras: a search tab that opens into a search field, a
// bottom accessory, and minimizing as a page scrolls. Run with
// `flutter run -t lib/features.dart`.
import 'package:flutter/cupertino.dart';
import 'package:liquidum/liquidum.dart';

void main() => runApp(const FeaturesApp());

class FeaturesApp extends StatefulWidget {
  const FeaturesApp({super.key});

  @override
  State<FeaturesApp> createState() => _FeaturesAppState();
}

class _FeaturesAppState extends State<FeaturesApp> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      debugShowCheckedModeBanner: false,
      home: GlassTabScaffold(
        minimizeOnScroll: true,
        accessory: const Text('Now Playing'),
        tabs: [
          const GlassTab(
            icon: CupertinoIcons.house_fill,
            label: 'Home',
            page: Rows('Home'),
          ),
          const GlassTab(
            icon: CupertinoIcons.square_grid_2x2_fill,
            label: 'New',
            page: Rows('New'),
          ),
          const GlassTab(
            icon: CupertinoIcons.dot_radiowaves_left_right,
            label: 'Radio',
            page: Rows('Radio'),
          ),
          GlassTab.search(
            controller: _search,
            page: ListenableBuilder(
              listenable: _search,
              builder: (BuildContext context, _) =>
                  Rows('Result', filter: _search.text),
            ),
          ),
        ],
      ),
    );
  }
}

/// A long list, to scroll under the bar.
class Rows extends StatelessWidget {
  const Rows(this.title, {super.key, this.filter = ''});

  final String title;
  final String filter;

  @override
  Widget build(BuildContext context) {
    final List<int> rows = <int>[
      for (var i = 0; i < 100; i++)
        if (filter.isEmpty || '$i'.contains(filter)) i,
    ];
    return ListView.builder(
      itemCount: rows.length,
      itemExtent: 52,
      itemBuilder: (BuildContext context, int n) {
        final int i = rows[n];
        return Container(
          color: i % 3 == 0
              ? HSVColor.fromAHSV(1, (i * 47 % 360).toDouble(), 0.5, 0.95)
                    .toColor()
              : const Color(0xFFFFFFFF),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          alignment: Alignment.centerLeft,
          child: Text('$title $i'),
        );
      },
    );
  }
}
