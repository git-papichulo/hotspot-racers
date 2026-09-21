import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'model.dart';

bool _isCellular(String name) {
  final n = name.toLowerCase();
  return n.startsWith('rmnet') ||
      n.startsWith('ccmni') ||
      n.startsWith('v4-') ||
      n.startsWith('dummy') ||
      n.startsWith('tun') ||
      n.startsWith('lo');
}

Future<List<String>> localIps() async {
  final out = <String>[];
  try {
    final ifs = await NetworkInterface.list(includeLoopback: false, type: InternetAddressType.IPv4);
    for (final i in ifs) {
      if (_isCellular(i.name)) {
        continue;
      }
      for (final a in i.addresses) {
        if (!a.isLoopback) {
          out.add(a.address);
        }
      }
    }
  } catch (_) {}
  return out;
}

class Discovery {
  RawDatagramSocket? _sock;
  Timer? _timer;
  final Map<String, RoomInfo> rooms = <String, RoomInfo>{};
  void Function()? onChange;

  Future<void> start() async {
    try {
      final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, kDiscoveryPort, reuseAddress: true);
      s.broadcastEnabled = true;
      _sock = s;
      s.listen((RawSocketEvent ev) {
        if (ev != RawSocketEvent.read) {
          return;
        }
        Datagram? dg = s.receive();
        while (dg != null) {
          _handle(dg);
          dg = s.receive();
        }
      });
    } catch (_) {}
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      final now = DateTime.now();
      final before = rooms.length;
      rooms.removeWhere((String k, RoomInfo r) => now.difference(r.seen).inMilliseconds > 3500);
      if (before != rooms.length) {
        onChange?.call();
      }
    });
  }

  void _handle(Datagram dg) {
    try {
      final j = jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;
      if (j['g'] != 'HRACE') {
        return;
      }
      final ip = dg.address.address;
      final port = (j['p'] as num).toInt();
      final key = '$ip:$port';
      final name = (j['n'] ?? 'Room').toString();
      final pl = (j['pl'] as num).toInt();
      final tr = (j['tr'] as num).toInt();
      final lp = (j['lp'] as num).toInt();
      final r = rooms[key];
      if (r == null) {
        rooms[key] = RoomInfo(ip, port, name, pl, tr, lp, DateTime.now());
        onChange?.call();
      } else {
        final changed = r.name != name || r.players != pl || r.track != tr || r.laps != lp;
        r.name = name;
        r.players = pl;
        r.track = tr;
        r.laps = lp;
        r.seen = DateTime.now();
        if (changed) {
          onChange?.call();
        }
      }
    } catch (_) {}
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _sock?.close();
    _sock = null;
    onChange = null;
  }
}
