
library server;

import 'dart:io';

import 'package:args/args.dart';
import 'package:logging/logging.dart';
import 'package:services/server.dart';

Logger _logger = new Logger('server');

void main(List args) {
  var parser = new ArgParser();

  // TODO: document the '0' port option
  parser.addOption('port', defaultsTo: '47201', help: 'server port');
  parser.addOption('cwd', help: 'current working directory');
  parser.addFlag('verbose', help: 'print verbose logging info');

  ArgResults results = parser.parse(args);

  try {
    Logger.root.onRecord.listen(print);

    if (results['verbose'] == true) {
      Logger.root.level = Level.FINE;
    }

    if (results['cwd'] != null) {
      Directory dir = new Directory(results['cwd']);
      Directory.current = dir;
      _logger.info('changing to directory ${dir}');
    }
    _serveFrom(int.parse(results['port']));
  } catch (e) {
    print("usage: dart server [--port xxx]");
    print(parser.getUsage());
    exit(1);
  }
}

void _serveFrom(int port) {
  new Server(port).start();
}
