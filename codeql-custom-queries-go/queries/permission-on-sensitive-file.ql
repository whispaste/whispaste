/**
 * @name Sensitive file created without restrictive permissions
 * @description Files containing API keys, credentials, or configuration with secrets
 *              must be created with mode 0600 (owner-only read/write). Using more
 *              permissive modes allows other users on the system to read credentials.
 * @kind problem
 * @problem.severity warning
 * @security-severity 6.0
 * @precision medium
 * @id go/whispaste/permission-on-sensitive-file
 * @tags security
 *       file-permissions
 *       external/cwe/cwe-732
 */

import go

/**
 * Detects os.WriteFile or os.OpenFile calls where:
 * 1. The filename suggests sensitive content (config, key, secret, credential)
 * 2. The permission mode is more permissive than 0600
 */
from CallExpr call, Expr permArg, int permValue
where
  (
    // os.WriteFile(name, data, perm)
    call.getTarget().hasQualifiedName("os", "WriteFile") and
    permArg = call.getArgument(2)
    or
    // os.OpenFile(name, flag, perm)
    call.getTarget().hasQualifiedName("os", "OpenFile") and
    permArg = call.getArgument(2)
  ) and
  permValue = permArg.(IntLit).getIntValue() and
  // More permissive than 0600 (owner read+write only)
  permValue > 384 and // 0600 decimal = 384
  // Check if filename references suggest sensitive content
  exists(Expr nameArg |
    nameArg = call.getArgument(0) and
    (
      nameArg.(StringLit).getExactValue().regexpMatch("(?i).*(config|key|secret|credential|token|password|api).*")
      or
      exists(string varName |
        varName = nameArg.(Ident).getName() and
        varName.regexpMatch("(?i).*(config|key|secret|credential).*")
      )
    )
  ) and
  not call.getFile().getBaseName().matches("%_test.go")
select call,
  "Sensitive file written with permission mode " + permArg.toString() +
    " which is more permissive than 0600. Use os.FileMode(0600) for files containing credentials."
