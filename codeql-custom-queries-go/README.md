# WhisPaste — Custom CodeQL Queries (Go)

Project-specific CodeQL queries for security and quality analysis of the WhisPaste Go codebase.

## Queries

| Query | Severity | CWE | Description |
|-------|----------|-----|-------------|
| **credential-in-log** | Error | CWE-532 | Detects API keys/tokens passed to `logDebug/logInfo/logWarn/logError`. These project log functions write to disk; `logWarn`/`logError` additionally trigger crash reports. |
| **hardcoded-secret-pattern** | Error | CWE-798 | Finds string literals matching known secret patterns (OpenAI, GitHub, Discord, AWS, Anthropic, Groq, Supabase JWT). |
| **unencrypted-external-url** | Warning | CWE-319 | Flags `http://` URLs to external services. Localhost/loopback is exempt (local AI servers). |
| **subprocess-path-injection** | Error | CWE-78 | Taint-tracks config values flowing into `exec.Command` — prevents command injection via manipulated binary paths. |
| **permission-on-sensitive-file** | Warning | CWE-732 | Flags `os.WriteFile`/`os.OpenFile` on credential files with permissions more permissive than `0600`. |
| **crash-report-trigger-audit** | Recommendation | — | Lists all `logWarn`/`logError` call sites for periodic audit of unintentional crash report triggers. |

## How It Works

These queries run automatically via GitHub Actions (`.github/workflows/codeql.yml`) on every push to `main` and on pull requests. The CodeQL config (`.github/codeql/codeql-config.yml`) extends the default `security-and-quality` suite with this custom query pack.

## Adding New Queries

1. Create a `.ql` file in `queries/`
2. Include required metadata: `@name`, `@kind`, `@problem.severity`, `@id`
3. Use the `go/whispaste/` ID namespace
4. Push to `main` — CodeQL picks up new queries automatically

## Dependencies

- `codeql/go-all ^1.1.0` — CodeQL Go standard library
- Runs on `windows-latest` (CGO required for audio capture build)
