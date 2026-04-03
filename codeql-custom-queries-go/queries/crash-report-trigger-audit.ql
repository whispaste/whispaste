/**
 * @name Audit: logWarn/logError triggers crash report
 * @description In WhisPaste, logWarn() and logError() automatically trigger crash
 *              reports via crashReporter.captureError(). This query identifies all
 *              call sites so developers can audit whether each warning/error truly
 *              warrants a crash report, or should be downgraded to logInfo/logDebug.
 * @kind problem
 * @problem.severity recommendation
 * @precision high
 * @id go/whispaste/crash-report-trigger-audit
 * @tags maintainability
 *       audit
 *       crash-reporting
 */

import go

from CallExpr call, string funcName
where
  funcName = ["logWarn", "logError"] and
  call.getTarget().getName() = funcName and
  not call.getFile().getBaseName().matches("%_test.go")
select call,
  funcName + "() at this location triggers an automatic crash report. " +
    "Verify this is intentional. Downgrade to logInfo() if the condition " +
    "is expected/recoverable and should not generate crash telemetry."
