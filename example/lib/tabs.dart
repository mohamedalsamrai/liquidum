import 'package:flutter/cupertino.dart';
import 'package:liquidum/liquidum.dart';

import 'sf_symbol.dart';

/// A tab of the example apps, with what each bar needs to show it.
class TabSpec {
  const TabSpec({required this.icon, required this.label, required this.symbol});

  /// Stand-in where SF Symbols are not available.
  final IconData icon;
  final String label;

  /// SF Symbol name, for the native bar and for Liquidum's bar on iOS.
  final String symbol;

  /// The tab for Liquidum's [GlassTabBar], drawn with UIKit's own symbol.
  GlassTabItem get glassItem =>
      GlassTabItem(icon: SfSymbol(symbol, fallback: icon), label: label);
}

const tabs = <TabSpec>[
  TabSpec(icon: CupertinoIcons.house_fill, label: 'Home', symbol: 'house.fill'),
  TabSpec(
    icon: CupertinoIcons.square_grid_2x2_fill,
    label: 'New',
    symbol: 'square.grid.2x2.fill',
  ),
  TabSpec(
    icon: CupertinoIcons.dot_radiowaves_left_right,
    label: 'Radio',
    symbol: 'dot.radiowaves.left.and.right',
  ),
  TabSpec(
    icon: CupertinoIcons.music_albums_fill,
    label: 'Library',
    symbol: 'music.note.square.stack.fill',
  ),
];
