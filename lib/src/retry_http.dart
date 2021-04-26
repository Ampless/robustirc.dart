import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'server.dart';

Future<http.StreamedResponse> retryHttp(
    {required String method,
    required RobustIrcServer server,
    required String path,
    String body = '',
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
    required http.Client client,
    required RobustIrcServer Function() newServer,
    int delay = 1}) async {
  final req = http.Request(
      method, Uri.https('$server', '/robustirc/v1$path', queryParameters));
  req.encoding = utf8;
  req.body = body;
  headers.forEach((key, value) => req.headers[key] = value);
  try {
    return await client.send(req);
  } on Exception {
    server = newServer();
    return Future.delayed(
        Duration(seconds: 1),
        () => retryHttp(
              method: method,
              server: server,
              path: path,
              body: body,
              queryParameters: queryParameters,
              headers: headers,
              client: client,
              newServer: newServer,
              delay: min(delay * 2, 64),
            ));
  }
}
