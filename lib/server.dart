
library services.server;

import 'dart:async';
import 'dart:convert' show JSON;
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

import 'common.dart';
export 'common.dart';

Logger _logger = new Logger('services');

class Server {
  final int port;

  Server(this.port);

  void start() {
    HttpServer.bind(InternetAddress.ANY_IP_V6, port).then((server) {
      _logger.info('serving on ${port}...');

      server.listen((HttpRequest req) {
        if (req.uri.path == '/ws') {
          // Upgrade a HttpRequest to a WebSocket connection.
          WebSocketTransformer.upgrade(req).then((socket) {
            new ServerClient(socket, this);
          });
        }
      });
    });
  }
}

class ServerClient {
  final WebSocket socket;
  final Server server;

  Map<String, Domain> _domainMap = {};

  ServerClient(this.socket, this.server) {
    new ControlDomain(this);
    new ProcessDomain(this);
    new ProjectsDomain(this);
    new ServicesDomain(this);

    socket.listen(_handleMessage, onDone: _onDone);
  }

  void _register(Domain domain) {
    _domainMap[domain.name] = domain;
  }

  void _onDone() {
    _logger.info('client closing');
  }

  void _handleMessage(String message) {
    if (message.length > 300) {
      _logger.fine('<== ${message.substring(0, 300)}...');
    } else {
      _logger.fine('<== ${message}');
    }

    Map msg = JSON.decode(message);

    String method = msg['method'];
    var params = msg['params'];
    var id = msg['id'];
    int index = method.indexOf('.');
    String domainName = index != -1 ? method.substring(0, index) : null;

    if (domainName == null) {
      _send(_createError(id, 'command not understood: ${method}'));
    } else if (_domainMap.containsKey(domainName)) {
      Domain domain = _domainMap[domainName];
      domain.handleMessage(id, method.substring(index + 1), params);
    } else {
      _send(_createError(id, 'command not understood: ${method}'));
    }
  }

  Map _createResponse(var id, dynamic result) => {'id': id, 'result': result};

  Map _createError(var id, dynamic error) => {'id': id, 'error': error};

  void _send(Map message) {
    String str = JSON.encode(message);
    if (str.length > 300) {
      _logger.fine('==> ${str.substring(0, 300)}...');
    } else {
      _logger.fine('==> ${str}');
    }
    socket.add(str);
  }

  String _cwd() => Directory.current.path;
}

abstract class Domain {
  final ServerClient client;
  final String name;

  Map<String, Function> _methods = {};

  Domain(this.client, this.name) {
    client._register(this);

    register();
  }

  void register();

  void _register(String method, Function function) {
    _methods[method] = function;
  }

  void handleMessage(var id, String method, Map params) {
    if (_methods.containsKey(method)) {
      Future f = _methods[method](params);
      f.then((result) {
        if (result is Serializable) {
          result = result.toJson();
        }
        client._send(client._createResponse(id, result));
      }).catchError((e) {
        client._send(client._createError(id, '${e}'));
      });
    } else {
      client._send(client._createError(id, 'command not understood: ${method}'));
    }
  }
}

class ControlDomain extends Domain {
  ControlDomain(ServerClient client) : super(client, 'control');

  void register() {
    _register('pwd', pwd);
    _register('killServer', killServer);
  }

  Future<String> pwd(Map params) {
    return new Future.value(Directory.current.path);
  }

  Future killServer(Map params) {
    Timer.run(() {
      final reason = 'client requested closure';
      client.socket.close(WebSocketStatus.NORMAL_CLOSURE, reason).then((_) {
        exit(0);
      });
    });

    return new Future.value();
  }
}

class ProcessDomain extends Domain {
  ProcessDomain(ServerClient client) : super(client, 'process');

  void register() {
    _register('execSync', execSync);
  }

  Future<ExecResult> execSync(Map params) {
    String project = params['project'];
    String cmd = params['cmd'];
    List<String> args = params['args'] == null ? [] : params['args'];

    return Process.run(cmd, args, workingDirectory: _projectDir(project).path)
        .then((ProcessResult result) {
      return new ExecResult.fromResult(result);
    });
  }
}

// apt-get, brew, npm, node, analysis_server
List<DiscoveredService> getKnownServices(ServicesDomain services) {
  return [
    new BowerService(services),
    new DartService(services),
    new GitService(services),
    new PubService(services)
  ];
}

class ServicesDomain extends Domain {
  final Map<String, DiscoveredService> _services = {};

  Completer _readyCompleter = new Completer();

  ServicesDomain(ServerClient client) : super(client, 'services');

  void register() {
    _register('list', list);
    _register('hasService', hasService);
    _register('callServiceCommand', callServiceCommand);

    _discoverServices(getKnownServices(this))
        .then((_) => _readyCompleter.complete())
        .catchError((e) => _readyCompleter.completeError(e));
  }

  Future<List<String>> list(Map params) {
    return _whenReady().then((_) => _services.keys.toList()..sort());
  }

  Future<bool> hasService(Map params) {
    String name = params['name'];

    return _whenReady().then((_) => _services.containsKey(name));
  }

  Future<ExecResult> callServiceCommand(Map params) {
    String name = params['name'];
    String project = params['project'];
    String command = params['command'];
    List<String> args = params['args'];

    return _whenReady().then((_) {
      DiscoveredService service = _services[name];
      if (service == null) return new Future.error("no service '${name}'");
      return service.handleCommand(project, command, args);
    });
  }

  Future _whenReady() => _readyCompleter.future;

  Future<Map> _discoverServices(List<DiscoveredService> knownServices) {
    List<DiscoveredService> services = [];

    return Future.forEach(knownServices, (DiscoveredService service) {
      return service.isAvailable().then((val) {
        if (val) services.add(service);
      });
    }).then((_) {
      services.forEach((s) {
        _services[s.name] = s;
        _logger.info('discovered service ${s}');
      });
      return _services;
    });
  }
}

class ProjectsDomain extends Domain {
  ProjectsDomain(ServerClient client) : super(client, 'projects');

  void register() {
    _register('getProjects', getProjects);
    _register('createProject', createProject);
    _register('deleteProject', deleteProject);
  }

  Future<List<String>> getProjects(Map params) {
    return Directory.current.list(followLinks: false)
        .where((entity) => entity is Directory)
        .map((entity) => path.basename(entity.path))
        .toList();
  }

  Future createProject(Map params) {
    String name = params['name'];
    Directory dir = _projectDir(name);
    return dir.create().then((_) => null);
  }

  Future deleteProject(Map params) {
    String name = params['name'];
    Directory dir = _projectDir(name);
    return dir.delete().then((_) => null);
  }
}

Directory _projectDir(String name) =>
    new Directory(path.join(Directory.current.path, name));

abstract class DiscoveredService {
  final ServicesDomain services;
  final String name;

  DiscoveredService(this.services, this.name);

  Future<bool> isAvailable();

  // Subclasses can override.
  Future<ExecResult> handleCommand(String project, String command, List<String> args) {
    args = args == null ? [] : args.toList();
    args.insert(0, command);
    return Process.run(name, args, workingDirectory: _projectDir(project).path)
        .then((ProcessResult result) {
      return new ExecResult.fromResult(result);
    });
  }

  String toString() => name;
}

class GitService extends DiscoveredService {
  GitService(ServicesDomain services) : super(services, 'git');

  Future<bool> isAvailable() => _checkCommandExists('git', '--version');
}

class DartService extends DiscoveredService {
  DartService(ServicesDomain services) : super(services, 'dart');

  Future<bool> isAvailable() => _checkCommandExists('dart', '--version');
}

class PubService extends DiscoveredService {
  PubService(ServicesDomain services) : super(services, 'pub');

  Future<bool> isAvailable() => _checkCommandExists('pub', '--version');
}

class BowerService extends DiscoveredService {
  BowerService(ServicesDomain services) : super(services, 'bower');

  Future<bool> isAvailable() => _checkCommandExists('bower', '--version');
}

Future<bool> _checkCommandExists(String command, [String arg]) {
  List args = arg == null ? [] : [arg];
  return Process.run(command, args).then((ProcessResult result) {
    return result.exitCode == 0;
  }).catchError((e) {
    return false;
  });
}
