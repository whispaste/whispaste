/**
 * @name Hardcoded secret or service URL in source code
 * @description Detects string literals that match patterns for API keys, webhook URLs,
 *              or other secrets that should be stored in configuration, not source code.
 *              Hardcoded secrets in binaries can be extracted by attackers.
 * @kind problem
 * @problem.severity error
 * @security-severity 9.0
 * @precision medium
 * @id go/whispaste/hardcoded-secret-pattern
 * @tags security
 *       credentials
 *       external/cwe/cwe-798
 */

import go

/**
 * A string literal that matches known secret patterns.
 */
class HardcodedSecret extends StringLit {
  string secretType;

  HardcodedSecret() {
    exists(string val | val = this.getExactValue() |
      // OpenAI API keys
      (val.regexpMatch("sk-[a-zA-Z0-9]{20,}") and secretType = "OpenAI API key")
      or
      // AWS IAM access keys
      (val.regexpMatch("AKIA[0-9A-Z]{16}") and secretType = "AWS access key")
      or
      // GitHub personal access tokens
      (val.regexpMatch("ghp_[a-zA-Z0-9]{36}") and secretType = "GitHub token")
      or
      // GitHub fine-grained tokens
      (val.regexpMatch("github_pat_[a-zA-Z0-9_]{22,}") and secretType = "GitHub fine-grained token")
      or
      // Discord webhook URLs
      (val.regexpMatch("https://discord\\.com/api/webhooks/[0-9]+/[a-zA-Z0-9_-]+") and
        secretType = "Discord webhook URL")
      or
      // Discord bot tokens
      (val.regexpMatch("[A-Za-z0-9_-]{24}\\.[A-Za-z0-9_-]{6}\\.[A-Za-z0-9_-]{27,}") and
        val.indexOf(".") > 0 and
        secretType = "Discord bot token")
      or
      // Supabase service role keys (JWT format starting with eyJ)
      (val.regexpMatch("eyJ[a-zA-Z0-9_-]{50,}\\.[a-zA-Z0-9_-]{50,}\\.[a-zA-Z0-9_-]{50,}") and
        secretType = "JWT/Supabase key")
      or
      // Anthropic API keys
      (val.regexpMatch("sk-ant-[a-zA-Z0-9-]{20,}") and secretType = "Anthropic API key")
      or
      // Groq API keys
      (val.regexpMatch("gsk_[a-zA-Z0-9]{20,}") and secretType = "Groq API key")
      or
      // Deepgram API keys
      (val.regexpMatch("[a-f0-9]{40,}") and
        val.length() >= 40 and
        val.length() <= 64 and
        not val.regexpMatch("[0-9a-f]{64}") and // Exclude SHA-256 hashes (model verification)
        secretType = "potential API key (hex)")
    ) and
    // Exclude test files
    not this.getFile().getBaseName().matches("%_test.go") and
    // Exclude the query's own test expectations
    not this.getFile().getRelativePath().matches("codeql-custom-queries%")
  }

  string getSecretType() { result = secretType }
}

from HardcodedSecret secret
select secret,
  "Hardcoded " + secret.getSecretType() +
    " found. Move to config.json or environment variable. Never embed secrets in the binary."
