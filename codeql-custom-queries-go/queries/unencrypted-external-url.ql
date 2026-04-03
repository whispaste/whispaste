/**
 * @name Unencrypted HTTP URL for external service
 * @description HTTP URLs to external services transmit data in plaintext, allowing
 *              interception of API keys, audio data, or transcription results.
 *              Use HTTPS for all external communication. HTTP is only acceptable
 *              for localhost/loopback connections (127.0.0.1, [::1]).
 * @kind problem
 * @problem.severity warning
 * @security-severity 5.0
 * @precision high
 * @id go/whispaste/unencrypted-external-url
 * @tags security
 *       tls
 *       external/cwe/cwe-319
 */

import go

from StringLit urlLit
where
  urlLit.getExactValue().regexpMatch("http://[^/].*") and
  // Allow localhost/loopback — local AI servers bind to 127.0.0.1
  not urlLit.getExactValue().regexpMatch("http://(localhost|127\\.0\\.0\\.1|\\[::1\\]).*") and
  // Exclude test files
  not urlLit.getFile().getBaseName().matches("%_test.go") and
  // Exclude documentation strings (comments are not StringLit anyway)
  not urlLit.getExactValue().regexpMatch("http://www\\.w3\\.org/.*") and
  not urlLit.getExactValue().regexpMatch("http://schemas\\..*") and
  // Exclude example/placeholder URLs
  not urlLit.getExactValue().regexpMatch("http://example\\.com.*")
select urlLit,
  "External URL uses unencrypted HTTP: '" + urlLit.getExactValue() +
    "'. Use HTTPS to protect data in transit."
