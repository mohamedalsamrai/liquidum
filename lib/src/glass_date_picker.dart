part of 'glass.dart';

/// What a [GlassDatePicker] shows and edits.
enum GlassDatePickerMode {
  /// The date: a tap opens the calendar.
  date,

  /// The time of day: a tap opens the time wheels.
  time,

  /// Both, side by side.
  dateAndTime,
}

/// UIKit's compact date picker (`UIDatePicker`, `.compact`) on iOS 26.5:
/// the date, the time or both on gray capsules; a tap opens the calendar
/// (or the time wheels) on a platter of glass beside them, grown out of the
/// label on UIKit's spring and folded back into it.
///
/// The calendar is UIKit's (`UICalendarView`): the month with arrows to the
/// next and previous ones (or a swipe), the days with today in blue and the
/// chosen day on a circle, and the month and year on wheels from a tap on
/// the title. Choosing a day calls [onChanged] and leaves the calendar
/// open; a tap anywhere else closes it.
///
/// ```dart
/// GlassDatePicker(
///   value: date,
///   onChanged: (DateTime d) => setState(() => date = d),
/// )
/// ```
class GlassDatePicker extends StatefulWidget {
  const GlassDatePicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.mode = GlassDatePickerMode.date,
    this.firstDate,
    this.lastDate,
  });

  /// The date and time shown.
  final DateTime value;

  /// Called with the new date and time (null disables the picker).
  final ValueChanged<DateTime>? onChanged;

  final GlassDatePickerMode mode;

  /// The earliest day that can be chosen (any, by default).
  final DateTime? firstDate;

  /// The latest day that can be chosen (any, by default).
  final DateTime? lastDate;

  @override
  State<GlassDatePicker> createState() => _GlassDatePickerState();
}

// UIKit's compact date picker and its overlay (iOS 26.5, en_US), measured
// on the simulator: see doc/comparison/glass-widgets/stage6/metrics.txt.
abstract final class _DateMetrics {
  // The compact capsules: 17pt text, 7pt above and below, 12pt either side
  // (36pt tall for the time, and for the date beside it, 4pt apart).
  static const double capsuleHeight = 34.33;
  static const double pairHeight = 36;
  static const double capsulePad = 12;
  static const double capsuleGap = 4;

  // The platters, and where they go: the edge nearer the label 6pt past
  // its middle (it covers the label's lower or upper part), the right edge
  // 6pt short of its middle, kept 20pt from the screen's sides; above the
  // label when below would come within 90pt of the safe area's bottom.
  static const Size calendar = Size(320, 332);
  static const Size wheels = Size(232, 204);
  static const double radius = 28;
  static const double below = 6.17;
  static const double above = 5.83;
  static const double side = 6;
  static const double edge = 20;
  static const double room = 90;

  // Open and close: one spring p; the platter scales 0.2 + 0.8p about the
  // label's middle on its near edge, shows p, and its glass unfolds from
  // that edge, 0.15 + 0.85p of its height.
  static const double start = 0.2;
  static const double fold = 0.15;
  static const double openResponse = 2 * math.pi / 19.56;
  static const double openDamping = 0.798;
  static const double closeResponse = 2 * math.pi / 17.8;
  static const double closeDamping = 0.846;

  // The calendar.
  static const double headerTop = 16;
  static const double headerHeight = 37.67;
  static const double titleLeft = 16;
  static const double titleInset = 4;
  static const double arrowLeft = 231.33;
  static const double arrowWidth = 43.33;
  static const double weekdayTop = 69.67;
  static const double weekdayHeight = 15.67;
  static const double weekdayLeft = 16;
  static const double weekdayWidth = 31.67;
  static const double weekdayStep = 42.72;
  static const double gridTop = 85.33;
  static const double gridHeight = 685 / 3;
  static const double cellLeft = 10.33;
  static const double cellWidth = 42.67;
  static const Duration page = Duration(milliseconds: 300);
  static const Duration swap = Duration(milliseconds: 250);
  static const Rect monthWheels = Rect.fromLTWH(16, 76.83, 288, 216);

  // The time wheels, inside their platter.
  static const Rect timeWheels = Rect.fromLTWH(7, 16, 218, 172);

  // The wheels' selection: a 32pt capsule 16pt in from the platter's sides,
  // in the secondary system fill. UIKit's month and year columns: the
  // months left-aligned 44pt into the wheels, in a column 155pt wide (its
  // magnified row grows about the column's middle), the years 34pt into
  // the next, 111pt wide.
  static const double band = 32;
  static const double bandInset = 16;
  static Color bandFill(bool dark) =>
      dark ? const Color(0x52787880) : const Color(0x29787880);
  static const double monthColumn = 155;
  static const double monthText = 44;
  static const double yearColumn = 111;
  static const double yearText = 34;
  // The time: the hours right-aligned 44.3pt into the wheels, the minutes
  // centered at 103.7, AM and PM at 166.7.
  static const double hourColumn = 60;
  static const double hourRight = 44.3;
  static const double minuteColumn = 87.4;
  static const double periodColumn = 38.6;
  static const TextStyle wheelText = TextStyle(
    fontSize: 21,
    letterSpacing: -0.6,
  );
  static const double wheelRow = 32;
  static const double wheelSqueeze = 1.25;
  static const double wheelMagnification = 2.35 / 2.1;

  // SF Pro's tracking at these sizes.
  static const TextStyle capsuleText = TextStyle(
    fontSize: 17,
    letterSpacing: -0.43,
  );
  static const TextStyle title = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.43,
  );
  static const TextStyle weekday = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.08,
  );
  static const TextStyle day = TextStyle(fontSize: 20, letterSpacing: -0.45);

  static Color label(bool dark) =>
      dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
  // The weekdays: the secondary label color, which UIKit's vibrancy darkens
  // over light glass to about three quarters of the label's ink.
  static Color secondary(bool dark) =>
      dark ? const Color(0x99EBEBF5) : const Color(0xBF3C3C43);
  static Color tertiary(bool dark) =>
      dark ? const Color(0x4DEBEBF5) : const Color(0x4D3C3C43);
  static Color blue(bool dark) =>
      dark ? const Color(0xFF0091FF) : const Color(0xFF0088FF);
  static Color capsuleFill(bool dark) =>
      dark ? const Color(0x3D767680) : const Color(0x1F767680);
  static Color selectedFill(bool dark) => blue(dark).withValues(alpha: 0.12);

  // The rows of the month's grid share its height, to the pixel (5 rows of
  // 45.67, 6 of 38).
  static double rowHeight(int rows) => (gridHeight / rows * 3).round() / 3;
}

const List<String> _monthNames = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const List<String> _weekdayNames = <String>[
  'SUN',
  'MON',
  'TUE',
  'WED',
  'THU',
  'FRI',
  'SAT',
];

String _dateText(DateTime d) =>
    '${_monthNames[d.month - 1].substring(0, 3)} ${d.day}, ${d.year}';

String _timeText(DateTime d, bool use24) {
  final String mm = d.minute.toString().padLeft(2, '0');
  if (use24) {
    return '${d.hour.toString().padLeft(2, '0')}:$mm';
  }
  final int h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:$mm ${d.hour < 12 ? 'AM' : 'PM'}';
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

int _monthIndex(DateTime d) => d.year * 12 + d.month - 1;

DateTime _monthAt(int index) => DateTime(index ~/ 12, index % 12 + 1);

enum _DateOverlayKind { calendar, wheels }

class _GlassDatePickerState extends State<GlassDatePicker> {
  final GlobalKey _dateKey = GlobalKey();
  final GlobalKey _timeKey = GlobalKey();
  late final ValueNotifier<DateTime> _value = ValueNotifier<DateTime>(
    widget.value,
  );
  OverlayEntry? _entry;
  _DateOverlayKind? _open;
  bool _closing = false;

  @override
  void didUpdateWidget(GlassDatePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    _value.value = widget.value;
  }

  @override
  void dispose() {
    _removeOverlay();
    _value.dispose();
    super.dispose();
  }

  void _removeOverlay() {
    final OverlayEntry? entry = _entry;
    _entry = null;
    if (entry != null) {
      entry.remove();
      entry.dispose();
    }
  }

  void _show(_DateOverlayKind kind, GlobalKey source) {
    if (_entry != null || widget.onChanged == null) {
      return;
    }
    final OverlayState overlay = Overlay.of(context, rootOverlay: true);
    final RenderBox overlayBox =
        overlay.context.findRenderObject()! as RenderBox;
    final RenderBox box =
        source.currentContext!.findRenderObject()! as RenderBox;
    final Rect label = MatrixUtils.transformRect(
      box.getTransformTo(overlayBox),
      Offset.zero & box.size,
    );
    _entry = OverlayEntry(
      builder: (BuildContext overlayContext) => InheritedTheme.captureAll(
        context,
        _DateOverlay(
          kind: kind,
          label: label,
          value: _value,
          firstDate: widget.firstDate,
          lastDate: widget.lastDate,
          onChanged: _changed,
          onClosing: () {
            if (mounted) {
              setState(() => _closing = true);
            }
          },
          onClosed: () {
            _removeOverlay();
            if (mounted) {
              setState(() {
                _open = null;
                _closing = false;
              });
            }
          },
        ),
        to: overlay.context,
      ),
    );
    overlay.insert(_entry!);
    setState(() {
      _open = kind;
      _closing = false;
    });
  }

  void _changed(DateTime d) {
    _value.value = d;
    widget.onChanged?.call(d);
  }

  @override
  Widget build(BuildContext context) {
    final bool dark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final bool use24 = MediaQuery.alwaysUse24HourFormatOf(context);
    final bool enabled = widget.onChanged != null;
    Widget capsule(_DateOverlayKind kind, GlobalKey key, String text) =>
        _DateCapsule(
          key: key,
          text: text,
          dark: dark,
          enabled: enabled,
          active: _open == kind && !_closing,
          height:
              kind == _DateOverlayKind.calendar &&
                  widget.mode == GlassDatePickerMode.date
              ? _DateMetrics.capsuleHeight
              : _DateMetrics.pairHeight,
          onTap: () => _show(kind, key),
        );
    final GlassDatePickerMode mode = widget.mode;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (mode != GlassDatePickerMode.time)
          capsule(_DateOverlayKind.calendar, _dateKey, _dateText(widget.value)),
        if (mode == GlassDatePickerMode.dateAndTime)
          const SizedBox(width: _DateMetrics.capsuleGap),
        if (mode != GlassDatePickerMode.date)
          capsule(
            _DateOverlayKind.wheels,
            _timeKey,
            _timeText(widget.value, use24),
          ),
      ],
    );
  }
}

/// A compact picker's label on its gray capsule: blue while its platter is
/// open.
class _DateCapsule extends StatelessWidget {
  const _DateCapsule({
    super.key,
    required this.text,
    required this.dark,
    required this.enabled,
    required this.active,
    required this.height,
    required this.onTap,
  });

  final String text;
  final double height;
  final bool dark;
  final bool enabled;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: text,
      excludeSemantics: true,
      onTap: enabled ? onTap : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: Container(
          // (Taller with larger text.)
          constraints: BoxConstraints(minHeight: height),
          padding: const EdgeInsets.symmetric(
            horizontal: _DateMetrics.capsulePad,
          ),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _DateMetrics.capsuleFill(dark),
            borderRadius: BorderRadius.circular(height / 2),
          ),
          child: Text(
            text,
            maxLines: 1,
            style: _DateMetrics.capsuleText.copyWith(
              color: !enabled
                  ? _DateMetrics.tertiary(dark)
                  : active
                  ? _DateMetrics.blue(dark)
                  : _DateMetrics.label(dark),
            ),
          ),
        ),
      ),
    );
  }
}

/// Where a platter of [size] goes beside [label] on a screen of [screen]
/// with [padding] (UIKit's placement), and the point it grows from.
({Rect rect, Offset origin, bool up}) _placeDatePlatter(
  Rect label,
  Size size,
  Size screen,
  EdgeInsets padding,
) {
  final Offset c = label.center;
  final double maxLeft = screen.width - _DateMetrics.edge - size.width;
  final double left = math.max(
    _DateMetrics.edge,
    math.min(c.dx - _DateMetrics.side - size.width, maxLeft),
  );
  double top = c.dy + _DateMetrics.below;
  final bool up =
      top + size.height > screen.height - padding.bottom - _DateMetrics.room;
  if (up) {
    top = math.max(padding.top, c.dy - _DateMetrics.above - size.height);
  }
  final Rect rect = Offset(left, top) & size;
  return (
    rect: rect,
    origin: Offset(
      c.dx.clamp(rect.left, rect.right),
      up ? rect.bottom : rect.top,
    ),
    up: up,
  );
}

class _DateOverlay extends StatefulWidget {
  const _DateOverlay({
    required this.kind,
    required this.label,
    required this.value,
    required this.firstDate,
    required this.lastDate,
    required this.onChanged,
    required this.onClosing,
    required this.onClosed,
  });

  final _DateOverlayKind kind;
  final Rect label;
  final ValueNotifier<DateTime> value;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final ValueChanged<DateTime> onChanged;
  final VoidCallback onClosing;
  final VoidCallback onClosed;

  @override
  State<_DateOverlay> createState() => _DateOverlayState();
}

class _DateOverlayState extends State<_DateOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final GlassSpring _shown = GlassSpring(
    response: _DateMetrics.openResponse,
    dampingRatio: _DateMetrics.openDamping,
    tolerance: 5e-4,
  );
  final _EditAmount _amount = _EditAmount();
  Duration? _last;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    _shown.target = 1;
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _amount.dispose();
    super.dispose();
  }

  void close() {
    if (_closing) {
      return;
    }
    _closing = true;
    _shown
      ..configure(_DateMetrics.closeResponse, _DateMetrics.closeDamping)
      ..target = 0;
    widget.onClosing();
    if (!_ticker.isActive) {
      _last = null;
      _ticker.start();
    }
    setState(() {});
  }

  void _tick(Duration elapsed) {
    final Duration? last = _last;
    _last = elapsed;
    if (last != null) {
      _shown.step((elapsed - last).inMicroseconds / 1e6);
    }
    if (_shown.isSettled) {
      _shown.snap(_shown.target);
      _ticker.stop();
      _last = null;
      if (_closing) {
        widget.onClosed();
        return;
      }
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);
    final bool dark = media.platformBrightness == Brightness.dark;
    final bool calendar = widget.kind == _DateOverlayKind.calendar;
    final Size size = calendar ? _DateMetrics.calendar : _DateMetrics.wheels;
    final (:Rect rect, :Offset origin, :bool up) = _placeDatePlatter(
      widget.label,
      size,
      media.size,
      media.padding,
    );
    final double p = _shown.value;
    _amount.value = p.clamp(0.0, 1.0);
    // (Written so that p = 1 gives exactly 1.)
    final double s = 1 - (1 - _DateMetrics.start) * (1 - p);
    final double u = 1 - (1 - _DateMetrics.fold) * (1 - p);
    final double left = origin.dx + (rect.left - origin.dx) * s;
    final double width = size.width * s;
    final double height = size.height * s * u;
    final double top = up ? origin.dy - height : origin.dy;
    final Rect glass = Rect.fromLTWH(left, top, width, math.max(height, 0));
    final double radius = math.min(
      _DateMetrics.radius * s,
      glass.shortestSide / 2,
    );
    return Stack(
      children: <Widget>[
        // A touch anywhere else closes the platter (and goes no further).
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerUp: (_) => close(),
          ),
        ),
        Positioned.fromRect(
          rect: glass,
          child: IgnorePointer(
            ignoring: _closing,
            child: GlassPresence(
              amount: _amount,
              child: Glass._fixedFace(
                radius: radius,
                interactive: false,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radius),
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: size.width,
                    maxWidth: size.width,
                    minHeight: size.height,
                    maxHeight: size.height,
                    child: Transform.scale(
                      scale: s,
                      alignment: Alignment.topLeft,
                      child: Opacity(
                        opacity: p.clamp(0.0, 1.0),
                        child: SizedBox.fromSize(
                          size: size,
                          child: calendar
                              ? _GlassCalendar(
                                  value: widget.value,
                                  firstDate: widget.firstDate,
                                  lastDate: widget.lastDate,
                                  dark: dark,
                                  onChanged: widget.onChanged,
                                )
                              : _GlassTimeWheels(
                                  value: widget.value,
                                  dark: dark,
                                  onChanged: widget.onChanged,
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// UIKit's calendar (`UICalendarView`) on the platter: the month and its
/// arrows, the weekdays, the days; or, from a tap on the title, the month
/// and year on wheels.
class _GlassCalendar extends StatefulWidget {
  const _GlassCalendar({
    required this.value,
    required this.firstDate,
    required this.lastDate,
    required this.dark,
    required this.onChanged,
  });

  final ValueNotifier<DateTime> value;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final bool dark;
  final ValueChanged<DateTime> onChanged;

  @override
  State<_GlassCalendar> createState() => _GlassCalendarState();
}

class _GlassCalendarState extends State<_GlassCalendar>
    with SingleTickerProviderStateMixin {
  // Months as pages from the first month that can be shown.
  late final int _first = _monthIndex(widget.firstDate ?? DateTime(1));
  late final int _last = _monthIndex(widget.lastDate ?? DateTime(9999, 12));
  late int _month = _monthIndex(widget.value.value).clamp(_first, _last);
  late final PageController _pages = PageController(
    initialPage: _month - _first,
  );
  late final AnimationController _wheels = AnimationController(
    vsync: this,
    duration: _DateMetrics.swap,
  );
  late final CurvedAnimation _swap = CurvedAnimation(
    parent: _wheels,
    curve: Curves.easeInOut,
  );

  @override
  void dispose() {
    _pages.dispose();
    _swap.dispose();
    _wheels.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final int to = (_month + delta).clamp(_first, _last);
    if (to == _month) {
      return;
    }
    _pages.animateToPage(
      to - _first,
      duration: _DateMetrics.page,
      curve: Curves.easeInOut,
    );
  }

  void _toggleWheels() {
    if (_wheels.status == AnimationStatus.forward ||
        _wheels.status == AnimationStatus.completed) {
      _wheels.reverse();
    } else {
      _wheels.forward();
    }
  }

  bool _allowed(DateTime day) =>
      (widget.firstDate == null || !day.isBefore(_day(widget.firstDate!))) &&
      (widget.lastDate == null || !day.isAfter(_day(widget.lastDate!)));

  void _choose(DateTime day) {
    final DateTime v = widget.value.value;
    widget.onChanged(
      DateTime(day.year, day.month, day.day, v.hour, v.minute, v.second),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool dark = widget.dark;
    final DateTime shown = _monthAt(_month);
    return AnimatedBuilder(
      animation: _swap,
      builder: (BuildContext context, Widget? _) {
        final double w = _swap.value;
        final Color titleColor = Color.lerp(
          _DateMetrics.label(dark),
          _DateMetrics.blue(dark),
          w,
        )!;
        return Stack(
          children: <Widget>[
            // The title: the month and year, and a chevron that turns down
            // while the wheels show.
            Positioned(
              left: _DateMetrics.titleLeft,
              top: _DateMetrics.headerTop,
              height: _DateMetrics.headerHeight,
              child: Semantics(
                button: true,
                label: '${_monthNames[shown.month - 1]} ${shown.year}',
                excludeSemantics: true,
                onTap: _toggleWheels,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleWheels,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: _DateMetrics.titleInset,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          '${_monthNames[shown.month - 1]} ${shown.year}',
                          style: _DateMetrics.title.copyWith(color: titleColor),
                        ),
                        const SizedBox(width: 4),
                        Transform.rotate(
                          angle: math.pi / 2 * w,
                          child: CustomPaint(
                            size: const Size(10.33, 14),
                            painter: _DateChevronPainter(
                              _DateMetrics.blue(dark),
                              forward: true,
                              stroke: 2.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // The arrows.
            for (final int i in <int>[0, 1])
              Positioned(
                left: _DateMetrics.arrowLeft + i * _DateMetrics.arrowWidth,
                top: _DateMetrics.headerTop,
                width: _DateMetrics.arrowWidth,
                height: _DateMetrics.headerHeight,
                child: IgnorePointer(
                  ignoring: w > 0,
                  child: Opacity(
                    opacity: 1 - w,
                    child: Semantics(
                      button: true,
                      label: i == 0 ? 'Previous Month' : 'Next Month',
                      excludeSemantics: true,
                      onTap: () => _go(i == 0 ? -1 : 1),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _go(i == 0 ? -1 : 1),
                        child: Center(
                          child: CustomPaint(
                            size: const Size(15.33, 21),
                            painter: _DateChevronPainter(
                              (i == 0 ? _month > _first : _month < _last)
                                  ? _DateMetrics.label(dark)
                                  : _DateMetrics.tertiary(dark),
                              forward: i == 1,
                              stroke: 2.4,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            // The weekdays and the days.
            Positioned.fill(
              child: IgnorePointer(
                ignoring: w > 0,
                child: Opacity(
                  opacity: 1 - w,
                  child: Stack(
                    children: <Widget>[
                      for (int c = 0; c < 7; c++)
                        Positioned(
                          left:
                              _DateMetrics.weekdayLeft +
                              c * _DateMetrics.weekdayStep,
                          top: _DateMetrics.weekdayTop,
                          width: _DateMetrics.weekdayWidth,
                          height: _DateMetrics.weekdayHeight,
                          child: Center(
                            child: Text(
                              _weekdayNames[c],
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.visible,
                              style: _DateMetrics.weekday.copyWith(
                                color: _DateMetrics.secondary(dark),
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        left: 0,
                        right: 0,
                        top: _DateMetrics.gridTop,
                        height: _DateMetrics.gridHeight + 7 / 3,
                        child: PageView.builder(
                          controller: _pages,
                          itemCount: _last - _first + 1,
                          onPageChanged: (int page) =>
                              setState(() => _month = _first + page),
                          itemBuilder: (BuildContext context, int page) =>
                              ValueListenableBuilder<DateTime>(
                                valueListenable: widget.value,
                                builder:
                                    (BuildContext context, DateTime v, _) =>
                                        _MonthGrid(
                                          month: _monthAt(_first + page),
                                          selected: _day(v),
                                          today: _day(DateTime.now()),
                                          dark: dark,
                                          allowed: _allowed,
                                          onChoose: _choose,
                                        ),
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // The month and year wheels.
            if (w > 0)
              Positioned.fill(
                child: Opacity(
                  opacity: w,
                  child: _WheelBand(
                    dark: dark,
                    width: _DateMetrics.calendar.width,
                    center: _DateMetrics.monthWheels.center.dy,
                  ),
                ),
              ),
            if (w > 0)
              Positioned.fromRect(
                rect: _DateMetrics.monthWheels,
                child: Opacity(
                  opacity: w,
                  child: IgnorePointer(
                    ignoring: _wheels.status == AnimationStatus.reverse,
                    child: _MonthYearWheels(
                      month: _month,
                      first: _first,
                      last: _last,
                      dark: dark,
                      onChanged: (int m) {
                        if (m != _month) {
                          _pages.jumpToPage(m - _first);
                          setState(() => _month = m);
                        }
                      },
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// One month's days in UIKit's grid: seven columns, its rows sharing the
/// grid's height; today in blue, the chosen day on a circle.
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.selected,
    required this.today,
    required this.dark,
    required this.allowed,
    required this.onChoose,
  });

  final DateTime month;
  final DateTime selected;
  final DateTime today;
  final bool dark;
  final bool Function(DateTime day) allowed;
  final ValueChanged<DateTime> onChoose;

  @override
  Widget build(BuildContext context) {
    final int lead = DateTime(month.year, month.month).weekday % 7;
    final int days = DateTime(month.year, month.month + 1, 0).day;
    final int rows = ((lead + days) / 7).ceil();
    final double row = _DateMetrics.rowHeight(rows);
    final double circle = math.min(_DateMetrics.cellWidth, row);
    return Stack(
      children: <Widget>[
        for (int d = 1; d <= days; d++)
          () {
            final int i = lead + d - 1;
            final DateTime day = DateTime(month.year, month.month, d);
            final bool isSelected = day == selected;
            final bool isToday = day == today;
            final bool can = allowed(day);
            final Color text = !can
                ? _DateMetrics.tertiary(dark)
                : isSelected && isToday
                ? const Color(0xFFFFFFFF)
                : isSelected || isToday
                ? _DateMetrics.blue(dark)
                : _DateMetrics.label(dark);
            return Positioned(
              left: _DateMetrics.cellLeft + (i % 7) * _DateMetrics.cellWidth,
              top: 1 + (i ~/ 7) * row,
              width: _DateMetrics.cellWidth,
              height: row,
              child: Semantics(
                button: true,
                selected: isSelected,
                enabled: can,
                label: '$d ${_monthNames[month.month - 1]} ${month.year}',
                excludeSemantics: true,
                onTap: can ? () => onChoose(day) : null,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: can ? () => onChoose(day) : null,
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      if (isSelected)
                        Container(
                          width: circle,
                          height: circle,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isToday
                                ? _DateMetrics.blue(dark)
                                : _DateMetrics.selectedFill(dark),
                          ),
                        ),
                      Text(
                        '$d',
                        maxLines: 1,
                        softWrap: false,
                        style: _DateMetrics.day.copyWith(
                          color: text,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }(),
      ],
    );
  }
}

/// UIKit's time wheels on their platter: the hour (right-aligned), the
/// minute and AM or PM (or 24 hours, and no period); the hours and minutes
/// loop, and turning the hours past 12 turns the period, as UIKit's.
class _GlassTimeWheels extends StatefulWidget {
  const _GlassTimeWheels({
    required this.value,
    required this.dark,
    required this.onChanged,
  });

  final ValueNotifier<DateTime> value;
  final bool dark;
  final ValueChanged<DateTime> onChanged;

  @override
  State<_GlassTimeWheels> createState() => _GlassTimeWheelsState();
}

class _GlassTimeWheelsState extends State<_GlassTimeWheels> {
  late final DateTime _start = widget.value.value;
  late int _hour = _start.hour;
  late int _minute = _start.minute;
  bool? _use24;
  FixedExtentScrollController? _hours;
  late final FixedExtentScrollController _minutes = FixedExtentScrollController(
    initialItem: _minute,
  );
  late final FixedExtentScrollController _periods = FixedExtentScrollController(
    initialItem: _hour ~/ 12,
  );
  int _hourItem = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool use24 = MediaQuery.alwaysUse24HourFormatOf(context);
    if (use24 != _use24) {
      _use24 = use24;
      _hourItem = use24 ? _hour : _hour % 12;
      _hours?.dispose();
      _hours = FixedExtentScrollController(initialItem: _hourItem);
    }
  }

  @override
  void dispose() {
    _hours?.dispose();
    _minutes.dispose();
    _periods.dispose();
    super.dispose();
  }

  void _changed() {
    final DateTime v = widget.value.value;
    widget.onChanged(DateTime(v.year, v.month, v.day, _hour, _minute));
  }

  @override
  Widget build(BuildContext context) {
    final bool use24 = _use24!;
    final TextStyle style = _DateMetrics.wheelText.copyWith(
      color: _DateMetrics.label(widget.dark),
    );
    return Stack(
      children: <Widget>[
        _WheelBand(
          dark: widget.dark,
          width: _DateMetrics.wheels.width,
          center: _DateMetrics.timeWheels.center.dy,
        ),
        Positioned.fromRect(
          rect: _DateMetrics.timeWheels,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _wheelColumn(
                width: _DateMetrics.hourColumn,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(
                  right: _DateMetrics.hourColumn - _DateMetrics.hourRight,
                ),
                controller: _hours!,
                count: use24 ? 24 : 12,
                looping: true,
                style: style,
                label: (int i) =>
                    use24 ? i.toString().padLeft(2, '0') : '${i == 0 ? 12 : i}',
                onSelected: (int item) {
                  if (use24) {
                    _hour = item % 24;
                  } else {
                    // Past 12 (either way) the period turns.
                    final int turns =
                        (item / 12).floor() - (_hourItem / 12).floor();
                    int period = _hour ~/ 12;
                    if (turns.isOdd) {
                      period = 1 - period;
                      _periods.animateToItem(
                        period,
                        duration: _DateMetrics.swap,
                        curve: Curves.easeInOut,
                      );
                    }
                    _hour = item % 12 + 12 * period;
                  }
                  _hourItem = item;
                  _changed();
                },
              ),
              _wheelColumn(
                width: _DateMetrics.minuteColumn,
                controller: _minutes,
                count: 60,
                looping: true,
                style: style,
                label: (int i) => i.toString().padLeft(2, '0'),
                onSelected: (int item) {
                  _minute = item % 60;
                  _changed();
                },
              ),
              if (!use24)
                _wheelColumn(
                  width: _DateMetrics.periodColumn,
                  controller: _periods,
                  count: 2,
                  looping: false,
                  style: style,
                  label: (int i) => i == 0 ? 'AM' : 'PM',
                  onSelected: (int item) {
                    _hour = _hour % 12 + 12 * item;
                    _changed();
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One of UIKit's wheels (a column of a picker): [count] items, looping or
/// not, the middle one magnified as UIKit's.
Widget _wheelColumn({
  required double width,
  required FixedExtentScrollController controller,
  required int count,
  required bool looping,
  required TextStyle style,
  required String Function(int) label,
  required ValueChanged<int> onSelected,
  AlignmentGeometry alignment = Alignment.center,
  EdgeInsets padding = EdgeInsets.zero,
}) => SizedBox(
  width: width,
  child: CupertinoPicker.builder(
    scrollController: controller,
    itemExtent: _DateMetrics.wheelRow,
    squeeze: _DateMetrics.wheelSqueeze,
    magnification: _DateMetrics.wheelMagnification,
    useMagnifier: true,
    selectionOverlay: null,
    onSelectedItemChanged: onSelected,
    childCount: looping ? null : count,
    itemBuilder: (BuildContext context, int i) => Padding(
      padding: padding,
      child: Align(
        alignment: alignment,
        child: Text(label(i % count), maxLines: 1, style: style),
      ),
    ),
  ),
);

/// SF Symbols' chevron.forward / chevron.backward (and the title's
/// chevron.right), as strokes.
class _DateChevronPainter extends CustomPainter {
  const _DateChevronPainter(
    this.color, {
    required this.forward,
    required this.stroke,
  });

  final Color color;
  final bool forward;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final double w = size.width, h = size.height;
    final double inset = stroke / 2 + 1;
    final double near = w * 0.28, far = w * 0.72;
    final Path path = forward
        ? (Path()
            ..moveTo(near, inset)
            ..lineTo(far, h / 2)
            ..lineTo(near, h - inset))
        : (Path()
            ..moveTo(far, inset)
            ..lineTo(near, h / 2)
            ..lineTo(far, h - inset));
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_DateChevronPainter oldDelegate) =>
      color != oldDelegate.color ||
      forward != oldDelegate.forward ||
      stroke != oldDelegate.stroke;
}

/// The wheels' selection band (UIKit's capsule across the platter).
class _WheelBand extends StatelessWidget {
  const _WheelBand({
    required this.dark,
    required this.width,
    required this.center,
  });

  final bool dark;
  final double width;
  final double center;

  @override
  Widget build(BuildContext context) => Stack(
    children: <Widget>[
      Positioned(
        left: _DateMetrics.bandInset,
        width: width - 2 * _DateMetrics.bandInset,
        top: center - _DateMetrics.band / 2,
        height: _DateMetrics.band,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _DateMetrics.bandFill(dark),
            borderRadius: BorderRadius.circular(_DateMetrics.band / 2),
          ),
        ),
      ),
    ],
  );
}

/// UIKit's month and year wheels (the calendar's title, tapped): the
/// months loop; [onChanged] gets the month chosen (as a month index), kept
/// between [first] and [last].
class _MonthYearWheels extends StatefulWidget {
  const _MonthYearWheels({
    required this.month,
    required this.first,
    required this.last,
    required this.dark,
    required this.onChanged,
  });

  final int month;
  final int first;
  final int last;
  final bool dark;
  final ValueChanged<int> onChanged;

  @override
  State<_MonthYearWheels> createState() => _MonthYearWheelsState();
}

class _MonthYearWheelsState extends State<_MonthYearWheels> {
  late int _monthOfYear = widget.month % 12;
  late int _year = widget.month ~/ 12;
  late final FixedExtentScrollController _months = FixedExtentScrollController(
    initialItem: _monthOfYear,
  );
  late final FixedExtentScrollController _years = FixedExtentScrollController(
    initialItem: _year - widget.first ~/ 12,
  );

  @override
  void dispose() {
    _months.dispose();
    _years.dispose();
    super.dispose();
  }

  void _changed() {
    final int m = (_year * 12 + _monthOfYear).clamp(widget.first, widget.last);
    widget.onChanged(m);
  }

  @override
  Widget build(BuildContext context) {
    final TextStyle style = _DateMetrics.wheelText.copyWith(
      color: _DateMetrics.label(widget.dark),
    );
    final int firstYear = widget.first ~/ 12;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _wheelColumn(
          width: _DateMetrics.monthColumn,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: _DateMetrics.monthText),
          style: style,
          controller: _months,
          count: 12,
          looping: true,
          label: (int i) => _monthNames[i],
          onSelected: (int i) {
            _monthOfYear = i % 12;
            _changed();
          },
        ),
        _wheelColumn(
          width: _DateMetrics.yearColumn,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: _DateMetrics.yearText),
          style: style,
          controller: _years,
          count: widget.last ~/ 12 - firstYear + 1,
          looping: false,
          label: (int i) => '${firstYear + i}',
          onSelected: (int i) {
            _year = firstYear + i;
            _changed();
          },
        ),
      ],
    );
  }
}
