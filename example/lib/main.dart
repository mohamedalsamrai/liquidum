import 'package:flutter/cupertino.dart';
import 'package:liquidum/liquidum.dart';

import 'feed.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const CupertinoApp(
      home: GlassTabScaffold(
glassColor: Color(0xffffffff),
indicatorColor: Color.fromARGB(126, 0, 204, 255),
lensColor: Color.fromARGB(124, 0, 204, 255),
        tabs: [
          GlassTab(
            icon: CupertinoIcons.house_fill,
            label: 'Home',
            page: Feed(title: 'Home'),
          ),
          GlassTab(
            icon: CupertinoIcons.square_grid_2x2_fill,
            label: 'New',
            page: Feed(title: 'New'),
          ),
          GlassTab(
            icon: CupertinoIcons.dot_radiowaves_left_right,
            label: 'Radio',
            badge: '3',
            page: Feed(title: 'Radio'),
          ),
          GlassTab(
            icon: CupertinoIcons.music_albums_fill,
            label: 'Library',
            page: Feed(title: 'Library'),
          ),
        ],
      ),
    );
  }
}
