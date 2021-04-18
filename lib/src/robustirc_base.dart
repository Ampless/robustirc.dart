import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dns_client/dns_client.dart';
import 'package:http/http.dart' as http;

final _rand = Random();

class RobustIrcServer {
  final String hostname;
  final int port;

  RobustIrcServer(this.hostname, this.port);

  static RobustIrcServer fromDns(Answer answer) =>
      fromDnsData(answer.data.split(' '));
  static RobustIrcServer fromDnsData(List<String> data) =>
      RobustIrcServer(data[3], int.parse(data[2]));
}

class RobustIrc {
  final String hostname;
  final String prefix;
  List<InternetAddress> servers;
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

  static RobustIrcServer _pickServer(List<RobustIrcServer> servers) =>
      servers[_rand.nextInt(servers.length)];

  static Future<HttpClientRequest> _connectToServer(
      List<RobustIrcServer> servers, String path) async {
    final http = HttpClient();
    final server = _pickServer(servers);
    return http.open('POST', host, port, path);
  }

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
    return RobustIrc(hostname, servers, userAgent);
  }
}
