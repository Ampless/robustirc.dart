class RobustIrcServer {
  final String host;
  final int port;

  RobustIrcServer(this.host, this.port);

  static RobustIrcServer fromDns(Map answer) =>
      fromDnsData(answer['data'].split(' '));
  static RobustIrcServer fromDnsData(List data) =>
      RobustIrcServer(data[3], int.parse(data[2]));

  @override
  String toString() => '$host:$port';
}
