import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 本机单实例：谁先占住这个回环端口，谁就是首个实例。
const _port = 47621;
const _hello = 'ENODE-PING';
const _ack = 'ENODE-OK';

/// 抢到端口返回 true（本进程继续启动）；确认已有实例被唤醒返回 false（调用方应立刻退出）。
/// 端口被别的程序占着时也算“没有兄弟实例”，照常启动，不至于起不来。
Future<bool> claimSingleInstance({required void Function() onActivate}) async {
  ServerSocket? server;
  try {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, _port);
  } on SocketException {
    server = null;
  }
  if (server == null) return !await _wakeExisting();

  server.listen((socket) {
    socket.listen((data) {
      if (utf8.decode(data, allowMalformed: true).trim() != _hello) {
        socket.destroy();
        return;
      }
      socket.write(_ack);
      unawaited(socket.flush().whenComplete(socket.destroy));
      onActivate();
    });
  });
  return true;
}

Future<bool> _wakeExisting() async {
  Socket? socket;
  try {
    socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      _port,
      timeout: const Duration(milliseconds: 800),
    );
    socket.add(utf8.encode(_hello));
    await socket.flush();
    final reply = await socket.first.timeout(const Duration(milliseconds: 800));
    return utf8.decode(reply, allowMalformed: true).trim() == _ack;
  } on Object {
    return false;
  } finally {
    socket?.destroy();
  }
}
