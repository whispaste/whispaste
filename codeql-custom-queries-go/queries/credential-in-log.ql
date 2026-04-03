/**
 * @name Potential credential value passed to log function
 * @description Passing API keys, tokens, or passwords directly to log functions
 *              risks exposing secrets in log files or crash reports. Log presence
 *              checks (e.g., key != "") instead of actual values.
 * @kind problem
 * @problem.severity error
 * @security-severity 8.0
 * @precision high
 * @id go/whispaste/credential-in-log
 * @tags security
 *       credentials
 *       external/cwe/cwe-532
 */

import go

/**
 * Matches the project-specific log functions that write to the app log file.
 * logWarn and logError additionally trigger crash reports, making credential
 * exposure even more dangerous.
 */
class ProjectLogCall extends CallExpr {
  ProjectLogCall() {
    exists(string name |
      name = ["logDebug", "logInfo", "logWarn", "logError"] and
      this.getTarget().getName() = name and
      this.getTarget().getPackage().getPath() = this.getEnclosingFunction().getPackage().getPath()
    )
  }

  string getLogFuncName() { result = this.getTarget().getName() }
}

/**
 * An expression that references a variable or field with a credential-like name.
 */
class CredentialRef extends Expr {
  string credName;

  CredentialRef() {
    (
      credName = this.(Ident).getName()
      or
      credName = this.(SelectorExpr).getSelector().getName()
    ) and
    credName.regexpMatch("(?i).*(api[_]?key|token|secret|password|credential|webhook[_]?url|auth[_]?key|private[_]?key).*") and
    not credName.regexpMatch("(?i).*(has[_]?key|key[_]?present|key[_]?exists|key[_]?count|keyboard|token[_]?count|key[_]?name|key[_]?type).*")
  }

  string getCredentialName() { result = credName }
}

from ProjectLogCall logCall, CredentialRef credRef
where credRef = logCall.getAnArgument()
select logCall,
  "Credential '" + credRef.getCredentialName() + "' passed to " +
    logCall.getLogFuncName() +
    "(). Log presence (key != \"\") instead of actual value. logWarn/logError also trigger crash reports."
