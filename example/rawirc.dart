import 'dart:convert';
import 'dart:io';

import 'package:robustirc/robustirc.dart';

void main(List<String> args) async {
  final irc = await RobustIrc.connect(
    args[0],
    userAgent:
        'RawIRC (the robustirc.dart test client, see https://github.com/Ampless/robustirc.dart)',
  );
  (await irc.getMessages()).stream.transform(utf8.decoder).listen(print);
  stdin.transform(utf8.decoder).transform(LineSplitter()).listen((s) async {
    print(await irc.postMessage(s));
  }, onDone: () async => print(await irc.close('rawirc - stdin closed')));
}
