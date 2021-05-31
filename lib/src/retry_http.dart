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
    int delay = 1,
    int sameServerRetries = 0,
    required Random rand}) async {
  final req = http.Request(
      method, Uri.https('$server', '/robustirc/v1$path', queryParameters));
  req.encoding = utf8;
  req.body = body;
  headers.forEach((key, value) => req.headers[key] = value);
  try {
    return await client.send(req);
  } on http.ClientException {
    return sameServerRetries > 5
        ? Future.delayed(
            Duration(milliseconds: rand.nextInt(420) + 250),
            () => retryHttp(
                  method: method,
                  server: newServer(),
                  path: path,
                  body: body,
                  queryParameters: queryParameters,
                  headers: headers,
                  client: client,
                  newServer: newServer,
                  rand: rand,
                ))
        : Future.delayed(
            Duration(seconds: delay),
            () => retryHttp(
                  method: method,
                  server: server,
                  path: path,
                  body: body,
                  queryParameters: queryParameters,
                  headers: headers,
                  client: client,
                  newServer: newServer,
                  delay: delay * 2,
                  sameServerRetries: sameServerRetries + 1,
                  rand: rand,
                ));
  }
}
