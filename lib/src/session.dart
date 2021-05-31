import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'retry_http.dart';
import 'server.dart';

final _rand = Random();
T _randElement<T>(List<T> l) => l[_rand.nextInt(l.length)];

Future<List<RobustIrcServer>?> lookupRobustIrcServers(String hostname,
    {String dnsServer = 'https://cloudflare-dns.com/dns-query'}) async {
  final uri = Uri.parse(dnsServer);
  uri.queryParameters['name'] = '_robustirc._tcp.$hostname';
  uri.queryParameters['type'] = 'SRV';
  return jsonDecode(
          (await http.get(uri, headers: {'accept': 'application/dns-json'}))
              .body)['Answer']
      ?.where((a) => a['type'] == 33 && a['name'].contains('robustirc'))
      .map<RobustIrcServer>((e) => RobustIrcServer.fromDns(e))
      .toList();
}

class RobustSession {
  final String hostname;
  final String prefix;
  RobustIrcServer currentServer;
  List<RobustIrcServer> servers;
  final String sessionId, sessionAuth;
  final String userAgent;
  final http.Client _client;

  RobustSession(
    this.hostname,
    this.servers,
    this.userAgent,
    this.sessionId,
    this.sessionAuth,
    this.prefix,
    this.currentServer,
    this._client,
  );

  RobustIrcServer _regenServer() =>
      currentServer = servers[_rand.nextInt(servers.length)];

  static Map<String, String> _sHeaders(String ua, [String? sa]) {
    final h = {'User-Agent': ua};
    if (sa != null) h['X-Session-Auth'] = sa;
    return h;
  }

  Map<String, String> get _headers => _sHeaders(userAgent, sessionAuth);

  static Future<RobustSession> connect(
    String hostname, {
    bool lookupHostname = true,
    String userAgent = 'robustirc.dart 0.1.0',
    List<RobustIrcServer>? servers,
  }) async {
    servers ??= lookupHostname
        ? await lookupRobustIrcServers(hostname)
        : [RobustIrcServer(hostname, 60667)];
    if (servers == null) throw 'cant get server list';
    var currentServer = _randElement(servers);
    final client = http.Client();
    final json = jsonDecode(await (await retryHttp(
      server: currentServer,
      path: '/session',
      client: client,
      method: 'POST',
      newServer: () => currentServer = _randElement(servers!),
      headers: _sHeaders(userAgent),
      rand: _rand,
    ))
        .stream
        .bytesToString());
    return RobustSession(
      hostname,
      servers,
      userAgent,
      json['Sessionid'],
      json['Sessionauth'],
      json['Prefix'],
      currentServer,
      client,
    );
  }

  Future<int> quit(String msg) => retryHttp(
        method: 'DELETE',
        path: '/$sessionId',
        server: currentServer,
        headers: _headers,
        body: jsonEncode({'Quitmessage': msg}),
        client: _client,
        newServer: _regenServer,
        rand: _rand,
      ).then((value) => value.statusCode);

  int generateMessageId(String msg) =>
      msg.hashCode << 32 | _rand.nextInt(1 << 32);

  Future<int> postMessage(String msg, [int? id]) {
    id ??= generateMessageId(msg);
    return retryHttp(
      method: 'POST',
      path: '/$sessionId/message',
      server: currentServer,
      headers: _headers,
      body: jsonEncode({'Data': msg, 'ClientMessageId': id}),
      client: _client,
      newServer: _regenServer,
      rand: _rand,
    ).then((value) => value.statusCode);
  }

  void getMessages(Function(String, String) ircHandler,
          {Function()? pingHandler, String? lastseen}) =>
      retryHttp(
        method: 'GET',
        path: '/$sessionId/messages',
        server: currentServer,
        headers: _headers,
        client: _client,
        newServer: _regenServer,
        queryParameters: lastseen != null ? {'lastseen': lastseen} : {},
        rand: _rand,
      ).then((res) =>
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
              final jid = packet['Id'];
              final id = '${jid['Id']}.${jid['Reply']}';
              final data = packet['Data'];
              ircHandler(id, data);
            } else {
              throw 'Unknown packet type: $type';
            }
          }));
}
