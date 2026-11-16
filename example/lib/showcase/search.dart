// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart';

import 'art.dart';
import 'explore.dart';

/// The search tab's page: places that match the search field's text.
class SearchPage extends StatelessWidget {
  const SearchPage({super.key, required this.query});

  /// The search field's text (the tab bar's search field edits it).
  final TextEditingController query;

  @override
  Widget build(BuildContext context) {
    final EdgeInsets pad = MediaQuery.paddingOf(context);
    final Color label = CupertinoColors.label.resolveFrom(context);
    final Color secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: query,
      builder: (BuildContext context, TextEditingValue value, Widget? child) {
        final String q = value.text.trim().toLowerCase();
        final List<Place> found = <Place>[
          for (final Place p in places)
            if (q.isEmpty ||
                p.name.toLowerCase().contains(q) ||
                p.country.toLowerCase().contains(q) ||
                p.kind.toLowerCase().contains(q))
              p,
        ];
        return ListView(
          padding: EdgeInsets.fromLTRB(16, pad.top + 12, 16, pad.bottom + 20),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 16),
              child: Text(
                'Search',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                  color: label,
                ),
              ),
            ),
            if (q.isEmpty) ...<Widget>[
              const SectionTitle('Recently viewed'),
              SizedBox(
                height: 168,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: <Widget>[
                    for (final Place p in places.reversed.take(5))
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: SizedBox(
                          width: 128,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              SizedBox(
                                height: 128,
                                child: Photo(p.photo, radius: 20),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                p.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 15, color: label),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const SectionTitle('All places'),
            ],
            for (final Place p in found)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context, rootNavigator: true).push(
                  CupertinoPageRoute<void>(
                    builder: (BuildContext context) => PlacePage(place: p),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    children: <Widget>[
                      SizedBox.square(
                        dimension: 60,
                        child: Photo(p.photo, radius: 14),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              p.name,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: label,
                              ),
                            ),
                            Text(
                              '${p.country} · ${p.kind}',
                              style: TextStyle(fontSize: 15, color: secondary),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        CupertinoIcons.chevron_forward,
                        size: 18,
                        color: CupertinoColors.tertiaryLabel.resolveFrom(
                          context,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (found.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Center(
                  child: Text(
                    'No places match “${value.text}”.',
                    style: TextStyle(fontSize: 17, color: secondary),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
