import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'server.dart';

final _rand = Random();

//TODO: fix thundering herd (section 4 of the spec)

class RobustSession {
  final String hostname;
  final String prefix;
  RobustIrcServer currentServer;
  List<RobustIrcServer> servers;
  final String sessionId, sessionAuth;
  final String userAgent;
  final http.Client _client = http.Client();

  RobustSession(
    this.hostname,
    this.servers,
    this.userAgent,
    this.sessionId,
    this.sessionAuth,
    this.prefix,
  ) : currentServer = servers[_rand.nextInt(servers.length)];

  void _regenServer() => currentServer = servers[_rand.nextInt(servers.length)];

  static Future<T> _retry<T>(Future<T> Function(bool) f,
      [bool retried = false, int dly = 1]) {
    dly &= 0xff; //delay for at most 128 seconds
    try {
      return f(retried);
    } on Exception {
      return Future.delayed(
          Duration(seconds: dly), () => _retry(f, true, dly * 2));
    }
  }

  static Map<String, String> _sHeaders(String ua, String? sa) {
    final h = {'User-Agent': ua};
    if (sa != null) h['X-Session-Auth'] = sa;
    return h;
  }

  Map<String, String> get _headers => _sHeaders(userAgent, sessionAuth);

  static Uri _makeuri(
      RobustIrcServer server, Function() regenServer, String path, bool retried,
      [Map<String, dynamic> params = const {}]) {
    if (retried) regenServer();
    return Uri.https('$server', '/robustirc/v1$path', params);
  }

  static Future<String> _postToServer(List<RobustIrcServer> servers,
          String path, Object body, String userAgent, [String? sessionAuth]) =>
      _retry((r) => http.post(
              _makeuri(servers[_rand.nextInt(servers.length)], () {}, path, r),
              encoding: utf8,
              body: body,
              headers: _sHeaders(userAgent, sessionAuth)))
          .then((value) => value.body);

  static Future<List<RobustIrcServer>?> _lookupServers(String hostname) async =>
      jsonDecode((await http.get(
                  Uri.https('cloudflare-dns.com', '/dns-query',
                      {'name': '_robustirc._tcp.$hostname', 'type': 'SRV'}),
                  headers: {'accept': 'application/dns-json'}))
              .body)['Answer']
          ?.where((a) => a['type'] == 33 && a['name'].contains('robustirc'))
          .map<RobustIrcServer>((e) => RobustIrcServer.fromDns(e))
          .toList();

  static Future<RobustSession> connect(
    String hostname, {
    bool lookupHostname = true,
    String userAgent = 'robustirc.dart 0.0.1',
    List<RobustIrcServer>? servers,
  }) async {
    servers ??= lookupHostname
        ? await _lookupServers(hostname)
        : [RobustIrcServer(hostname, 60667)];
    if (servers == null) throw 'cant get server list';
    final json =
        jsonDecode(await _postToServer(servers, '/session', '', userAgent));
    return RobustSession(
      hostname,
      servers,
      userAgent,
      json['Sessionid'],
      json['Sessionauth'],
      json['Prefix'],
    );
  }

  Future<int> quit(String msg) => _retry((r) => _client.delete(
        _makeuri(currentServer, _regenServer, '/$sessionId', r),
        headers: _headers,
        encoding: utf8,
        body: jsonEncode({'Quitmessage': msg}),
      )).then((value) => value.statusCode);

  int generateMessageId(String msg) =>
      msg.hashCode << 32 | _rand.nextInt(1 << 32);

  Future<int> postMessage(String msg, [int? id]) {
    id ??= generateMessageId(msg);
    return _retry((r) => _client.post(
          _makeuri(currentServer, _regenServer, '/$sessionId/message', r),
          headers: _headers,
          encoding: utf8,
          body: jsonEncode({'Data': msg, 'ClientMessageId': id}),
        )).then((value) => value.statusCode);
  }

  Future<void> ping() => postMessage('PING');

  void getMessages(Function(String, String) ircHandler,
          {Function()? pingHandler, String? lastseen}) =>
      _retry((r) => _client.send(http.Request(
          'GET',
          _makeuri(currentServer, _regenServer, '/$sessionId/messages', r,
              lastseen != null ? {'lastseen': lastseen} : {}))
        ..headers['X-Session-Auth'] = sessionAuth)).then((res) =>
          res.stream.transform(utf8.decoder).map(jsonDecode).forEach((packet) {
            final type = packet['Type'];
            if (type == 4) {
              servers = packet['Servers']
                  .map((s) => s.split(':'))
                  .map<RobustIrcServer>(
                      (s) => RobustIrcServer(s[0], int.parse(s[1])))
                  .toList();
              if (pingHandler != null) pingHandler();
            } else if (type == 3) {
              final id = '${packet['Id']['Id']}.${packet['Id']['Reply']}';
              final data = packet['Data'];
              ircHandler(id, data);
            } else {
              throw 'Unknown packet type: $type';
            }
          }));
}
