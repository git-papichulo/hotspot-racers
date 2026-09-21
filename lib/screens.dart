import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'model.dart';
import 'native.dart';
import 'net.dart';
import 'painter.dart';
import 'session.dart';
import 'track.dart';

const Color kBg = Color(0xFF1B2430);
const Color kPanel = Color(0xFF2B3644);
const Color kAccent = Color(0xFF00BCD4);
const Color kCoral = Color(0xFFFF6B6B);
const Color kMuted = Color(0xFF8FA3B8);

const TextStyle kMutedStyle = TextStyle(fontSize: 13, color: kMuted);
const TextStyle kBoldStyle = TextStyle(fontSize: 16, fontWeight: FontWeight.w700);

// ---------------------------------------------------------------------------
// shared widgets
// ---------------------------------------------------------------------------

class Panel extends StatelessWidget {
  final String title;
  final Widget child;

  const Panel({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(fontSize: 12, letterSpacing: 1.5, fontWeight: FontWeight.w700, color: kMuted),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class BigButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color color;
  final IconData? icon;

  const BigButton({super.key, required this.label, required this.onTap, this.color = kAccent, this.icon});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFF3A4757),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (icon != null) Icon(icon),
            if (icon != null) const SizedBox(width: 8),
            Text(label),
          ],
        ),
      ),
    );
  }
}

class NoticeScreen extends StatelessWidget {
  final String text;

  const NoticeScreen({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.wifi_off, size: 56, color: kCoral),
                const SizedBox(height: 16),
                Text(text, textAlign: TextAlign.center, style: kBoldStyle),
                const SizedBox(height: 24),
                BigButton(label: 'BACK', onTap: () => Navigator.of(context).pop()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// menu
// ---------------------------------------------------------------------------

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  final TextEditingController _name = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final saved = await Native.getPref('name');
    final low = await Native.getPref('lowfps');
    if (!mounted) {
      return;
    }
    setState(() {
      _name.text = (saved != null && saved.isNotEmpty) ? saved : 'Player${10 + math.Random().nextInt(90)}';
      Settings.lowFps = low == '1';
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String get _cleanName {
    final t = _name.text.trim();
    if (t.isEmpty) {
      return 'Player';
    }
    return t.length > 14 ? t.substring(0, 14) : t;
  }

  Future<void> _go(Widget page) async {
    Native.setPref('name', _cleanName);
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (BuildContext c) => page));
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text(
                    'HOTSPOT',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: 4, color: kAccent),
                  ),
                  const Text(
                    'RACERS',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: 4, color: kCoral),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Local Wi-Fi racing for up to 6 players. No internet needed.',
                    textAlign: TextAlign.center,
                    style: kMutedStyle,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _name,
                    maxLength: 14,
                    decoration: InputDecoration(
                      labelText: 'Your name',
                      filled: true,
                      fillColor: kPanel,
                      counterText: '',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 16),
                  BigButton(
                    label: 'HOST A RACE',
                    icon: Icons.wifi_tethering,
                    onTap: () => _go(SessionScreen(session: HostSession(_cleanName, isOnline: true))),
                  ),
                  const SizedBox(height: 12),
                  BigButton(
                    label: 'JOIN A RACE',
                    icon: Icons.login,
                    color: kCoral,
                    onTap: () => _go(JoinScreen(name: _cleanName)),
                  ),
                  const SizedBox(height: 12),
                  BigButton(
                    label: 'PRACTICE VS BOTS',
                    icon: Icons.sports_score,
                    color: const Color(0xFF3A4757),
                    onTap: () => _go(SessionScreen(session: HostSession(_cleanName, isOnline: false))),
                  ),
                  const SizedBox(height: 18),
                  const Panel(
                    title: 'HOW TO PLAY',
                    child: Text(
                      'One phone turns on its hotspot and taps Host. Everyone else connects to that Wi-Fi and taps Join. '
                      'Hold the left half of the screen to steer left, the right half to steer right. Hold both to brake. Gas is automatic.',
                      style: kMutedStyle,
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: Settings.lowFps,
                    title: const Text('Battery saver (30 FPS)'),
                    subtitle: const Text('Helps very old phones', style: kMutedStyle),
                    onChanged: (bool v) {
                      setState(() {
                        Settings.lowFps = v;
                      });
                      Native.setPref('lowfps', v ? '1' : '0');
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// join
// ---------------------------------------------------------------------------

class JoinScreen extends StatefulWidget {
  final String name;

  const JoinScreen({super.key, required this.name});

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final Discovery _disc = Discovery();
  final TextEditingController _ip = TextEditingController();
  bool _busy = false;
  String? _msg;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await Native.prepare(bindWifi: false);
    if (!mounted) {
      return;
    }
    _disc.onChange = () {
      if (mounted) {
        setState(() {});
      }
    };
    await _disc.start();
  }

  @override
  void dispose() {
    _disc.stop();
    _ip.dispose();
    Native.release();
    super.dispose();
  }

  Future<void> _showSession(ClientSession s) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (BuildContext c) => SessionScreen(session: s)));
    if (mounted) {
      await Native.prepare(bindWifi: false);
      setState(() {
        _busy = false;
        _msg = null;
      });
    }
  }

  Future<void> _connectTo(String ip, int port) async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _msg = 'Connecting...';
    });
    final s = ClientSession(widget.name, ip, port);
    final ok = await s.connect();
    if (!mounted) {
      await s.close();
      s.dispose();
      return;
    }
    if (!ok) {
      final e = s.error;
      await s.close();
      s.dispose();
      setState(() {
        _busy = false;
        _msg = e ?? 'Could not connect';
      });
      return;
    }
    await _showSession(s);
  }

  Future<void> _quick() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _msg = 'Looking for the host...';
    });
    final mine = await localIps();
    final tried = <String>{};
    for (final ip in mine) {
      final p = ip.split('.');
      if (p.length != 4) {
        continue;
      }
      final host = '${p[0]}.${p[1]}.${p[2]}.1';
      if (host == ip || !tried.add(host)) {
        continue;
      }
      final s = ClientSession(widget.name, host, kGamePort);
      final ok = await s.connect();
      if (!mounted) {
        await s.close();
        s.dispose();
        return;
      }
      if (ok) {
        await _showSession(s);
        return;
      }
      await s.close();
      s.dispose();
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _msg = 'No host found. Are you connected to the host hotspot?';
      });
    }
  }

  void _manual() {
    final txt = _ip.text.trim();
    if (txt.isEmpty) {
      return;
    }
    final parts = txt.split(':');
    final port = parts.length > 1 ? (int.tryParse(parts[1]) ?? kGamePort) : kGamePort;
    _connectTo(parts[0].trim(), port);
  }

  Widget _roomTile(RoomInfo r) {
    final tn = (r.track >= 0 && r.track < kTrackDefs.length) ? kTrackDefs[r.track].name : 'Track';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: kBg,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _busy ? null : () => _connectTo(r.ip, r.port),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: <Widget>[
                const Icon(Icons.wifi, color: kAccent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(r.name, style: kBoldStyle),
                      Text('${r.players}/$kMaxCars players - $tn - ${r.laps} laps', style: kMutedStyle),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rooms = _disc.rooms.values.toList();
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: <Widget>[
            Row(
              children: <Widget>[
                IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.arrow_back)),
                const Text('Join a race', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 8),
            Panel(
              title: 'ROOMS ON THIS WI-FI',
              child: rooms.isEmpty
                  ? const Text(
                      'Searching... make sure you are connected to the host hotspot or the same router.',
                      style: kMutedStyle,
                    )
                  : Column(children: rooms.map(_roomTile).toList()),
            ),
            BigButton(
              label: 'QUICK CONNECT',
              icon: Icons.bolt,
              color: kCoral,
              onTap: _busy ? null : _quick,
            ),
            const SizedBox(height: 12),
            Panel(
              title: 'OR ENTER THE HOST IP',
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _ip,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        hintText: '192.168.43.1',
                        filled: true,
                        fillColor: kBg,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(onPressed: _busy ? null : _manual, child: const Text('GO')),
                ],
              ),
            ),
            if (_msg != null) Padding(padding: const EdgeInsets.all(8), child: Text(_msg!, style: kMutedStyle)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// session wrapper: lobby <-> race
// ---------------------------------------------------------------------------

class SessionScreen extends StatefulWidget {
  final Session session;

  const SessionScreen({super.key, required this.session});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  @override
  void initState() {
    super.initState();
    widget.session.addListener(_changed);
    widget.session.open();
  }

  void _changed() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    final s = widget.session;
    s.removeListener(_changed);
    s.close();
    s.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final note = s.notice;
    if (note != null) {
      return NoticeScreen(text: note);
    }
    if (s.inRace) {
      return RaceScreen(key: ValueKey<int>(s.raceNo), session: s);
    }
    return LobbyScreen(s: s);
  }
}

// ---------------------------------------------------------------------------
// lobby
// ---------------------------------------------------------------------------

class LobbyScreen extends StatelessWidget {
  final Session s;

  const LobbyScreen({super.key, required this.s});

  Widget _header() {
    final children = <Widget>[];
    if (s.isHost && s.online) {
      children.add(const Text('You are hosting this room', style: kBoldStyle));
      if (s.ips.isEmpty) {
        children.add(const Text(
          'Turn on your phone hotspot (or join a shared Wi-Fi) so friends can find you.',
          style: kMutedStyle,
        ));
      } else {
        for (final ip in s.ips) {
          children.add(SelectableText(
            '$ip : ${s.port}',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kAccent),
          ));
        }
        children.add(const Text(
          'Friends: connect to this Wi-Fi, open the app, tap Join a race.',
          style: kMutedStyle,
        ));
      }
    } else if (s.isHost) {
      children.add(const Text('Practice mode - just you and the bots', style: kBoldStyle));
    } else {
      children.add(const Text('Connected to the host', style: kBoldStyle));
    }
    return Panel(
      title: 'ROOM',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _tracks(bool host) {
    return SizedBox(
      height: 170,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: kTrackCount,
        separatorBuilder: (BuildContext c, int i) => const SizedBox(width: 10),
        itemBuilder: (BuildContext c, int i) {
          final sel = s.cfg.trackId == i;
          final def = kTrackDefs[i];
          return GestureDetector(
            onTap: host ? () => s.setTrack(i) : null,
            child: Container(
              width: 108,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: kBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: sel ? kAccent : Colors.transparent, width: 3),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(child: CustomPaint(painter: TrackPreviewPainter(Track.byId(i)))),
                  const SizedBox(height: 4),
                  Text(def.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  Text(def.level, textAlign: TextAlign.center, style: kMutedStyle),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _stepper(String label, int value, int min, int max, void Function(int)? onChange) {
    return Row(
      children: <Widget>[
        Expanded(child: Text(label, style: const TextStyle(fontSize: 16))),
        IconButton(
          onPressed: (onChange != null && value > min) ? () => onChange(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
          width: 34,
          child: Center(child: Text('$value', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
        ),
        IconButton(
          onPressed: (onChange != null && value < max) ? () => onChange(value + 1) : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }

  Widget _colors() {
    final taken = <int>{};
    int mine = -1;
    for (final h in s.humans) {
      if (h.id == s.myId) {
        mine = h.color;
      } else {
        taken.add(h.color);
      }
    }
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: <Widget>[
        for (int i = 0; i < kPalette.length; i++)
          GestureDetector(
            onTap: taken.contains(i) ? null : () => s.setColor(i),
            child: Opacity(
              opacity: taken.contains(i) ? 0.25 : 1.0,
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: kPalette[i],
                  shape: BoxShape.circle,
                  border: Border.all(color: mine == i ? Colors.white : const Color(0xFF111111), width: mine == i ? 4 : 3),
                ),
                child: mine == i ? const Icon(Icons.check, color: Colors.white, size: 22) : null,
              ),
            ),
          ),
      ],
    );
  }

  Widget _playerRow(Color c, String name, String tag, bool me) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: Colors.black, width: 2)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(name, style: TextStyle(fontSize: 16, fontWeight: me ? FontWeight.w800 : FontWeight.w500)),
          ),
          if (me) const Text('YOU  ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: kAccent)),
          if (tag.isNotEmpty) Text(tag, style: kMutedStyle),
        ],
      ),
    );
  }

  Widget _players() {
    final rows = <Widget>[];
    for (final h in s.humans) {
      rows.add(_playerRow(kPalette[h.color % kPalette.length], h.name, h.id == 0 ? 'HOST' : '', h.id == s.myId));
    }
    for (int i = 0; i < s.effectiveBots; i++) {
      rows.add(_playerRow(const Color(0xFF6B7A8C), kBotNames[i % kBotNames.length], 'BOT', false));
    }
    final empty = kMaxCars - s.humans.length - s.effectiveBots;
    if (empty > 0) {
      rows.add(Text('$empty empty slot(s)', style: kMutedStyle));
    }
    return Column(children: rows);
  }

  @override
  Widget build(BuildContext context) {
    if (s.humans.isEmpty) {
      return Scaffold(
        backgroundColor: kBg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(s.isHost ? 'Starting room...' : 'Joining...', style: kMutedStyle),
              const SizedBox(height: 16),
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            ],
          ),
        ),
      );
    }
    final host = s.isHost;
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
          children: <Widget>[
            _header(),
            Panel(title: 'TRACK', child: _tracks(host)),
            Panel(
              title: 'RACE SETTINGS',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _stepper('Laps', s.cfg.laps, 1, 10, host ? s.setLaps : null),
                  _stepper('Bots', s.cfg.bots, 0, 5, host ? s.setBots : null),
                  Text('${s.effectiveBots} bot(s) will race (6 cars max in total)', style: kMutedStyle),
                  const SizedBox(height: 12),
                  const Text('Bot skill', style: TextStyle(fontSize: 16)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: <Widget>[
                      for (int i = 0; i < kDiffNames.length; i++)
                        ChoiceChip(
                          label: Text(kDiffNames[i]),
                          selected: s.cfg.diff == i,
                          onSelected: host ? (bool v) => s.setDiff(i) : null,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Panel(title: 'YOUR CAR COLOUR', child: _colors()),
            Panel(title: 'PLAYERS (${s.humans.length}/$kMaxCars)', child: _players()),
            if (host)
              BigButton(label: 'START RACE', icon: Icons.flag, onTap: s.startRace)
            else
              const Center(child: Text('Waiting for the host to start...', style: kMutedStyle)),
            const SizedBox(height: 8),
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Leave room')),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// race
// ---------------------------------------------------------------------------

class Hud {
  final int place;
  final int total;
  final int lap;
  final int laps;
  final String center;

  const Hud({this.place = 1, this.total = 1, this.lap = 1, this.laps = 3, this.center = ''});

  @override
  bool operator ==(Object other) {
    return other is Hud &&
        other.place == place &&
        other.total == total &&
        other.lap == lap &&
        other.laps == laps &&
        other.center == center;
  }

  @override
  int get hashCode => Object.hash(place, total, lap, laps, center);
}

class RaceScreen extends StatefulWidget {
  final Session session;

  const RaceScreen({super.key, required this.session});

  @override
  State<RaceScreen> createState() => _RaceScreenState();
}

class _RaceScreenState extends State<RaceScreen> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  final ValueNotifier<Hud> _hud = ValueNotifier<Hud>(const Hud());
  ui.Image? _bg;
  bool _bgStarted = false;
  Duration _last = Duration.zero;
  bool _skip = false;
  final Map<int, int> _sides = <int, int>{};
  double _steer = 0;
  bool _brake = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_bgStarted) {
      _bgStarted = true;
      final size = MediaQuery.sizeOf(context);
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final fit = math.min(size.width / kWorldW, size.height / kWorldH) * dpr;
      final scale = (fit * 0.85).clamp(0.5, 1.2).toDouble();
      _loadBg(scale);
    }
  }

  Future<void> _loadBg(double scale) async {
    final tr = widget.session.track;
    if (tr == null) {
      return;
    }
    final img = await renderTrackImage(tr, scale);
    if (!mounted) {
      img.dispose();
      return;
    }
    setState(() {
      _bg = img;
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    _hud.dispose();
    _bg?.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    var dt = (elapsed - _last).inMicroseconds / 1000000.0;
    _last = elapsed;
    if (dt > 0.1) {
      dt = 0.1;
    }
    final s = widget.session;
    s.setInput(_steer, _brake);
    s.update(dt);
    if (Settings.lowFps) {
      _skip = !_skip;
      if (_skip) {
        return;
      }
    }
    _frame.value++;
    _updateHud();
  }

  void _updateHud() {
    final s = widget.session;
    final me = s.myCar;
    int lap = 1;
    int place = 1;
    if (me != null) {
      lap = me.crossings.clamp(1, s.cfg.laps).toInt();
      place = me.place;
    }
    String center = '';
    if (s.phase == RacePhase.countdown) {
      final n = (-s.clock).ceil();
      center = n > 3 ? 'READY' : (n <= 0 ? 'GO!' : '$n');
    } else if (s.phase == RacePhase.racing && s.clock < 0.8) {
      center = 'GO!';
    }
    final h = Hud(place: place, total: s.cars.length, lap: lap, laps: s.cfg.laps, center: center);
    if (h != _hud.value) {
      _hud.value = h;
    }
  }

  void _pt(PointerEvent e) {
    final w = MediaQuery.sizeOf(context).width;
    _sides[e.pointer] = e.localPosition.dx < w / 2 ? -1 : 1;
    _recalc();
  }

  void _rm(PointerEvent e) {
    _sides.remove(e.pointer);
    _recalc();
  }

  void _recalc() {
    final l = _sides.containsValue(-1);
    final r = _sides.containsValue(1);
    _steer = (r ? 1.0 : 0.0) - (l ? 1.0 : 0.0);
    _brake = l && r;
  }

  Future<void> _confirmLeave() async {
    final s = widget.session;
    final ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('Leave race?'),
        content: Text(
          (s.isHost && s.online) ? 'You are the host - leaving ends the room for everyone.' : 'You will drop out of the race.',
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Stay')),
          TextButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Leave')),
        ],
      ),
    );
    if (ok == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  Widget _pill(String label, String value, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2B3440),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black, width: 3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white70)),
          const SizedBox(width: 8),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: c)),
        ],
      ),
    );
  }

  Widget _hint(IconData icon) {
    return Container(
      width: 56,
      height: 56,
      decoration: const BoxDecoration(color: Color(0x66000000), shape: BoxShape.circle),
      child: Icon(icon, color: Colors.white70, size: 30),
    );
  }

  Widget _resultRow(ResultRow r) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          SizedBox(width: 28, child: Text('${r.place}', style: kBoldStyle)),
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: kPalette[r.color % kPalette.length],
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black, width: 2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              r.isMe ? '${r.name} (you)' : r.name,
              style: TextStyle(fontSize: 16, fontWeight: r.isMe ? FontWeight.w800 : FontWeight.w500),
            ),
          ),
          Text(fmtTime(r.time), style: kBoldStyle),
        ],
      ),
    );
  }

  Widget _resultsCard(Session s) {
    return Container(
      width: 330,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(20)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text(
            'RESULTS',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 3, color: kAccent),
          ),
          const SizedBox(height: 10),
          for (final r in s.results) _resultRow(r),
          const SizedBox(height: 14),
          if (s.isHost)
            BigButton(label: 'BACK TO LOBBY', onTap: s.backToLobby)
          else
            const Text('Waiting for the host...', textAlign: TextAlign.center, style: kMutedStyle),
          const SizedBox(height: 6),
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Leave')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return Scaffold(
      backgroundColor: const Color(0xFF8CB30B),
      body: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _pt,
        onPointerMove: _pt,
        onPointerUp: _rm,
        onPointerCancel: _rm,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            RepaintBoundary(child: CustomPaint(painter: RacePainter(s, _bg, _frame))),
            Positioned.fill(
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    children: <Widget>[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          ValueListenableBuilder<Hud>(
                            valueListenable: _hud,
                            builder: (BuildContext c, Hud h, Widget? w) => _pill('POS', '${h.place}/${h.total}', kAccent),
                          ),
                          GestureDetector(
                            onTap: _confirmLeave,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.black, width: 3),
                              ),
                              child: const Icon(Icons.close, color: Colors.black, size: 22),
                            ),
                          ),
                          ValueListenableBuilder<Hud>(
                            valueListenable: _hud,
                            builder: (BuildContext c, Hud h, Widget? w) => _pill('LAP', '${h.lap}/${h.laps}', kCoral),
                          ),
                        ],
                      ),
                      const Spacer(),
                      IgnorePointer(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            _hint(Icons.arrow_back),
                            const Text('hold both = brake', style: TextStyle(color: Colors.white70, fontSize: 12)),
                            _hint(Icons.arrow_forward),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Center(
              child: IgnorePointer(
                child: ValueListenableBuilder<Hud>(
                  valueListenable: _hud,
                  builder: (BuildContext c, Hud h, Widget? w) {
                    if (h.center.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Text(
                      h.center,
                      style: const TextStyle(
                        fontSize: 88,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        shadows: <Shadow>[
                          Shadow(color: Colors.black, offset: Offset(4, 4)),
                          Shadow(color: Colors.black, offset: Offset(-2, -2)),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            if (s.showResults)
              Positioned.fill(
                child: Container(
                  color: const Color(0xCC000000),
                  child: Center(child: _resultsCard(s)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
