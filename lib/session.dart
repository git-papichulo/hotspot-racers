import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'model.dart';
import 'native.dart';
import 'net.dart';
import 'sim.dart';
import 'track.dart';

double _r1(double v) => (v * 10).roundToDouble() / 10;
double _r2(double v) => (v * 100).roundToDouble() / 100;

class SnapCar {
  double x = 0;
  double y = 0;
  double a = 0;
  double vx = 0;
  double vy = 0;
  int crossings = 0;
  int place = 1;
  bool finished = false;
}

abstract class Session extends ChangeNotifier {
  final RaceConfig cfg = RaceConfig();
  final List<PlayerInfo> humans = <PlayerInfo>[];
  int myId = 0;
  int effectiveBots = 0;
  bool inRace = false;
  int raceNo = 0;
  String? notice;
  bool closed = false;
  bool online = true;
  int port = kGamePort;
  List<String> ips = <String>[];
  String hostName = '';

  Track? track;
  List<Car> cars = <Car>[];
  RacePhase phase = RacePhase.countdown;
  double clock = -3.5;
  List<ResultRow> results = <ResultRow>[];
  bool showResults = false;
  bool _disposed = false;

  bool get isHost;

  Car? get myCar {
    for (final c in cars) {
      if (c.humanId == myId) {
        return c;
      }
    }
    return null;
  }

  @override
  void notifyListeners() {
    if (!_disposed) {
      super.notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> open() async {}
  void setColor(int c);
  void setInput(double steer, bool brake);
  void update(double dt);
  void startRace() {}
  void backToLobby() {}
  void setTrack(int id) {}
  void setLaps(int n) {}
  void setBots(int n) {}
  void setDiff(int d) {}
  Future<void> close();
}

// ---------------------------------------------------------------------------
// HOST
// ---------------------------------------------------------------------------

class HostSession extends Session {
  HostSession(String name, {required bool isOnline}) {
    hostName = name;
    online = isOnline;
  }

  HttpServer? _server;
  RawDatagramSocket? _beacon;
  Timer? _beaconTimer;
  final Map<int, WebSocket> _sockets = <int, WebSocket>{};
  final Map<int, double> _lastInput = <int, double>{};
  final Stopwatch _sw = Stopwatch()..start();
  final math.Random _rnd = math.Random();
  RaceSim? _sim;
  int _nextId = 1;
  int _seq = 0;
  double _snapAcc = 0;

  double get _now => _sw.elapsedMicroseconds / 1000000.0;

  @override
  bool get isHost => true;

  @override
  Future<void> open() async {
    await Native.prepare(bindWifi: false);
    final saved = await Native.getPref('cfg');
    if (saved != null && saved.isNotEmpty) {
      try {
        cfg.applyJson(jsonDecode(saved) as Map<String, dynamic>);
      } catch (_) {}
    }
    if (closed) {
      return;
    }
    humans.add(PlayerInfo(0, hostName, 0));
    myId = 0;
    _refreshBots();
    if (online) {
      await _startServer();
      await _startBeacon();
    }
    notifyListeners();
  }

  void _refreshBots() {
    var e = math.min(cfg.bots, kMaxCars - humans.length);
    if (e < 0) {
      e = 0;
    }
    effectiveBots = e;
  }

  // ---- lobby controls ----

  @override
  void setTrack(int id) {
    cfg.trackId = id.clamp(0, kTrackCount - 1).toInt();
    _cfgChanged();
  }

  @override
  void setLaps(int n) {
    cfg.laps = n.clamp(1, 10).toInt();
    _cfgChanged();
  }

  @override
  void setBots(int n) {
    cfg.bots = n.clamp(0, 5).toInt();
    _cfgChanged();
  }

  @override
  void setDiff(int d) {
    cfg.diff = d.clamp(0, 2).toInt();
    _cfgChanged();
  }

  void _cfgChanged() {
    _refreshBots();
    Native.setPref('cfg', jsonEncode(cfg.toJson()));
    _broadcastLobby();
    notifyListeners();
  }

  @override
  void setColor(int c) {
    _setColorFor(0, c);
  }

  void _setColorFor(int id, int c) {
    if (inRace || c < 0 || c >= kPalette.length) {
      return;
    }
    for (final h in humans) {
      if (h.id != id && h.color == c) {
        return;
      }
    }
    for (final h in humans) {
      if (h.id == id) {
        h.color = c;
      }
    }
    _broadcastLobby();
    notifyListeners();
  }

  int _freeColor() {
    final used = <int>{};
    for (final h in humans) {
      used.add(h.color);
    }
    for (int i = 0; i < kPalette.length; i++) {
      if (!used.contains(i)) {
        return i;
      }
    }
    return 0;
  }

  // ---- network ----

  Future<void> _startServer() async {
    HttpServer? srv;
    for (int p = kGamePort; p < kGamePort + 10; p++) {
      try {
        srv = await HttpServer.bind(InternetAddress.anyIPv4, p);
        port = p;
        break;
      } catch (_) {}
    }
    if (srv == null) {
      notice = 'Could not open a network port. Close other apps and try again.';
      return;
    }
    _server = srv;
    srv.listen((HttpRequest req) async {
      if (WebSocketTransformer.isUpgradeRequest(req)) {
        try {
          final ws = await WebSocketTransformer.upgrade(req, compression: CompressionOptions.compressionOff);
          ws.pingInterval = const Duration(seconds: 4);
          _onSocket(ws);
        } catch (_) {}
      } else {
        try {
          req.response.statusCode = HttpStatus.forbidden;
          await req.response.close();
        } catch (_) {}
      }
    }, onError: (Object e) {});
  }

  void _onSocket(WebSocket ws) {
    int pid = -1;
    ws.listen((dynamic data) {
      if (closed || data is! String) {
        return;
      }
      Map<String, dynamic> m;
      try {
        m = jsonDecode(data) as Map<String, dynamic>;
      } catch (_) {
        return;
      }
      final t = m['t'];
      if (t == 'join') {
        if (pid >= 0) {
          return;
        }
        if (inRace) {
          _sendRaw(ws, jsonEncode(<String, dynamic>{'t': 'busy'}));
          ws.close();
          return;
        }
        if (humans.length >= kMaxCars) {
          _sendRaw(ws, jsonEncode(<String, dynamic>{'t': 'full'}));
          ws.close();
          return;
        }
        final id = _nextId++;
        var name = (m['n'] ?? 'Player').toString().trim();
        if (name.isEmpty) {
          name = 'Player';
        }
        if (name.length > 14) {
          name = name.substring(0, 14);
        }
        humans.add(PlayerInfo(id, name, _freeColor()));
        _sockets[id] = ws;
        _lastInput[id] = _now;
        pid = id;
        _refreshBots();
        _sendRaw(ws, jsonEncode(<String, dynamic>{'t': 'welcome', 'id': id}));
        _broadcastLobby();
        notifyListeners();
      } else if (pid >= 0) {
        _onMessage(pid, m);
      }
    }, onDone: () {
      if (pid >= 0) {
        _dropPlayer(pid);
      }
    }, onError: (Object e) {
      if (pid >= 0) {
        _dropPlayer(pid);
      }
    }, cancelOnError: true);
  }

  void _onMessage(int id, Map<String, dynamic> m) {
    final t = m['t'];
    if (t == 'in') {
      for (final c in cars) {
        if (c.humanId == id) {
          final s = m['s'];
          c.inSteer = s is num ? s.toDouble() : 0.0;
          c.inBrake = m['b'] == 1;
          _lastInput[id] = _now;
        }
      }
    } else if (t == 'color') {
      final c = m['c'];
      if (c is num) {
        _setColorFor(id, c.toInt());
      }
    } else if (t == 'bye') {
      _dropPlayer(id);
    }
  }

  void _dropPlayer(int id) {
    final ws = _sockets.remove(id);
    _lastInput.remove(id);
    if (ws != null) {
      try {
        ws.close();
      } catch (_) {}
    }
    if (inRace) {
      for (final c in cars) {
        if (c.humanId == id) {
          c.isBot = true;
          c.humanId = -1;
          c.skill = kDiffSkill[cfg.diff];
        }
      }
      humans.removeWhere((PlayerInfo h) => h.id == id);
    } else {
      humans.removeWhere((PlayerInfo h) => h.id == id);
      _refreshBots();
      _broadcastLobby();
    }
    notifyListeners();
  }

  void _sendRaw(WebSocket ws, String s) {
    try {
      ws.add(s);
    } catch (_) {}
  }

  void _broadcastLobby() {
    if (_sockets.isEmpty) {
      return;
    }
    final msg = jsonEncode(<String, dynamic>{
      't': 'lobby',
      'cfg': cfg.toJson(),
      'pl': humans.map((PlayerInfo h) => h.toJson()).toList(),
      'eb': effectiveBots,
    });
    for (final ws in _sockets.values) {
      _sendRaw(ws, msg);
    }
  }

  Future<void> _startBeacon() async {
    try {
      final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      s.broadcastEnabled = true;
      _beacon = s;
    } catch (_) {
      return;
    }
    _beaconTimer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      _sendBeacon();
    });
    _sendBeacon();
  }

  Future<void> _sendBeacon() async {
    final sock = _beacon;
    if (sock == null || closed) {
      return;
    }
    final found = await localIps();
    if (closed) {
      return;
    }
    if (found.join(',') != ips.join(',')) {
      ips = found;
      notifyListeners();
    }
    if (inRace) {
      return;
    }
    final data = utf8.encode(jsonEncode(<String, dynamic>{
      'g': 'HRACE',
      'n': hostName,
      'p': port,
      'pl': humans.length,
      'tr': cfg.trackId,
      'lp': cfg.laps,
    }));
    final targets = <String>{'255.255.255.255'};
    for (final ip in found) {
      final p = ip.split('.');
      if (p.length == 4) {
        targets.add('${p[0]}.${p[1]}.${p[2]}.255');
      }
    }
    for (final t in targets) {
      try {
        sock.send(data, InternetAddress(t), kDiscoveryPort);
      } catch (_) {}
    }
  }

  // ---- race ----

  @override
  void startRace() {
    if (inRace || humans.isEmpty) {
      return;
    }
    final tr = Track.byId(cfg.trackId);
    final list = <Car>[];
    final used = <int>{};
    for (final h in humans) {
      list.add(Car(list.length, h.name, h.color, isBot: false, humanId: h.id));
      used.add(h.color);
    }
    _refreshBots();
    for (int i = 0; i < effectiveBots; i++) {
      int col = 0;
      for (int k = 0; k < kPalette.length; k++) {
        if (!used.contains(k)) {
          col = k;
          break;
        }
      }
      used.add(col);
      final c = Car(list.length, kBotNames[i % kBotNames.length], col, isBot: true, humanId: -1);
      c.skill = kDiffSkill[cfg.diff] * (0.97 + 0.03 * _rnd.nextDouble());
      list.add(c);
    }
    placeOnGrid(tr, list, _rnd);
    cars = list;
    track = tr;
    _sim = RaceSim(tr, cfg.laps, list);
    inRace = true;
    raceNo++;
    showResults = false;
    results = <ResultRow>[];
    phase = RacePhase.countdown;
    clock = -3.5;
    _snapAcc = 0;
    final msg = jsonEncode(<String, dynamic>{
      't': 'start',
      'cfg': cfg.toJson(),
      'pl': <Map<String, dynamic>>[
        for (final c in list)
          <String, dynamic>{
            's': c.slot,
            'n': c.name,
            'c': c.color,
            'b': c.isBot ? 1 : 0,
            'h': c.humanId,
            'x': _r1(c.x),
            'y': _r1(c.y),
            'a': _r2(c.a),
          },
      ],
    });
    for (final ws in _sockets.values) {
      _sendRaw(ws, msg);
    }
    notifyListeners();
  }

  @override
  void setInput(double steer, bool brake) {
    final c = myCar;
    if (c != null) {
      c.inSteer = steer;
      c.inBrake = brake;
    }
  }

  @override
  void update(double dt) {
    final sim = _sim;
    if (sim == null) {
      return;
    }
    final t = _now;
    for (final c in cars) {
      if (c.humanId > 0) {
        final last = _lastInput[c.humanId] ?? 0.0;
        if (t - last > 1.5) {
          c.inSteer = 0;
          c.inBrake = false;
        }
      }
    }
    final before = sim.phase;
    sim.update(dt);
    phase = sim.phase;
    clock = sim.clock;
    _snapAcc += dt;
    if (_snapAcc >= 0.05) {
      _snapAcc = 0;
      _broadcastSnapshot();
    }
    if (before != RacePhase.finished && sim.phase == RacePhase.finished) {
      _finishRace();
    }
  }

  void _broadcastSnapshot() {
    if (_sockets.isEmpty) {
      return;
    }
    final rows = <List<num>>[];
    for (final c in cars) {
      rows.add(<num>[
        _r1(c.x),
        _r1(c.y),
        _r2(c.a),
        c.vx.round(),
        c.vy.round(),
        c.crossings,
        c.place,
        c.finished ? 1 : 0,
      ]);
    }
    final msg = jsonEncode(<String, dynamic>{
      't': 's',
      'q': ++_seq,
      'ph': phase.index,
      'ck': _r2(clock),
      'c': rows,
    });
    for (final ws in _sockets.values) {
      _sendRaw(ws, msg);
    }
  }

  void _finishRace() {
    final order = List<Car>.from(cars);
    order.sort((Car a, Car b) => a.place.compareTo(b.place));
    results = <ResultRow>[
      for (final c in order)
        ResultRow(c.place, c.name, c.color, c.finished ? c.finishTime : -1.0, c.isBot, c.humanId == myId),
    ];
    showResults = true;
    final msg = jsonEncode(<String, dynamic>{
      't': 'end',
      'r': <List<num>>[
        for (final c in order) <num>[c.slot, c.place, c.finished ? _r2(c.finishTime) : -1],
      ],
    });
    for (final ws in _sockets.values) {
      _sendRaw(ws, msg);
    }
    notifyListeners();
  }

  @override
  void backToLobby() {
    if (!inRace) {
      return;
    }
    inRace = false;
    showResults = false;
    _sim = null;
    cars = <Car>[];
    track = null;
    _refreshBots();
    _broadcastLobby();
    notifyListeners();
  }

  @override
  Future<void> close() async {
    if (closed) {
      return;
    }
    closed = true;
    _beaconTimer?.cancel();
    _beacon?.close();
    for (final ws in _sockets.values) {
      try {
        ws.close();
      } catch (_) {}
    }
    _sockets.clear();
    try {
      await _server?.close(force: true);
    } catch (_) {}
    await Native.release();
  }
}

// ---------------------------------------------------------------------------
// CLIENT
// ---------------------------------------------------------------------------

class ClientSession extends Session {
  final String name;
  final String host;
  final int hostPort;

  ClientSession(this.name, this.host, this.hostPort);

  WebSocket? _ws;
  String? error;
  List<SnapCar?> _snap = <SnapCar?>[];
  double _snapTime = 0;
  bool _haveSnap = false;
  final Stopwatch _sw = Stopwatch()..start();
  double _inSteer = 0;
  bool _inBrake = false;
  double _lastSentSteer = 99;
  bool _lastSentBrake = false;
  double _sendAcc = 0;
  double _acc = 0;

  double get _now => _sw.elapsedMicroseconds / 1000000.0;

  @override
  bool get isHost => false;

  Future<bool> connect() async {
    try {
      await Native.prepare(bindWifi: true);
      final ws = await WebSocket
          .connect('ws://$host:$hostPort', compression: CompressionOptions.compressionOff)
          .timeout(const Duration(seconds: 4));
      ws.pingInterval = const Duration(seconds: 4);
      _ws = ws;
      ws.listen(_onData, onDone: _onClosed, onError: (Object e) => _onClosed(), cancelOnError: true);
      _send(<String, dynamic>{'t': 'join', 'n': name});
      return true;
    } catch (e) {
      error = 'Could not reach $host';
      return false;
    }
  }

  void _send(Map<String, dynamic> m) {
    try {
      _ws?.add(jsonEncode(m));
    } catch (_) {}
  }

  void _onClosed() {
    if (closed) {
      return;
    }
    notice ??= 'Disconnected from the host';
    notifyListeners();
  }

  void _onData(dynamic data) {
    if (data is! String) {
      return;
    }
    Map<String, dynamic> m;
    try {
      m = jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final t = m['t'];
    if (t == 'welcome') {
      myId = (m['id'] as num).toInt();
    } else if (t == 'lobby') {
      cfg.applyJson(m['cfg'] as Map<String, dynamic>);
      humans.clear();
      for (final e in (m['pl'] as List<dynamic>)) {
        humans.add(PlayerInfo.fromJson(e as Map<String, dynamic>));
      }
      effectiveBots = (m['eb'] as num).toInt();
      if (inRace) {
        inRace = false;
        showResults = false;
        cars = <Car>[];
        track = null;
      }
      notifyListeners();
    } else if (t == 'full') {
      notice = 'The room is full (6 players max)';
      notifyListeners();
    } else if (t == 'busy') {
      notice = 'A race is already running. Try again when it ends.';
      notifyListeners();
    } else if (t == 'start') {
      _onStart(m);
    } else if (t == 's') {
      _onSnapshot(m);
    } else if (t == 'end') {
      _onEnd(m);
    }
  }

  void _onStart(Map<String, dynamic> m) {
    cfg.applyJson(m['cfg'] as Map<String, dynamic>);
    final tr = Track.byId(cfg.trackId);
    final list = <Car>[];
    final snaps = <SnapCar?>[];
    for (final e in (m['pl'] as List<dynamic>)) {
      final j = e as Map<String, dynamic>;
      final c = Car(
        (j['s'] as num).toInt(),
        (j['n'] ?? 'Player').toString(),
        (j['c'] as num).toInt(),
        isBot: (j['b'] as num) == 1,
        humanId: (j['h'] as num).toInt(),
      );
      c.x = (j['x'] as num).toDouble();
      c.y = (j['y'] as num).toDouble();
      c.a = (j['a'] as num).toDouble();
      snapToTrack(tr, c);
      list.add(c);
      snaps.add(null);
    }
    cars = list;
    _snap = snaps;
    track = tr;
    inRace = true;
    raceNo++;
    phase = RacePhase.countdown;
    clock = -3.5;
    results = <ResultRow>[];
    showResults = false;
    _haveSnap = false;
    _acc = 0;
    notifyListeners();
  }

  void _onSnapshot(Map<String, dynamic> m) {
    final rows = m['c'] as List<dynamic>;
    _snapTime = _now;
    for (int i = 0; i < rows.length && i < _snap.length; i++) {
      final r = rows[i] as List<dynamic>;
      final s = _snap[i] ?? SnapCar();
      s.x = (r[0] as num).toDouble();
      s.y = (r[1] as num).toDouble();
      s.a = (r[2] as num).toDouble();
      s.vx = (r[3] as num).toDouble();
      s.vy = (r[4] as num).toDouble();
      s.crossings = (r[5] as num).toInt();
      s.place = (r[6] as num).toInt();
      s.finished = (r[7] as num) == 1;
      _snap[i] = s;
    }
    final ph = (m['ph'] as num).toInt();
    if (ph >= 0 && ph < RacePhase.values.length) {
      phase = RacePhase.values[ph];
    }
    clock = (m['ck'] as num).toDouble();
    _haveSnap = true;
  }

  void _onEnd(Map<String, dynamic> m) {
    final rows = <ResultRow>[];
    for (final e in (m['r'] as List<dynamic>)) {
      final r = e as List<dynamic>;
      final slot = (r[0] as num).toInt();
      if (slot < 0 || slot >= cars.length) {
        continue;
      }
      final c = cars[slot];
      rows.add(ResultRow((r[1] as num).toInt(), c.name, c.color, (r[2] as num).toDouble(), c.isBot, c.humanId == myId));
    }
    results = rows;
    showResults = true;
    notifyListeners();
  }

  @override
  void setColor(int c) {
    _send(<String, dynamic>{'t': 'color', 'c': c});
  }

  @override
  void setInput(double steer, bool brake) {
    _inSteer = steer;
    _inBrake = brake;
  }

  @override
  void update(double dt) {
    final tr = track;
    if (!inRace || tr == null || cars.isEmpty) {
      return;
    }
    final age = math.min(_now - _snapTime, 0.25);
    final go = phase == RacePhase.racing;
    final mine = myCar;
    _sendAcc += dt;
    if (_inSteer != _lastSentSteer || _inBrake != _lastSentBrake || _sendAcc >= 0.1) {
      _sendAcc = 0;
      _lastSentSteer = _inSteer;
      _lastSentBrake = _inBrake;
      _send(<String, dynamic>{'t': 'in', 's': _inSteer.round(), 'b': _inBrake ? 1 : 0});
    }
    if (mine != null) {
      mine.inSteer = _inSteer;
      mine.inBrake = _inBrake;
    }
    _acc += dt;
    if (_acc > 0.25) {
      _acc = 0.25;
    }
    while (_acc >= kStep) {
      _acc -= kStep;
      if (mine != null && _haveSnap) {
        stepCar(mine, kStep, tr, go);
      }
    }
    for (int i = 0; i < cars.length; i++) {
      final c = cars[i];
      final s = i < _snap.length ? _snap[i] : null;
      if (s == null) {
        continue;
      }
      c.crossings = s.crossings;
      c.place = s.place;
      c.finished = s.finished;
      if (c == mine) {
        final tx = s.x + s.vx * (age + 0.05);
        final ty = s.y + s.vy * (age + 0.05);
        final ex = tx - c.x;
        final ey = ty - c.y;
        final err = math.sqrt(ex * ex + ey * ey);
        if (err > 90) {
          c.x = tx;
          c.y = ty;
          c.vx = s.vx;
          c.vy = s.vy;
          c.a = s.a;
        } else {
          final k = err > 24 ? math.min(1.0, 6 * dt) : math.min(1.0, 0.8 * dt);
          c.x += ex * k;
          c.y += ey * k;
          if (err > 24) {
            c.vx += (s.vx - c.vx) * k * 0.5;
            c.vy += (s.vy - c.vy) * k * 0.5;
            c.a += wrapPi(s.a - c.a) * k * 0.5;
          }
        }
      } else {
        final k = math.min(1.0, 14 * dt);
        final tx = s.x + s.vx * age;
        final ty = s.y + s.vy * age;
        c.x += (tx - c.x) * k;
        c.y += (ty - c.y) * k;
        c.a += wrapPi(s.a - c.a) * k;
        c.vx = s.vx;
        c.vy = s.vy;
      }
    }
  }

  @override
  Future<void> close() async {
    if (closed) {
      return;
    }
    closed = true;
    _send(<String, dynamic>{'t': 'bye'});
    try {
      await _ws?.close();
    } catch (_) {}
    await Native.release();
  }
}
