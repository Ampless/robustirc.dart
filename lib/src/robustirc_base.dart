import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dns_client/dns_client.dart';
import 'package:http/http.dart' as http;

final _rand = Random();

class RobustIrcServer {
  final InternetAddress addr;
  final int port;

  RobustIrcServer(this.addr, this.port);
}

class RobustIrc {
  final String hostname;
  List<InternetAddress> servers;
  final String userAgent;
  final String sessionId, sessionAuth;

  RobustIrc(
    this.hostname,
    this.servers,
    this.userAgent,
    this.sessionId,
    this.sessionAuth,
  );

  static RobustIrcServer _pickServer(List<RobustIrcServer> servers) =>
      servers[_rand.nextInt(servers.length)];

  static Future<HttpClientRequest> _connectToServer(
      List<RobustIrcServer> servers, String path) async {
    final http = HttpClient();
    final server = _pickServer(servers);
    return http.open('POST', host, port, path);
  }

  static Future<DnsRecord> _lookupServers(String hostname,
      {InternetAddressType type = InternetAddressType.any}) async {
    final query = {'name': hostname, 'type': 'SRV'};
    final response = await http.get(
        Uri.https('https://cloudflare-dns.com/dns-query', _uri.path, query),
        headers: {'accept': 'application/dns-json'});
    final record = DnsRecord.fromJson(jsonDecode(response.body));
    return record;
  }

  static Future<RobustIrc> connect(
    String hostname, {
    bool lookupHostname = true,
    String userAgent = 'robustirc.dart 0.0.1',
    List<RobustIrcServer>? servers,
  }) async {
    //TODO: the standard forbids this, use SRV record
    servers ??= lookupHostname
        ? (await DnsOverHttps.cloudflare().lookup(hostname))
            .map((e) => RobustIrcServer(e, 443))
            .toList()
        : [RobustIrcServer(InternetAddress(hostname), 443)];
    return RobustIrc(hostname, servers, userAgent);
  }
}
