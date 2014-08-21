
library services.client;

import 'dart:async';
import 'dart:convert' show JSON;
import 'dart:io';

import 'package:logging/logging.dart';

import 'common.dart';
export 'common.dart';

Logger _logger = new Logger('services.client');

class Client {
  final WebSocket _socket;
  final Map<int, Completer> _completers = {};

  ControlDomain _controlDomain;
  ProcessDomain _processDomain;
  ProjectsDomain _projectsDomain;
  ServicesDomain _servicesDomain;

  int _id = 0;

  Client(this._socket) {
    _controlDomain = new ControlDomain(this);
    _processDomain = new ProcessDomain(this);
    _projectsDomain = new ProjectsDomain(this);
    _servicesDomain = new ServicesDomain(this);
  }

  ControlDomain get controlDomain => _controlDomain;
  ProcessDomain get processDomain => _processDomain;
  ProjectsDomain get projectsDomain => _projectsDomain;
  ServicesDomain get servicesDomain => _servicesDomain;

  void start() {
    _socket.listen(_handleMessage);
  }

  Future<dynamic> _sendCommand(String command, {Map params}) {
    var id = (_id++).toString();
    Completer completer = new Completer();

    Map cmd = {'method' : command, 'id' : id.toString()};

    if (params != null && params.isNotEmpty) {
      cmd['params'] = params;
    }

    _completers[id] = completer;
    _socket.add(JSON.encode(cmd));
    return completer.future;
  }

  void _handleMessage(String str) {
    Map msg = JSON.decode(str);

    if (msg['id'] != null) {
      Completer completer = _completers.remove(msg['id']);
      if (msg['error'] != null) {
        completer.completeError(msg['error']);
      } else {
        completer.complete(msg['result']);
      }
    } else {
      _logger.severe('unknown: ${msg}');
    }
  }
}

abstract class Domain {
  final Client _client;
  final String name;

  Domain(this._client, this.name);

  Future<dynamic> _sendCommand(String command, {Map params}) {
    return _client._sendCommand('${name}.${command}', params: params);
  }
}

class ProjectsDomain extends Domain {
  ProjectsDomain(Client client) : super(client, 'projects');

  Future<List<String>> getProjects() => _sendCommand('getProjects');

  Future<List<String>> createProject(String name) =>
      _sendCommand('createProject', params: {'name': name});

  Future<List<String>> deleteProject(String name) =>
      _sendCommand('deleteProject', params: {'name': name});
}

class ControlDomain extends Domain {
  ControlDomain(Client client) : super(client, 'control');

  Future<String> pwd() => _sendCommand('pwd');

  Future<String> killServer() => _sendCommand('killServer');
}

class ProcessDomain extends Domain {
  ProcessDomain(Client client) : super(client, 'process');

  Future<ExecResult> execSync(String project, String cmd, [List<String> args]) {
    Map params = {'project': project, 'cmd': cmd};
    if (args != null) params['args'] = args;

    return _sendCommand('execSync', params: params).then((Map m) {
      return new ExecResult.fromMap(m);
    });
  }
}

class ServicesDomain extends Domain {
  ServicesDomain(Client client) : super(client, 'services');

  Future<List<String>> list() => _sendCommand('list');

  // TODO: cache the service, onr a project/name basis?
  ProjectService getService(String serviceName, String projectName) {
    return new ProjectService(this, serviceName, projectName);
  }
}

class ProjectService {
  final ServicesDomain services;
  final String name;
  final String project;

  ProjectService(this.services, this.name, this.project);

  Future<ExecResult> callServiceCommand(String command, [List<String> args]) {
    Map params = {'name': name, 'project': project, 'command': command};
    if (args != null) params['args'] = args;
    return services._sendCommand('callServiceCommand', params: params).then((Map m) {
      return new ExecResult.fromMap(m);
    });
  }
}
