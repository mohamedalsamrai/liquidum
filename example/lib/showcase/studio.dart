// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart';
import 'package:liquidum/liquidum.dart';

import 'art.dart';

/// The Glass tab: the material itself over a photo. Regular, clear, tinted
/// and dark glass, groups that melt, every kind of glass button, and
/// interactive glass.
class StudioPage extends StatefulWidget {
  const StudioPage({super.key});

  @override
  State<StudioPage> createState() => _StudioPageState();
}

class _StudioPageState extends State<StudioPage> {
  bool _more = true;
  bool _liked = true;

  @override
  Widget build(BuildContext context) {
    void tap() {}
    return GlassPage(
      title: 'Glass',
      largeTitle: true,
      actions: <GlassBarItem>[
        GlassBarItem(
          icon: CupertinoIcons.info,
          semanticLabel: 'About',
          onPressed: () => showGlassAlert(
            context: context,
            title: 'Liquid Glass',
            message:
                'Every piece of glass here is measured against UIKit on '
                'iOS 26.',
          ),
        ),
      ],
      child: Builder(
        builder: (BuildContext context) {
          final EdgeInsets pad = MediaQuery.paddingOf(context);
          return Stack(
            children: <Widget>[
              const Positioned.fill(child: Photo('jellyfish')),
              ListView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  pad.top + 4,
                  16,
                  pad.bottom + 24,
                ),
                children: <Widget>[
                  const _Caption('Material'),
                  const Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: <Widget>[
                      Glass(child: _Pill('Regular')),
                      Glass(style: GlassStyle.clear, child: _Pill('Clear')),
                      Glass(tint: Color(0xB3FF8D28), child: _Pill('Tinted')),
                      Glass(brightness: Brightness.dark, child: _Pill('Dark')),
                    ],
                  ),
                  const _Caption('Groups'),
                  Row(
                    children: <Widget>[
                      // Glass in a group melts where it comes close; glass
                      // appearing grows out of its neighbors.
                      GlassGroup(
                        spacing: 20,
                        child: Row(
                          children: <Widget>[
                            GlassButton(
                              icon: _more
                                  ? CupertinoIcons.xmark
                                  : CupertinoIcons.ellipsis,
                              onPressed: () => setState(() => _more = !_more),
                            ),
                            for (final IconData icon in const <IconData>[
                              CupertinoIcons.share,
                              CupertinoIcons.bookmark,
                              CupertinoIcons.trash,
                            ]) ...<Widget>[
                              const SizedBox(width: 6),
                              Glass(
                                visible: _more,
                                child: SizedBox.square(
                                  dimension: 34.33,
                                  child: _more
                                      ? Icon(
                                          icon,
                                          size: 18,
                                          color: const Color(0xFFFFFFFF),
                                        )
                                      : null,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const Spacer(),
                      const GlassGroup(
                        spacing: 24,
                        child: Row(
                          children: <Widget>[
                            Glass(child: SizedBox.square(dimension: 48)),
                            SizedBox(width: 4),
                            Glass(child: SizedBox.square(dimension: 60)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const _Caption('Buttons'),
                  Wrap(
                    spacing: 10,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      GlassButton(label: 'Glass', onPressed: tap),
                      GlassButton(
                        label: 'Prominent',
                        prominent: true,
                        onPressed: tap,
                      ),
                      GlassButton(
                        label: 'Clear',
                        style: GlassStyle.clear,
                        onPressed: tap,
                      ),
                      GlassButton(
                        label: 'Tinted',
                        prominent: true,
                        tint: const Color(0xFFFF8D28),
                        onPressed: tap,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      GlassButton(icon: CupertinoIcons.add, onPressed: tap),
                      // A touch opens the menu out of the button.
                      GlassButton(
                        label: 'Share',
                        icon: CupertinoIcons.share,
                        menu: <GlassMenuItem>[
                          GlassMenuItem(
                            label: 'Copy',
                            icon: CupertinoIcons.doc_on_doc,
                            onPressed: tap,
                          ),
                          GlassMenuItem(
                            label: 'Messages',
                            icon: CupertinoIcons.chat_bubble,
                            onPressed: tap,
                          ),
                          GlassMenuItem(
                            label: 'Mail',
                            icon: CupertinoIcons.mail,
                            onPressed: tap,
                          ),
                        ],
                      ),
                      GlassButton(
                        icon: _liked
                            ? CupertinoIcons.heart_fill
                            : CupertinoIcons.heart,
                        prominent: true,
                        tint: CupertinoColors.systemPink,
                        onPressed: () => setState(() => _liked = !_liked),
                      ),
                      GlassButton(
                        icon: CupertinoIcons.star_fill,
                        style: GlassStyle.clear,
                        onPressed: tap,
                      ),
                      GlassButton(
                        label: 'Magic',
                        icon: CupertinoIcons.sparkles,
                        prominent: true,
                        style: GlassStyle.clear,
                        onPressed: tap,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      for (final (String label, GlassButtonSize size)
                          in const <(String, GlassButtonSize)>[
                            ('Mini', GlassButtonSize.mini),
                            ('Small', GlassButtonSize.small),
                            ('Medium', GlassButtonSize.medium),
                            ('Large', GlassButtonSize.large),
                          ])
                        GlassButton(label: label, size: size, onPressed: tap),
                    ],
                  ),
                  const _Caption('Interactive'),
                  // Any glass can take a finger: it swells, glows and
                  // stretches toward a drag.
                  Glass(
                    interactive: true,
                    radius: 30,
                    child: SizedBox(
                      height: 96,
                      child: Center(
                        child: Text(
                          'Press and drag',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: CupertinoColors.label.resolveFrom(context),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A caption over the photo.
class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 0, 10),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
          color: Color(0xE6FFFFFF),
        ),
      ),
    );
  }
}

/// A label inside a capsule of small glass.
class _Pill extends StatelessWidget {
  const _Pill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
      child: GlassLabel(text),
    );
  }
}
