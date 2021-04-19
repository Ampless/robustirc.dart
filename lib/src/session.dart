import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'server.dart';

final _rand = Random();

//TODO: use the leader when pinged (and fix thundering herd)

class RobustIrc {
  final String hostname;
  final String prefix;
  List<RobustIrcServer> servers;
  final String sessionId, sessionAuth;
  final String userAgent;
  final http.Client _client = http.Client();

  RobustIrc(
    this.hostname,
    this.servers,
    this.userAgent,
    this.sessionId,
    this.sessionAuth,
    this.prefix,
  );

  static Future<T> _retry<T>(Future<T> Function() f, [int dly = 1]) {
    dly &= 0xff; //delay for at most 128 seconds
    try {
      return f();
    } on Exception {
      return Future.delayed(Duration(seconds: dly), () => _retry(f, dly * 2));
    }
  }

  static Map<String, String> _sHeaders(String ua, String? sa) {
    final h = {'User-Agent': ua};
    if (sa != null) h['X-Session-Auth'] = sa;
    return h;
  }

  Map<String, String> get _headers => _sHeaders(userAgent, sessionAuth);

  static Uri _makeuri(List<RobustIrcServer> servers, String path,
      [Map<String, dynamic> params = const {}]) {
    final server = servers[_rand.nextInt(servers.length)];
    return Uri.https('$server', '/robustirc/v1$path', params);
  }

  static Future<String> _postToServer(List<RobustIrcServer> servers,
          String path, Object body, String userAgent, [String? sessionAuth]) =>
      _retry(() => http.post(_makeuri(servers, path),
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

  static Future<RobustIrc> connect(
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
    return RobustIrc(
      hostname,
      servers,
      userAgent,
      json['Sessionid'],
      json['Sessionauth'],
      json['Prefix'],
    );
  }

  Future<int> close(String msg) => _retry(() => _client.delete(
        _makeuri(servers, '/$sessionId'),
        headers: _headers,
        encoding: utf8,
        body: jsonEncode({'Quitmessage': msg}),
      )).then((value) => value.statusCode);

  int generateMessageId(String msg) =>
      msg.hashCode << 32 | _rand.nextInt(1 << 32);

  Future<int> postMessage(String msg, [int? id]) {
    id ??= generateMessageId(msg);
    return _retry(() => _client.post(
          _makeuri(servers, '/$sessionId/message'),
          headers: _headers,
          encoding: utf8,
          body: jsonEncode({'Data': msg, 'ClientMessageId': id}),
        )).then((value) => value.statusCode);
  }

  Future<void> ping() => postMessage('PING');

  Future<http.StreamedResponse> getMessages([String? lastseen]) =>
      _retry(() => _client.send(http.Request(
          'GET',
          _makeuri(servers, '/$sessionId/messages',
              lastseen != null ? {'lastseen': lastseen} : {}))
        ..headers['X-Session-Auth'] = sessionAuth));
}
