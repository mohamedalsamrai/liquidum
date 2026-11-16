// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart';
import 'package:liquidum/liquidum.dart';

import 'art.dart';

/// The Home tab: rooms and devices on panels of glass over a wallpaper,
/// with switches, sliders, a segmented control and grouped buttons.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _scene = 'Evening';
  bool _lights = true;
  double _brightness = 0.7;
  double _warmth = 0.35;
  int _temperature = 21;
  bool _playing = true;
  final Map<String, bool> _devices = <String, bool>{
    'Floor Lamp': true,
    'Ceiling Fan': false,
    'Blinds': true,
    'Front Door': true,
  };

  @override
  Widget build(BuildContext context) {
    return GlassPage(
      title: 'Home',
      largeTitle: true,
      actions: <GlassBarItem>[
        GlassBarItem(
          icon: CupertinoIcons.add,
          semanticLabel: 'Add',
          menu: <GlassMenuItem>[
            GlassMenuItem(
              label: 'Add Accessory',
              icon: CupertinoIcons.lightbulb,
              onPressed: () {},
            ),
            GlassMenuItem(
              label: 'Add Scene',
              icon: CupertinoIcons.sparkles,
              onPressed: () {},
            ),
            GlassMenuItem(
              label: 'Add Room',
              icon: CupertinoIcons.square_grid_2x2,
              onPressed: () {},
            ),
          ],
        ),
      ],
      child: Builder(
        builder: (BuildContext context) {
          final EdgeInsets pad = MediaQuery.paddingOf(context);
          return Stack(
            children: <Widget>[
              // A photo for the light, another for the dark.
              Positioned.fill(
                child: Photo(
                  CupertinoTheme.brightnessOf(context) == Brightness.dark
                      ? 'milky_way'
                      : 'sunset',
                ),
              ),
              ListView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  pad.top + 4,
                  16,
                  pad.bottom + 24,
                ),
                children: <Widget>[
                  // Small glass: light or dark with what is behind it.
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      _Status(
                        icon: CupertinoIcons.thermometer,
                        text: '$_temperature° inside',
                      ),
                      _Status(
                        icon: CupertinoIcons.lightbulb_fill,
                        text: _lights ? '3 lights on' : 'Lights off',
                      ),
                      const _Status(
                        icon: CupertinoIcons.lock_fill,
                        text: 'Locked',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: GlassSegmentedControl<String>(
                      children: const <String, Widget>{
                        'Morning': Text('Morning'),
                        'Day': Text('Day'),
                        'Evening': Text('Evening'),
                        'Night': Text('Night'),
                      },
                      groupValue: _scene,
                      onValueChanged: (String s) => setState(() => _scene = s),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _Panel(
                    child: Column(
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            const _Badge(
                              icon: CupertinoIcons.lightbulb_fill,
                              color: Color(0xFFFFB340),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _Title(
                                'Living Room',
                                _lights
                                    ? '${(_brightness * 100).round()}% · warm'
                                    : 'Off',
                              ),
                            ),
                            GlassSwitch(
                              value: _lights,
                              onChanged: (bool v) =>
                                  setState(() => _lights = v),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _SliderRow(
                          icon: CupertinoIcons.sun_max_fill,
                          child: GlassSlider(
                            value: _brightness,
                            onChanged: (double v) =>
                                setState(() => _brightness = v),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _SliderRow(
                          icon: CupertinoIcons.flame_fill,
                          child: GlassSlider(
                            value: _warmth,
                            activeColor: const Color(0xFFFF8D28),
                            onChanged: (double v) =>
                                setState(() => _warmth = v),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _Panel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const _Title('Climate', 'Heating'),
                              const SizedBox(height: 6),
                              Text(
                                '$_temperature°',
                                style: TextStyle(
                                  fontSize: 44,
                                  fontWeight: FontWeight.w300,
                                  color: CupertinoColors.label.resolveFrom(
                                    context,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              // In a group, nearby glass melts together.
                              GlassGroup(
                                spacing: 16,
                                child: Row(
                                  children: <Widget>[
                                    GlassButton(
                                      icon: CupertinoIcons.minus,
                                      onPressed: () =>
                                          setState(() => _temperature--),
                                    ),
                                    const SizedBox(width: 8),
                                    GlassButton(
                                      icon: CupertinoIcons.add,
                                      onPressed: () =>
                                          setState(() => _temperature++),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _Panel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const _Title('Speakers', 'Kitchen'),
                              const SizedBox(height: 10),
                              Container(
                                height: 50,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  gradient: const LinearGradient(
                                    colors: <Color>[
                                      Color(0xFFFF6FA5),
                                      Color(0xFF8B7CFF),
                                    ],
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: const Text(
                                  'Late Night Radio',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFFFFFFF),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: <Widget>[
                                  GlassButton(
                                    icon: CupertinoIcons.backward_fill,
                                    style: GlassStyle.clear,
                                    size: GlassButtonSize.small,
                                    onPressed: () {},
                                  ),
                                  GlassButton(
                                    icon: _playing
                                        ? CupertinoIcons.pause_fill
                                        : CupertinoIcons.play_fill,
                                    prominent: true,
                                    onPressed: () =>
                                        setState(() => _playing = !_playing),
                                  ),
                                  GlassButton(
                                    icon: CupertinoIcons.forward_fill,
                                    style: GlassStyle.clear,
                                    size: GlassButtonSize.small,
                                    onPressed: () {},
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  for (final List<String> row in const <List<String>>[
                    <String>['Floor Lamp', 'Ceiling Fan'],
                    <String>['Blinds', 'Front Door'],
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Row(
                        children: <Widget>[
                          for (final String name in row) ...<Widget>[
                            if (name != row.first) const SizedBox(width: 14),
                            Expanded(
                              child: _Device(
                                name: name,
                                on: _devices[name]!,
                                onChanged: (bool v) =>
                                    setState(() => _devices[name] = v),
                              ),
                            ),
                          ],
                        ],
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

/// A panel of large glass: it follows the system's light or dark.
class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: 28,
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.title, this.subtitle);

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: CupertinoColors.label.resolveFrom(context),
          ),
        ),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 14,
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(icon, size: 21, color: const Color(0xFFFFFFFF)),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({required this.icon, required this.child});

  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(
          icon,
          size: 20,
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
        ),
        const SizedBox(width: 10),
        Expanded(child: child),
      ],
    );
  }
}

/// A capsule of small glass with an icon and a status.
class _Status extends StatelessWidget {
  const _Status({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Glass(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: GlassLabel(text, icon: icon),
      ),
    );
  }
}

/// A device on interactive glass: it swells under a finger.
class _Device extends StatelessWidget {
  const _Device({
    required this.name,
    required this.on,
    required this.onChanged,
  });

  static const Map<String, (IconData, Color)> _looks =
      <String, (IconData, Color)>{
        'Floor Lamp': (CupertinoIcons.lightbulb_fill, Color(0xFFFFB340)),
        'Ceiling Fan': (CupertinoIcons.wind, Color(0xFF30B0C7)),
        'Blinds': (CupertinoIcons.sun_haze_fill, Color(0xFF5E5CE6)),
        'Front Door': (CupertinoIcons.lock_fill, Color(0xFF34C759)),
      };

  final String name;
  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color) = _looks[name]!;
    return Glass(
      radius: 26,
      interactive: true,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                _Badge(icon: icon, color: on ? color : const Color(0xFF8E8E93)),
                const Spacer(),
                GlassSwitch(value: on, onChanged: onChanged),
              ],
            ),
            const SizedBox(height: 14),
            _Title(name, on ? 'On' : 'Off'),
          ],
        ),
      ),
    );
  }
}
