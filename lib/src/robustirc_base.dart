import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dns_client/dns_client.dart';
import 'package:http/http.dart' as http;

final _rand = Random();

//TODO: comply with section 4 of the spec

class RobustIrcServer {
  final String host;
  final int port;

  RobustIrcServer(this.host, this.port);

  static RobustIrcServer fromDns(Answer answer) =>
      fromDnsData(answer.data.split(' '));
  static RobustIrcServer fromDnsData(List<String> data) =>
      RobustIrcServer(data[3], int.parse(data[2]));

  @override
  String toString() => '$host:$port';
}

class RobustIrc {
  final String hostname;
  final String prefix;
  List<RobustIrcServer> servers;
  final String sessionId, sessionAuth;
  final String userAgent;

  RobustIrc(
    this.hostname,
    this.servers,
    this.userAgent,
    this.sessionId,
    this.sessionAuth,
    this.prefix,
  );

  static Future<T> _retry<T>(Future<T> Function() f) {
    try {
      return f();
    } on Exception {
      return _retry(f);
    }
  }

  static Map<String, String>? _headers(String ua, String? sa) {
    final h = {'User-Agent': ua};
    if (sa != null) h['X-Session-Auth'] = sa;
    return h;
  }

  static Uri _makeuri(List<RobustIrcServer> servers, String path) {
    final server = servers[_rand.nextInt(servers.length)];
    return Uri.https('$server', '/robustirc/v1$path');
  }

  static Future<String> _postToServer(List<RobustIrcServer> servers,
          String path, Object body, String userAgent, [String? sessionAuth]) =>
      _retry(() => http
          .post(_makeuri(servers, path),
              encoding: utf8,
              body: body,
              headers: _headers(userAgent, sessionAuth))
          .then((value) => value.body));

  static Future<List<RobustIrcServer>?> _lookupServers(String hostname) async =>
      DnsRecord.fromJson(jsonDecode((await http.get(
                  Uri.https('cloudflare-dns.com', '/dns-query',
                      {'name': '_robustirc._tcp.$hostname', 'type': 'SRV'}),
                  headers: {'accept': 'application/dns-json'}))
              .body))
          .answer
          ?.where((a) => a.type == 33 && a.name.contains('robustirc'))
          .map((e) => RobustIrcServer.fromDns(e))
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
}
