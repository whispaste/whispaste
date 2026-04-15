# WhisPaste Security

## Zero-Trust Principle (MANDATORY)
- Open-source client is ALWAYS potentially inspectable/replayed/modified
- NEVER trust client code for: premium gating, share permissions, quota enforcement, data isolation
- Server-side enforcement ONLY: Supabase auth, RLS, edge functions, rate limits

## Supabase Edge Functions
Two functions exist: `analytics` (admin-only) and `testimonials` (public read + admin moderation).

### Security Conventions for Every Edge Function
| Pattern | Rule |
|---------|------|
| Admin auth | `x-api-key` header ONLY — never query params (logged) |
| Rate limiting | Per-device AND per-IP as separate queries (both must pass) |
| X-Forwarded-For | Use LAST entry: `split(",").pop().trim()` |
| Uniform responses | Consistent JSON — no internal state leaks |
| CORS | Public: `Access-Control-Allow-Origin: *` / Admin: no CORS header |
| Security headers | `X-Content-Type-Options: nosniff`, `Cache-Control: no-store` |
| Input validation | Length-capped, allowlists, hex hash validation |
| DB layer | RLS: `USING(false)` deny-all + `REVOKE ALL` + service_role bypass |

## Secrets
- NEVER commit: API keys, credentials, tokens, service-role keys
- Upstream provider keys: server-side only
- Client DSN (Sentry) is OK to hardcode (public DSN)
- `FlutterSecureStorage` for sensitive user config

## Data Privacy
- GDPR consent gate: nothing sent without `_consentGranted`
- Device ID: MD5 hash of hostname (not hardware identifier)
- PII sanitization: `CrashReporter.beforeSend` scrubs keys, tokens, passwords, paths

## Hardening
Apply same zero-trust standards to existing surfaces (feedback, analytics, testimonials) AND future premium paths.
