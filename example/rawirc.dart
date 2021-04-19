import 'dart:convert';
import 'dart:io';

import 'package:robustirc/robustirc.dart';

void main(List<String> args) async {
  final session = await RobustSession.connect(
    args[0],
    userAgent:
        'RawIRC (the robustirc.dart test client, see https://github.com/Ampless/robustirc.dart)',
  );
  session.getMessages((id, data) => print(data));
  stdin.transform(utf8.decoder).transform(LineSplitter()).listen((s) async {
    print(await session.postMessage(s));
  }, onDone: () async => print(await session.quit('rawirc - stdin closed')));
}
