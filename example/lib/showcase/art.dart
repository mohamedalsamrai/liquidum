// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart';
import 'package:liquidum/liquidum.dart';

/// One of the showcase's photos (`assets/photos`, from Unsplash: see
/// `assets/photos/CREDITS.md`), filling its box.
class Photo extends StatelessWidget {
  const Photo(this.name, {super.key, this.radius = 0});

  final String name;

  /// Rounds its corners (continuous, as iOS's).
  final double radius;

  @override
  Widget build(BuildContext context) {
    final Widget image = Image.asset(
      'assets/photos/$name.jpg',
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
    );
    if (radius == 0) {
      return image;
    }
    return ClipRSuperellipse(
      borderRadius: BorderRadius.circular(radius),
      child: image,
    );
  }
}

/// A place to visit.
@immutable
class Place {
  const Place({
    required this.name,
    required this.country,
    required this.kind,
    required this.days,
    required this.price,
    required this.temperature,
    required this.photo,
    required this.about,
  });

  final String name;
  final String country;
  final String kind;
  final int days;
  final int price;
  final int temperature;
  final String photo;
  final String about;
}

const List<Place> places = <Place>[
  Place(
    name: 'Norwegian Fjords',
    country: 'Norway',
    kind: 'Coast',
    days: 6,
    price: 1290,
    temperature: 14,
    photo: 'fjords',
    about:
        'Sheer granite cliffs over deep blue water, a ferry ride from '
        'Stavanger. Hike to the edge at sunrise, before the boats arrive.',
  ),
  Place(
    name: 'Matterhorn',
    country: 'Switzerland',
    kind: 'Mountains',
    days: 5,
    price: 1180,
    temperature: 11,
    photo: 'matterhorn',
    about:
        'The pyramid peak above Zermatt, its larch forests and car-free '
        'streets. A cog railway climbs to the glaciers.',
  ),
  Place(
    name: 'Yosemite',
    country: 'California',
    kind: 'Mountains',
    days: 4,
    price: 720,
    temperature: 22,
    photo: 'yosemite',
    about:
        'Granite walls, giant sequoias and waterfalls along the Merced '
        'River, with meadows that glow at dusk.',
  ),
  Place(
    name: 'Isle of Skye',
    country: 'Scotland',
    kind: 'Mountains',
    days: 5,
    price: 890,
    temperature: 13,
    photo: 'skye',
    about:
        'The ridges of the Quiraing, fairy pools and lighthouses on '
        'wind-swept cliffs over the Atlantic.',
  ),
  Place(
    name: 'Lisbon',
    country: 'Portugal',
    kind: 'Cities',
    days: 4,
    price: 640,
    temperature: 24,
    photo: 'lisbon',
    about:
        'Yellow trams climb tiled hills to viewpoints over the Tagus, '
        'with fado and pastries in every street.',
  ),
  Place(
    name: 'Neuschwanstein',
    country: 'Germany',
    kind: 'Mountains',
    days: 3,
    price: 560,
    temperature: 18,
    photo: 'neuschwanstein',
    about:
        'A fairy-tale castle on a crag above Alpine lakes, in the '
        'foothills of southern Bavaria.',
  ),
  Place(
    name: 'Lake Wānaka',
    country: 'New Zealand',
    kind: 'Lakes',
    days: 7,
    price: 1540,
    temperature: 17,
    photo: 'wanaka',
    about:
        'A willow standing in still water under the Southern Alps, an '
        'hour from Queenstown.',
  ),
  Place(
    name: 'San Francisco',
    country: 'California',
    kind: 'Cities',
    days: 3,
    price: 690,
    temperature: 19,
    photo: 'golden_gate',
    about:
        'Fog rolling under the Golden Gate, cable cars on steep hills '
        'and Pacific beaches at the end of the park.',
  ),
  Place(
    name: 'Cinque Terre',
    country: 'Italy',
    kind: 'Coast',
    days: 4,
    price: 780,
    temperature: 25,
    photo: 'cinque_terre',
    about:
        'Five pastel villages on cliffs above the Ligurian Sea, joined by '
        'trails through vineyards.',
  ),
];

/// The trip on the Plan tab.
const Place trip = Place(
  name: 'Tromsø',
  country: 'Norway',
  kind: 'Trips',
  days: 7,
  price: 1460,
  temperature: -4,
  photo: 'aurora',
  about: 'Northern lights, huskies and fjords above the Arctic Circle.',
);

/// A section's title over content.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
          color: CupertinoColors.label.resolveFrom(context),
        ),
      ),
    );
  }
}

/// An icon and a short text in the colors of the small glass under them:
/// black on light glass and white on dark, turning with it as it adapts to
/// what is behind it.
class GlassLabel extends StatelessWidget {
  const GlassLabel(this.text, {super.key, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return GlassBrightness(
      builder: (BuildContext context, double dark, Widget? child) {
        final Color color = Color.lerp(
          const Color(0xFF000000),
          const Color(0xFFFFFFFF),
          dark,
        )!;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
            ],
            Text(
              text,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        );
      },
    );
  }
}
