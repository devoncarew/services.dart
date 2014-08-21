
library test_client;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

import 'package:services/client.dart';

void main(List args) {
  var parser = new ArgParser();

  parser.addOption('port',
      defaultsTo: '47201',
      help: 'services server port');

  ArgResults results = parser.parse(args);

  String portStr = results['port'];

  try {
    _connectTo(int.parse(portStr));
  } catch (e) {
    print("usage: dart client [--port xxx]");
    print(parser.getUsage());
    exit(1);
  }
}

void _connectTo(int port) {
  final url = 'ws://localhost:${port}/ws';

  print('connecting to ${url}...');

  WebSocket.connect(url).then((socket) {
    print('connected to ${url}');

    new ExampleClient(new Client(socket));
  }).catchError((e) {
    print('Error connecting to ${url}: ${e}');
    exit(1);
  });
}

class ExampleClient {
  final Client client;

  Map<String, Function> _commands = {};

  String project;

  ExampleClient(this.client) {
    _commands['exit'] = _exit;
    _commands['ls'] = _ls;
    _commands['pwd'] = _pwd;
    _commands['projects'] = _projects;
    _commands['project'] = _project;
    _commands['services'] = _services;
    _commands['service'] = _service;

    client.start();

    print('commands: ${_commands.keys.toList()..sort()}');

    Stream cmdLineStream = stdin
        .transform(UTF8.decoder)
        .transform(new LineSplitter());

    stdout.write('] ');

    cmdLineStream.listen(handleInput);

//    ProjectService gitService = client.servicesDomain.getService('git', 'ace.dart');
//    gitService.callServiceCommand('status').then(print);

    // TODO: call control.killServer

  }

  void handleInput(String line) {
    String command = line;
    List<String> args = [];
    if (line.indexOf(' ') != -1) {
      command = line.substring(0, line.indexOf(' '));
      args = line.substring(line.indexOf(' ') + 1).split(' ');
    }

    if (_commands.containsKey(command)) {
      Function fn = _commands[command];
      var r = fn(args);
      if (r is Future) {
        r.then((_) {
          stdout.write('] ');
        }).catchError((e) {
          print(e);
          stdout.write('] ');
        });
      } else {
        stdout.write('] ');
      }
    } else {
      print('command not understood: ${command}');
      stdout.write('] ');
    }
  }

  Future _pwd(List args) {
    return client.controlDomain.pwd().then(print);
  }

  Future _ls(List args) {
    return client.processDomain.execSync(project, 'ls').then(print);
  }

  Future _exit(List args) {
    return client.controlDomain.killServer().then((_) => exit(0));
  }

  Future _projects(List args) {
    return client.projectsDomain.getProjects().then((projects) {
      projects.forEach(print);
    });
  }

  void _project(List args) {
    project = args.first;
    print('switched to ${project}');
  }

  Future _services(List args) {
    return client.servicesDomain.list().then((services) {
      services.forEach(print);
    });
  }

  Future _service(List args) {
    if (project == null) {
      return new Future.error('no project set');
    }

    String name = args.first;
    args = args.skip(1).toList();

    ProjectService service = client.servicesDomain.getService(name, project);

    String command = args.first;
    args = args.skip(1).toList();

    return service.callServiceCommand(command, args).then((ExecResult result) {
      print(result);
    });
  }
}
