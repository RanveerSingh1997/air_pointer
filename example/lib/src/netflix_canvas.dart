import 'dart:async';
import 'dart:math' as math;

import 'package:air_pointer/air_pointer.dart';
import 'package:flutter/material.dart';

// ── Layout constants ──────────────────────────────────────────────────────────

const _kBg = Color(0xFF141414);
const _kHeaderH = 68.0;
const _kFeaturedH = 400.0; // hero section at top of content
const _kSectionLabelH = 38.0;
const _kCardW = 150.0;
const _kPosterH = 155.0;
const _kLabelH = 46.0;
const _kCardTotalH = _kPosterH + _kLabelH; // 201
const _kCardGap = 10.0;
const _kStride = _kCardW + _kCardGap; // 160
const _kRowPad = 56.0;
const _kRowBottomPad = 28.0;
const _kRowH = _kSectionLabelH + _kCardTotalH + _kRowBottomPad; // 313

// ── Data ─────────────────────────────────────────────────────────────────────

class _Row {
  const _Row(this.title, this.cards);
  final String title;
  final List<_Card> cards;
}

class _Card {
  const _Card(
    this.title,
    this.genre,
    this.topColor,
    this.bottomColor, {
    this.rating = 7.5,
    this.description = '',
  });
  final String title;
  final String genre;
  final Color topColor;
  final Color bottomColor;
  final double rating;
  final String description;
}

const _kFeaturedCard = _Card(
  'Stranger Things',
  'Sci-Fi · Horror · Thriller',
  Color(0xFF8B1A1A),
  Color(0xFF1A0000),
  rating: 8.7,
  description:
      'When a young boy disappears, his mother, a police chief, and his friends '
      'must confront terrifying supernatural forces in order to get him back.',
);

const _rows = [
  _Row('Trending Now', [
    _Card('Stranger Things', 'Sci-Fi · Horror', Color(0xFF8B1A1A), Color(0xFF3D0000),
        rating: 8.7, description: 'A group of kids uncover supernatural mysteries in their small Indiana town.'),
    _Card('Wednesday', 'Mystery · Fantasy', Color(0xFF1A1A2E), Color(0xFF0A0A1A),
        rating: 8.1, description: 'The Addams daughter navigates life at Nevermore Academy while solving a murder mystery.'),
    _Card('Squid Game', 'Thriller · Drama', Color(0xFF006400), Color(0xFF002800),
        rating: 8.0, description: 'Hundreds of cash-strapped players accept an invitation to compete in deadly children\'s games.'),
    _Card('Bridgerton', 'Romance · Drama', Color(0xFF4B0082), Color(0xFF220040),
        rating: 7.3, description: 'The Bridgerton siblings navigate the competitive world of Regency-era London society.'),
    _Card('The Crown', 'Biography · Drama', Color(0xFF8B6914), Color(0xFF3D2900),
        rating: 8.6, description: 'The political rivalries and romance of Queen Elizabeth II\'s reign.'),
    _Card('Ozark', 'Crime · Thriller', Color(0xFF1C3A4A), Color(0xFF0A1A22),
        rating: 8.4, description: 'A financial advisor drags his family to the Ozarks, where he must launder money.'),
    _Card('Money Heist', 'Action · Crime', Color(0xFFB22222), Color(0xFF5C0A0A),
        rating: 8.2, description: 'A criminal mastermind recruits eight thieves for an ambitious mint heist.'),
    _Card('Dark', 'Sci-Fi · Mystery', Color(0xFF1A1A2E), Color(0xFF050510),
        rating: 8.8, description: 'A missing child sets four families on a frantic hunt in a time-bending German town.'),
    _Card('The Witcher', 'Fantasy · Action', Color(0xFF2D4A1E), Color(0xFF0E1A08),
        rating: 8.2, description: 'Geralt of Rivia, a mutated monster-hunter, struggles to find his place in a world of people.'),
  ]),
  _Row('Action & Adventure', [
    _Card('Extraction', 'Action · Thriller', Color(0xFF3D5A80), Color(0xFF1A2B3C),
        rating: 7.4, description: 'A fearless mercenary is hired to rescue the kidnapped son of a crime lord.'),
    _Card('The Old Guard', 'Action · Fantasy', Color(0xFF6B4C3B), Color(0xFF2E1A10),
        rating: 6.6, description: 'A covert team of immortal mercenaries must fight to keep their secret safe.'),
    _Card('Red Notice', 'Action · Comedy', Color(0xFF7B2D8B), Color(0xFF38104A),
        rating: 6.3, description: 'An FBI profiler pursues the world\'s most wanted art thief with an unlikely partner.'),
    _Card('6 Underground', 'Action · Comedy', Color(0xFF1B4332), Color(0xFF081A12),
        rating: 6.1, description: 'A billionaire fakes his own death to form a squad of vigilantes.'),
    _Card('Army of the Dead', 'Action · Horror', Color(0xFF4A4E69), Color(0xFF1A1C30),
        rating: 5.7, description: 'A group plans a daring heist inside a zombie quarantine zone in Las Vegas.'),
    _Card('Project Power', 'Action · Sci-Fi', Color(0xFF774936), Color(0xFF321A10),
        rating: 6.0, description: 'A pill that grants superpowers for five minutes hits the streets of New Orleans.'),
    _Card('Kate', 'Action · Thriller', Color(0xFF5C3317), Color(0xFF280F04),
        rating: 6.2, description: 'A female assassin has 24 hours to get vengeance on her murderer before she dies.'),
    _Card('Bright', 'Action · Fantasy', Color(0xFF2B2D42), Color(0xFF0E0F1C),
        rating: 6.3, description: 'An LAPD officer and his Orc partner are drawn into a struggle over a magic wand.'),
    _Card('Outside the Wire', 'Sci-Fi · Action', Color(0xFF3E3E3E), Color(0xFF141414),
        rating: 5.4, description: 'A drone pilot partners with an android officer on a dangerous mission.'),
  ]),
  _Row('Drama · Award Winners', [
    _Card('The Power of the Dog', 'Drama', Color(0xFF5D4037), Color(0xFF251510),
        rating: 6.9, description: 'A domineering rancher leads his brother and his new wife in a tale of repressed emotions.'),
    _Card('Marriage Story', 'Drama · Romance', Color(0xFF37474F), Color(0xFF131C20),
        rating: 7.9, description: 'A director and his actress wife struggle through a coast-to-coast divorce.'),
    _Card('The Irishman', 'Crime · Drama', Color(0xFF3E2723), Color(0xFF18100C),
        rating: 7.8, description: 'A hitman recalls his time with the mob and the disappearance of Jimmy Hoffa.'),
    _Card('Roma', 'Drama', Color(0xFF455A64), Color(0xFF1A2428),
        rating: 7.7, description: 'A year in the life of a middle-class family\'s maid in Mexico City in the 1970s.'),
    _Card('The Two Popes', 'Drama · Biography', Color(0xFF4A4000), Color(0xFF1C1800),
        rating: 7.6, description: 'An emissary of the Pope travels to Rome to argue for his retirement.'),
    _Card('Trial of Chicago 7', 'Drama · History', Color(0xFF1A237E), Color(0xFF080C38),
        rating: 7.7, description: 'The infamous 1969 trial of seven defendants charged with conspiracy.'),
    _Card('Malcolm & Marie', 'Drama · Romance', Color(0xFF212121), Color(0xFF080808),
        rating: 6.4, description: 'A filmmaker and his girlfriend return home as tensions rise to the surface.'),
    _Card('Mank', 'Biography · Drama', Color(0xFF2D2D2D), Color(0xFF0A0A0A),
        rating: 6.8, description: 'Herman J. Mankiewicz races to finish the Citizen Kane screenplay.'),
  ]),
  _Row('Comedy', [
    _Card('Murder Mystery', 'Comedy · Mystery', Color(0xFF1565C0), Color(0xFF0A3360),
        rating: 5.7, description: 'A New York cop and his wife get entangled in a murder mystery in Europe.'),
    _Card('Eurovision Song Contest', 'Comedy · Musical', Color(0xFF6A1B4D), Color(0xFF280830),
        rating: 6.5, description: 'Two Icelandic musicians get the chance to represent their country at Eurovision.'),
    _Card('The Ridiculous 6', 'Comedy · Western', Color(0xFF8D6E63), Color(0xFF3E2820),
        rating: 4.8, description: 'An outlaw raised by Native Americans sets out to find his biological father.'),
    _Card('Wine Country', 'Comedy', Color(0xFF6A1B4D), Color(0xFF2A0A1E),
        rating: 5.5, description: 'Six friends celebrate a 50th birthday with a trip to Napa Valley.'),
    _Card('Me Time', 'Comedy', Color(0xFF558B2F), Color(0xFF203810),
        rating: 5.1, description: 'A stay-at-home dad gets some alone time while his family is away.'),
    _Card('You People', 'Comedy · Drama', Color(0xFF0D47A1), Color(0xFF061C44),
        rating: 5.4, description: 'A new couple and their families examine modern love and family dynamics.'),
    _Card('Game Over Man!', 'Comedy · Action', Color(0xFF2E7D32), Color(0xFF0E3010),
        rating: 5.3, description: 'Three friends deal with a hostage situation while trying to finish their game deal.'),
    _Card('Holidate', 'Comedy · Romance', Color(0xFF880E4F), Color(0xFF380620),
        rating: 5.3, description: 'Two strangers agree to be each other\'s plus-ones for every holiday.'),
  ]),
  _Row('Sci-Fi & Fantasy', [
    _Card('Altered Carbon', 'Sci-Fi · Thriller', Color(0xFF006064), Color(0xFF002428),
        rating: 8.0, description: 'In a future where consciousness is digitized, a cynic wakes up in a new body on a mission.'),
    _Card('Lost in Space', 'Sci-Fi · Adventure', Color(0xFF1A237E), Color(0xFF080C3E),
        rating: 7.4, description: 'After crash-landing on an alien planet, the Robinsons must fight against all odds to survive.'),
    _Card('I Am Mother', 'Sci-Fi · Thriller', Color(0xFF1C1C2E), Color(0xFF08080E),
        rating: 6.7, description: 'A teen raised underground by a robot must decide if she can trust a human stranger.'),
    _Card('Oxygen', 'Sci-Fi · Thriller', Color(0xFF004D40), Color(0xFF001A16),
        rating: 6.5, description: 'A woman wakes in a cryogenic pod with no memory and must escape before her oxygen runs out.'),
    _Card('The Midnight Sky', 'Sci-Fi · Drama', Color(0xFF0D1B2A), Color(0xFF040C14),
        rating: 5.7, description: 'A scientist races to contact astronauts returning to a post-catastrophe Earth.'),
    _Card('The Platform', 'Sci-Fi · Horror', Color(0xFF1A1A2E), Color(0xFF060610),
        rating: 7.0, description: 'A vertical prison. A food platform descends from the top each day.'),
    _Card('Another Life', 'Sci-Fi', Color(0xFF263238), Color(0xFF0C1418),
        rating: 4.5, description: 'An astronaut leads a crew on a mission to explore the genesis of an alien artifact.'),
    _Card('Cowboy Bebop', 'Sci-Fi · Action', Color(0xFF4A2040), Color(0xFF1A0818),
        rating: 7.1, description: 'A ragtag group of bounty hunters chase criminals across the galaxy.'),
  ]),
  _Row('Documentaries', [
    _Card('The Last Dance', 'Sports · Doc', Color(0xFF1A1A1A), Color(0xFF050505),
        rating: 9.1, description: 'A behind-the-scenes look at the final championship season of Michael Jordan and the Bulls.'),
    _Card('Tiger King', 'Crime · Doc', Color(0xFF4E342E), Color(0xFF1C100A),
        description:
            'A zoo keeper with a mullet builds an empire of big cats while plotting against his nemesis.'),
    _Card('Our Planet', 'Nature · Doc', Color(0xFF1B5E20), Color(0xFF08240A),
        rating: 9.3, description: 'David Attenborough presents the spectacular diversity of life on our planet.'),
    _Card('Making a Murderer', 'True Crime', Color(0xFF263238), Color(0xFF0C1418),
        rating: 8.6, description: 'An exonerated man and his nephew become embroiled in a controversial murder case.'),
    _Card('Wild Wild Country', 'Documentary', Color(0xFF4A148C), Color(0xFF1C0840),
        rating: 8.2, description: 'A cult builds a utopian city in Oregon and a massive conflict ensues.'),
    _Card('My Octopus Teacher', 'Nature · Doc', Color(0xFF01579B), Color(0xFF012544),
        rating: 8.1, description: 'A filmmaker forges an unlikely friendship with an octopus in a kelp forest.'),
    _Card('13th', 'Documentary', Color(0xFF2D2D2D), Color(0xFF0A0A0A),
        rating: 8.2, description: 'An exploration of the intersection of race, justice, and mass incarceration in the US.'),
    _Card('Don\'t Look Up', 'Comedy · Satire', Color(0xFF0D47A1), Color(0xFF061C44),
        rating: 7.2, description: 'Two astronomers go on a media tour to warn mankind of an approaching comet.'),
  ]),
];

// ── Widget ────────────────────────────────────────────────────────────────────

class NetflixCanvas extends StatefulWidget {
  const NetflixCanvas({super.key});

  @override
  State<NetflixCanvas> createState() => _NetflixCanvasState();
}

class _NetflixCanvasState extends State<NetflixCanvas> {
  late final CanvasInputController _controller;
  late final StreamSubscription<PointerInputEvent> _sub;

  double _verticalScroll = 0;
  final _rowScrolls = <int, double>{};
  Offset? _cursorPos;
  ({int row, int col})? _hovered;
  bool _hoveredFeatured = false;
  _Card? _selectedCard;
  Size _size = Size.zero;

  @override
  void initState() {
    super.initState();
    _controller = CanvasInputController(sources: [MouseInputSource()]);
    _sub = _controller.events.listen(_onInput);
  }

  @override
  void dispose() {
    unawaited(_sub.cancel());
    unawaited(_controller.dispose());
    super.dispose();
  }

  double get _maxVerticalScroll {
    final contentH = _size.height - _kHeaderH;
    return math.max(0.0, _kFeaturedH + _rows.length * _kRowH - contentH);
  }

  double _maxRowScroll(int row) => math.max(
        0.0,
        _rows[row].cards.length * _kStride + _kRowPad - _size.width + _kCardGap,
      );

  void _onInput(PointerInputEvent event) {
    switch (event) {
      case CanvasHoverEvent(:final position):
        final hit = _hitTest(position);
        final onFeatured = _isOnFeatured(position);
        setState(() {
          _cursorPos = position;
          _hovered = hit;
          _hoveredFeatured = onFeatured;
        });

      case CanvasTapEvent(:final position):
        final hit = _hitTest(position);
        if (hit != null) {
          setState(() => _selectedCard = _rows[hit.row].cards[hit.col]);
        } else if (_isOnFeatured(position)) {
          setState(() => _selectedCard = _kFeaturedCard);
        }

      case CanvasScrollEvent(:final delta):
        final row = _rowForPos(_cursorPos);
        setState(() {
          _verticalScroll =
              (_verticalScroll + delta.dy).clamp(0, _maxVerticalScroll);
          if (row != null && delta.dx.abs() > 2) {
            _rowScrolls[row] =
                ((_rowScrolls[row] ?? 0) + delta.dx).clamp(0, _maxRowScroll(row));
          }
        });

      case CanvasDownEvent():
      case CanvasMoveEvent():
      case CanvasUpEvent():
      case CanvasCancelEvent():
      case CanvasScaleEvent():
      case CanvasScaleEndEvent():
        break;
    }
  }

  bool _isOnFeatured(Offset pos) {
    if (pos.dy < _kHeaderH) return false;
    final contentY = pos.dy - _kHeaderH + _verticalScroll;
    return contentY < _kFeaturedH;
  }

  int? _rowForPos(Offset? pos) {
    if (pos == null || pos.dy < _kHeaderH) return null;
    final contentY = pos.dy - _kHeaderH + _verticalScroll - _kFeaturedH;
    if (contentY < 0) return null;
    final ri = (contentY / _kRowH).floor();
    if (ri < 0 || ri >= _rows.length) return null;
    return ri;
  }

  ({int row, int col})? _hitTest(Offset pos) {
    if (pos.dy < _kHeaderH) return null;
    final contentY = pos.dy - _kHeaderH + _verticalScroll - _kFeaturedH;
    if (contentY < 0) return null;

    final ri = (contentY / _kRowH).floor();
    if (ri < 0 || ri >= _rows.length) return null;

    final rowY = contentY - ri * _kRowH;
    if (rowY < _kSectionLabelH || rowY > _kSectionLabelH + _kCardTotalH) {
      return null;
    }

    final rowScroll = _rowScrolls[ri] ?? 0.0;
    final cx = pos.dx - _kRowPad + rowScroll;
    if (cx < 0) return null;

    final ci = (cx / _kStride).floor();
    if (ci < 0 || ci >= _rows[ri].cards.length) return null;

    if (cx - ci * _kStride > _kCardW) return null; // in gap

    return (row: ri, col: ci);
  }

  @override
  Widget build(BuildContext context) {
    return _controller.buildSurface(
      child: LayoutBuilder(
        builder: (context, constraints) {
          _size = constraints.biggest;
          return Stack(
            children: [
              // Scrollable content
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _ContentPainter(
                      rows: _rows,
                      verticalScroll: _verticalScroll,
                      rowScrolls: Map.unmodifiable(_rowScrolls),
                      hovered: _hovered,
                      hoveredFeatured: _hoveredFeatured,
                    ),
                    size: Size.infinite,
                  ),
                ),
              ),

              // Fixed header (drawn on top of content)
              const Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: _kHeaderH,
                child: _NetflixHeader(),
              ),

              // Detail overlay
              if (_selectedCard != null)
                Positioned.fill(
                  child: _DetailOverlay(
                    card: _selectedCard!,
                    onClose: () => setState(() => _selectedCard = null),
                  ),
                ),

              // Cursor dot
              if (_cursorPos != null)
                Positioned(
                  left: _cursorPos!.dx - 8,
                  top: _cursorPos!.dy - 8,
                  child: const IgnorePointer(child: _CursorDot()),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ── Content painter ───────────────────────────────────────────────────────────

class _ContentPainter extends CustomPainter {
  const _ContentPainter({
    required this.rows,
    required this.verticalScroll,
    required this.rowScrolls,
    required this.hovered,
    required this.hoveredFeatured,
  });

  final List<_Row> rows;
  final double verticalScroll;
  final Map<int, double> rowScrolls;
  final ({int row, int col})? hovered;
  final bool hoveredFeatured;

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    canvas.drawRect(Offset.zero & size, Paint()..color = _kBg);

    // Featured hero section
    final featuredTop = _kHeaderH - verticalScroll;
    if (featuredTop < size.height && featuredTop + _kFeaturedH > _kHeaderH) {
      _paintFeatured(canvas, size, featuredTop);
    }

    // Card rows
    final rowsTop = _kHeaderH + _kFeaturedH - verticalScroll;
    final firstRow =
        ((verticalScroll - _kFeaturedH) / _kRowH).floor().clamp(0, rows.length);
    final lastRow =
        ((verticalScroll + size.height - _kHeaderH - _kFeaturedH) / _kRowH)
            .ceil()
            .clamp(0, rows.length);

    for (var ri = math.max(0, firstRow); ri < lastRow; ri++) {
      final rowTop = rowsTop + ri * _kRowH;
      if (rowTop > size.height || rowTop + _kRowH < _kHeaderH) continue;
      _paintRow(canvas, size, ri, rowTop);
    }
  }

  void _paintFeatured(Canvas canvas, Size size, double top) {
    final rect = Rect.fromLTWH(0, top, size.width, _kFeaturedH);

    // Background gradient
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [_kFeaturedCard.topColor, _kFeaturedCard.bottomColor],
          stops: const [0.0, 1.0],
        ).createShader(rect),
    );

    // Bottom fade to background
    canvas.drawRect(
      Rect.fromLTWH(0, top + _kFeaturedH * 0.55, size.width, _kFeaturedH * 0.45),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_kFeaturedCard.bottomColor.withValues(alpha: 0), _kBg],
        ).createShader(Rect.fromLTWH(
          0, top + _kFeaturedH * 0.55, size.width, _kFeaturedH * 0.45,
        )),
    );

    // Watermark title
    _paintText(
      canvas,
      _kFeaturedCard.title.toUpperCase(),
      TextStyle(
        color: Colors.white.withValues(alpha: 0.07),
        fontSize: 90,
        fontWeight: FontWeight.w900,
        letterSpacing: 4,
      ),
      Offset(56, top + 60),
      maxWidth: size.width - 112,
    );

    // Rating badge
    _paintRatingBadge(canvas, _kFeaturedCard.rating, Offset(56, top + 32));

    // Title
    _paintText(
      canvas,
      _kFeaturedCard.title,
      const TextStyle(
        color: Colors.white,
        fontSize: 40,
        fontWeight: FontWeight.bold,
        height: 1.1,
        shadows: [Shadow(blurRadius: 16)],
      ),
      Offset(56, top + _kFeaturedH * 0.45),
      maxWidth: size.width * 0.5,
    );

    // Genre
    _paintText(
      canvas,
      _kFeaturedCard.genre,
      TextStyle(
        color: Colors.white.withValues(alpha: 0.65),
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      Offset(56, top + _kFeaturedH * 0.45 + 52),
      maxWidth: 400,
    );

    // Description
    _paintText(
      canvas,
      _kFeaturedCard.description,
      TextStyle(
        color: Colors.white.withValues(alpha: 0.75),
        fontSize: 13,
        height: 1.5,
      ),
      Offset(56, top + _kFeaturedH * 0.45 + 76),
      maxWidth: size.width * 0.42,
      maxLines: 3,
    );

    // Play button area hint
    final playRect = Rect.fromLTWH(56, top + _kFeaturedH - 76, 110, 40);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        playRect,
        const Radius.circular(4),
      ),
      Paint()
        ..color = hoveredFeatured
            ? Colors.white
            : Colors.white.withValues(alpha: 0.88),
    );
    _paintText(
      canvas,
      '▶  Play',
      const TextStyle(
        color: Colors.black,
        fontSize: 14,
        fontWeight: FontWeight.bold,
      ),
      Offset(56 + 24, top + _kFeaturedH - 76 + 12),
    );

    final moreRect = Rect.fromLTWH(176, top + _kFeaturedH - 76, 120, 40);
    canvas.drawRRect(
      RRect.fromRectAndRadius(moreRect, const Radius.circular(4)),
      Paint()..color = Colors.white.withValues(alpha: 0.2),
    );
    _paintText(
      canvas,
      'ℹ  More Info',
      const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
      Offset(176 + 16, top + _kFeaturedH - 76 + 12),
    );
  }

  void _paintRow(Canvas canvas, Size size, int ri, double rowTop) {
    final row = rows[ri];
    final rowScroll = rowScrolls[ri] ?? 0.0;

    // Section label
    _paintText(
      canvas,
      row.title,
      const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
      ),
      Offset(_kRowPad, rowTop + 8),
      maxWidth: size.width - _kRowPad * 2,
    );

    // Clip cards to content area so they don't bleed under the header.
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, _kHeaderH, size.width, size.height - _kHeaderH));

    final firstCol = math.max(0, (rowScroll / _kStride).floor() - 1);
    final lastCol = math.min(
      row.cards.length,
      ((rowScroll + size.width - _kRowPad) / _kStride).ceil() + 1,
    );

    for (var ci = firstCol; ci < lastCol; ci++) {
      final cardLeft = _kRowPad + ci * _kStride - rowScroll;
      if (cardLeft + _kCardW < 0 || cardLeft > size.width) continue;

      final posterRect = Rect.fromLTWH(
        cardLeft,
        rowTop + _kSectionLabelH,
        _kCardW,
        _kPosterH,
      );
      final isHov = hovered?.row == ri && hovered?.col == ci;
      _paintCard(canvas, row.cards[ci], posterRect, isHov);
    }

    canvas.restore();
  }

  void _paintCard(Canvas canvas, _Card card, Rect posterRect, bool isHov) {
    final expand = isHov ? 4.0 : 0.0;
    final displayRect = posterRect.inflate(expand).translate(0, -expand);
    final rrect = RRect.fromRectAndRadius(displayRect, const Radius.circular(6));

    // Shadow
    if (isHov) {
      canvas.drawShadow(Path()..addRRect(rrect), Colors.black, 12, true);
    }

    // Gradient poster
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [card.topColor, card.bottomColor],
        ).createShader(displayRect),
    );

    // Faded title watermark on poster
    _paintText(
      canvas,
      card.title,
      TextStyle(
        color: Colors.white.withValues(alpha: 0.10),
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
      Offset(displayRect.left + 8, displayRect.top + displayRect.height / 2 - 14),
      maxWidth: _kCardW - 8,
    );

    // Hover border
    if (isHov) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }

    // Rating chip
    _paintRatingBadge(
      canvas,
      card.rating,
      Offset(posterRect.left + 6, posterRect.top + 6),
    );

    // Title below poster
    _paintText(
      canvas,
      card.title,
      TextStyle(
        color: isHov ? Colors.white : Colors.white.withValues(alpha: 0.88),
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      Offset(posterRect.left, posterRect.bottom + 8),
      maxWidth: _kCardW,
    );

    // Genre
    _paintText(
      canvas,
      card.genre,
      TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 10),
      Offset(posterRect.left, posterRect.bottom + 23),
      maxWidth: _kCardW,
    );
  }

  void _paintRatingBadge(Canvas canvas, double rating, Offset topLeft) {
    final tp = TextPainter(
      text: TextSpan(
        text: '★ ${rating.toStringAsFixed(1)}',
        style: const TextStyle(
          color: Color(0xFFFFD700),
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final chipRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(topLeft.dx, topLeft.dy, tp.width + 8, 16),
      const Radius.circular(3),
    );
    canvas.drawRRect(chipRect, Paint()..color = Colors.black.withValues(alpha: 0.6));
    tp.paint(canvas, Offset(topLeft.dx + 4, topLeft.dy + 3));
  }

  void _paintText(
    Canvas canvas,
    String text,
    TextStyle style,
    Offset pos, {
    double maxWidth = double.infinity,
    int maxLines = 1,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(_ContentPainter old) =>
      old.verticalScroll != verticalScroll ||
      old.rowScrolls != rowScrolls ||
      old.hovered != hovered ||
      old.hoveredFeatured != hoveredFeatured;
}

// ── Fixed header ──────────────────────────────────────────────────────────────

class _NetflixHeader extends StatelessWidget {
  const _NetflixHeader();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black, Colors.black.withValues(alpha: 0.0)],
          stops: const [0.6, 1.0],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 56),
        child: Row(
          children: [
            // Netflix logo
            RichText(
              text: const TextSpan(
                children: [
                  TextSpan(
                    text: 'N',
                    style: TextStyle(
                      color: Color(0xFFE50914),
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -3,
                    ),
                  ),
                  TextSpan(
                    text: 'ETFLIX',
                    style: TextStyle(
                      color: Color(0xFFE50914),
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 36),
            for (final item in ['Home', 'TV Shows', 'Movies', 'New & Popular', 'My List'])
              Padding(
                padding: const EdgeInsets.only(right: 20),
                child: Text(
                  item,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            const Spacer(),
            const Icon(Icons.search, color: Colors.white70, size: 22),
            const SizedBox(width: 20),
            const Icon(Icons.notifications_outlined, color: Colors.white70, size: 22),
            const SizedBox(width: 20),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF831010),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(Icons.person, color: Colors.white70, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Detail overlay ────────────────────────────────────────────────────────────

class _DetailOverlay extends StatelessWidget {
  const _DetailOverlay({required this.card, required this.onClose});

  final _Card card;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onClose,
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.82),
        child: Center(
          child: GestureDetector(
            onTap: () {}, // absorb taps inside overlay
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 540,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Poster
                    SizedBox(
                      height: 280,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [card.topColor, card.bottomColor],
                              ),
                            ),
                          ),
                          // Bottom fade
                          const Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: 100,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Color(0xFF1A1A1A),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Watermark
                          Center(
                            child: Text(
                              card.title,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.09),
                                fontSize: 52,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          // Title
                          Positioned(
                            left: 24,
                            bottom: 16,
                            child: Text(
                              card.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                shadows: [Shadow(blurRadius: 12)],
                              ),
                            ),
                          ),
                          // Rating
                          Positioned(
                            top: 14,
                            left: 14,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.amber,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '★ ${card.rating.toStringAsFixed(1)}',
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          // Close
                          Positioned(
                            top: 12,
                            right: 12,
                            child: GestureDetector(
                              onTap: onClose,
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.65),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close,
                                    color: Colors.white, size: 18),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Info panel
                    Container(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                      color: const Color(0xFF1A1A1A),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            card.genre,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12),
                          ),
                          if (card.description.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text(
                              card.description,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                height: 1.5,
                              ),
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              const _DetailBtn(
                                color: Colors.white,
                                textColor: Colors.black,
                                icon: Icons.play_arrow,
                                label: 'Play',
                              ),
                              const SizedBox(width: 10),
                              _DetailBtn(
                                color: Colors.white.withValues(alpha: 0.18),
                                textColor: Colors.white,
                                icon: Icons.add,
                                label: 'My List',
                              ),
                              const SizedBox(width: 10),
                              _DetailBtn(
                                color: Colors.white.withValues(alpha: 0.18),
                                textColor: Colors.white,
                                icon: Icons.thumb_up_outlined,
                                label: 'Rate',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailBtn extends StatelessWidget {
  const _DetailBtn({
    required this.color,
    required this.textColor,
    required this.icon,
    required this.label,
  });

  final Color color;
  final Color textColor;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration:
            BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: textColor, size: 16),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

// ── Cursor dot ────────────────────────────────────────────────────────────────

class _CursorDot extends StatelessWidget {
  const _CursorDot();

  @override
  Widget build(BuildContext context) => Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.85),
          boxShadow: [
            BoxShadow(
                color: Colors.white.withValues(alpha: 0.4), blurRadius: 8),
          ],
        ),
      );
}
