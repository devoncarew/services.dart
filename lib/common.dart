
library services.common;

import 'dart:convert' show JSON;
import 'dart:io';

class ExecResult extends Serializable {
  int exitCode;
  String stdout;
  String stderr;

  ExecResult.fromMap(Map m) {
    fromJson(m);
  }

  ExecResult.fromResult(ProcessResult result) {
    this.exitCode = result.exitCode;
    this.stdout = result.stdout;
    this.stderr = result.stderr;
  }

  void fromJson(Map map) {
    exitCode = map['exitCode'];
    stdout = map['stdout'];
    stderr = map['stderr'];
  }

  Map toJson() => {'exitCode': exitCode, 'stdout': stdout, 'stderr': stderr};

  String toString() {
    StringBuffer buf = new StringBuffer();
    if (stdout != null && stdout.isNotEmpty) buf.write(stdout.trim() + '\n');
    if (stderr != null && stderr.isNotEmpty) buf.write(stderr.trim() + '\n');
    if (exitCode != 0) buf.write('[exitCode=${exitCode}]');
    return buf.toString().trim();
  }
}

abstract class Serializable {
  void fromJson(Map map);
  Map toJson();

  String toString() => JSON.encode(toJson());
}
