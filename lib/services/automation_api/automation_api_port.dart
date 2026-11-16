/// Port constants of the local automation API (ticket / 8.1).
///
/// Kept free of Flutter imports so the CLI and the MCP server can read the
/// default without loading the app.
library;

/// Default port the automation API targets when the user hasn't set
/// `AutomationApiSettings.customPort` — high enough to avoid the most
/// common local dev-server collisions (3000/5173/8080/…).
///
/// This is only the *first* port tried: if binding to the target port
/// (`customPort ?? kAutomationApiDefaultPort`) fails — most commonly
/// `EADDRINUSE` — the controller automatically tries the next
/// `kAutomationApiPortFallbackAttempts` consecutive ports before giving up.
const kAutomationApiDefaultPort = 8765;
