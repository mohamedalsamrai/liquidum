import 'package:flutter/cupertino.dart';

/// Colorful, high-contrast content, so the glass has something to bend.
/// Tapping a card opens it in the tab's own navigator, under the bar.
class Feed extends StatelessWidget {
  const Feed({super.key, required this.title, this.query = ''});

  final String title;

  /// Shows only the albums whose names contain it, as a search page.
  final String query;

  @override
  Widget build(BuildContext context) {
    final EdgeInsets padding = MediaQuery.paddingOf(context);
    final List<int> albums = <int>[
      for (var i = 0; i < 24; i++)
        if ('Album ${i + 1}'.toLowerCase().contains(query.toLowerCase())) i,
    ];
    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: EdgeInsets.fromLTRB(20, padding.top + 56, 20, 12),
          sliver: SliverToBoxAdapter(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.bold,
                color: CupertinoColors.label.resolveFrom(context),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, padding.bottom + 20),
          sliver: SliverGrid.builder(
            itemCount: albums.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.8,
            ),
            itemBuilder: (BuildContext context, int n) => GestureDetector(
              onTap: () => Navigator.of(context).push(
                CupertinoPageRoute<void>(
                  builder: (BuildContext context) => _Detail(index: albums[n]),
                ),
              ),
              child: _Card(index: albums[n]),
            ),
          ),
        ),
      ],
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(middle: Text('Album ${index + 1}')),
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          MediaQuery.paddingOf(context).top + 20,
          20,
          MediaQuery.paddingOf(context).bottom + 20,
        ),
        children: <Widget>[
          AspectRatio(aspectRatio: 1, child: _Card(index: index, large: true)),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.index, this.large = false});

  final int index;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final double hue = (index * 47) % 360;
    final Widget art = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            HSVColor.fromAHSV(1, hue, 0.75, 0.95).toColor(),
            HSVColor.fromAHSV(1, (hue + 60) % 360, 0.9, 0.55).toColor(),
          ],
        ),
      ),
      child: Center(
        child: Text(
          '${index + 1}',
          style: TextStyle(
            fontSize: large ? 120 : 64,
            fontWeight: FontWeight.w800,
            color: const Color(0xE6FFFFFF),
          ),
        ),
      ),
    );
    if (large) {
      return art;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: art),
        const SizedBox(height: 6),
        Text(
          'Album ${index + 1}',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: CupertinoColors.label.resolveFrom(context),
          ),
        ),
        Text(
          'Artist',
          style: TextStyle(
            fontSize: 15,
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
        ),
      ],
    );
  }
}
