import 'dart:ui' show Color;

const int kMaxCars = 6;
const int kTrackCount = 4;
const int kDiscoveryPort = 45454;
const int kGamePort = 45455;

const List<Color> kPalette = <Color>[
  Color(0xFFE53935),
  Color(0xFF1E88E5),
  Color(0xFF43A047),
  Color(0xFFFDD835),
  Color(0xFFFB8C00),
  Color(0xFF8E24AA),
  Color(0xFFEC407A),
  Color(0xFF00ACC1),
];

const List<String> kColorNames = <String>['Red', 'Blue', 'Green', 'Yellow', 'Orange', 'Purple', 'Pink', 'Teal'];
const List<String> kBotNames = <String>['Turbo', 'Dusty', 'Blaze', 'Nitro', 'Rusty', 'Zippy'];
const List<String> kDiffNames = <String>['Easy', 'Normal', 'Hard'];
const List<double> kDiffSkill = <double>[0.82, 0.90, 0.97];

enum RacePhase { countdown, racing, finished }

class Settings {
  static bool lowFps = false;
}

int _asInt(dynamic v, int fallback) => v is num ? v.toInt() : fallback;

class RaceConfig {
  int trackId;
  int laps;
  int bots;
  int diff;

  RaceConfig({this.trackId = 0, this.laps = 3, this.bots = 2, this.diff = 1});

  Map<String, dynamic> toJson() => <String, dynamic>{'tr': trackId, 'lp': laps, 'bt': bots, 'df': diff};

  void applyJson(Map<String, dynamic> j) {
    trackId = _asInt(j['tr'], trackId);
    laps = _asInt(j['lp'], laps);
    bots = _asInt(j['bt'], bots);
    diff = _asInt(j['df'], diff);
    if (trackId < 0 || trackId >= kTrackCount) {
      trackId = 0;
    }
    if (laps < 1) {
      laps = 1;
    }
    if (laps > 10) {
      laps = 10;
    }
    if (bots < 0) {
      bots = 0;
    }
    if (bots > 5) {
      bots = 5;
    }
    if (diff < 0) {
      diff = 0;
    }
    if (diff > 2) {
      diff = 2;
    }
  }
}

class PlayerInfo {
  final int id;
  String name;
  int color;

  PlayerInfo(this.id, this.name, this.color);

  Map<String, dynamic> toJson() => <String, dynamic>{'id': id, 'n': name, 'c': color};

  factory PlayerInfo.fromJson(Map<String, dynamic> j) {
    return PlayerInfo(_asInt(j['id'], 0), (j['n'] ?? 'Player').toString(), _asInt(j['c'], 0));
  }
}

class RoomInfo {
  final String ip;
  final int port;
  String name;
  int players;
  int track;
  int laps;
  DateTime seen;

  RoomInfo(this.ip, this.port, this.name, this.players, this.track, this.laps, this.seen);
}

class ResultRow {
  final int place;
  final String name;
  final int color;
  final double time;
  final bool bot;
  final bool isMe;

  const ResultRow(this.place, this.name, this.color, this.time, this.bot, this.isMe);
}

String fmtTime(double t) {
  if (t < 0) {
    return 'DNF';
  }
  final m = t ~/ 60;
  final s = t - m * 60;
  return '$m:${s.toStringAsFixed(1).padLeft(4, '0')}';
}
