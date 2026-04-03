/**
 * @name Untrusted data in subprocess command path
 * @description WhisPaste spawns whisper-server and llama-server as subprocesses.
 *              If the executable path or arguments are constructed from user-controllable
 *              input (config values, file paths from UI) without validation, an attacker
 *              could achieve arbitrary command execution.
 * @kind path-problem
 * @problem.severity error
 * @security-severity 9.8
 * @precision medium
 * @id go/whispaste/subprocess-path-injection
 * @tags security
 *       command-injection
 *       external/cwe/cwe-78
 */

import go
import semmle.go.dataflow.TaintTracking

/**
 * A source of user-controllable data — config getters that return paths or
 * strings that could be manipulated.
 */
class ConfigPathSource extends DataFlow::Node {
  ConfigPathSource() {
    exists(CallExpr call, string name |
      call.getTarget().getName() = name and
      name.regexpMatch("(?i)get.*(path|dir|binary|command|exec|url|endpoint).*") and
      this.asExpr() = call
    )
  }
}

/**
 * A sink where data flows into a subprocess command.
 */
class ExecCommandSink extends DataFlow::Node {
  ExecCommandSink() {
    exists(CallExpr call |
      (
        call.getTarget().hasQualifiedName("os/exec", "Command") or
        call.getTarget().hasQualifiedName("os/exec", "CommandContext") or
        call.getTarget().hasQualifiedName("syscall", "Exec")
      ) and
      this.asExpr() = call.getArgument(0)
    )
  }
}

module SubprocessPathConfig implements DataFlow::ConfigSig {
  predicate isSource(DataFlow::Node node) { node instanceof ConfigPathSource }

  predicate isSink(DataFlow::Node node) { node instanceof ExecCommandSink }
}

module SubprocessPathFlow = TaintTracking::Global<SubprocessPathConfig>;

import SubprocessPathFlow::PathGraph

from SubprocessPathFlow::PathNode source, SubprocessPathFlow::PathNode sink
where SubprocessPathFlow::flowPath(source, sink)
select sink.getNode(), source, sink,
  "Subprocess command path comes from $@ which may contain user-controlled data. " +
    "Validate the path points to an expected binary before execution.",
  source.getNode(), "this config value"
