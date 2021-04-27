import 'dart:convert';
import 'dart:io';

import 'package:robustirc/robustirc.dart';

void main(List<String> args) async {
  final session = await RobustSession.connect(
    args.first,
    userAgent:
        'RawIRC (robustirc.dart test client, see https://github.com/Ampless/robustirc.dart)',
  );
  session.getMessages((id, data) => print(data));
  stdin.transform(utf8.decoder).transform(LineSplitter()).listen((s) async {
    print(await session.postMessage(s));
  }, onDone: () => session.quit('rawirc - stdin closed').then((_) => exit(0)));
}
