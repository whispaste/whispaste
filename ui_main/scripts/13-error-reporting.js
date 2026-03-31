/* ── Error Reporting Toggle ──────────────────────────────── */
// About page toggle for opt-in anonymous crash reporting.

function initErrorReportingToggle() {
  const toggle = document.getElementById('toggle-error-reporting');
  if (!toggle || !window.getErrorReportingEnabled) return;

  window.getErrorReportingEnabled().then(enabled => {
    toggle.checked = !!enabled;
  });

  toggle.addEventListener('change', () => {
    if (window.setErrorReportingEnabled) {
      window.setErrorReportingEnabled(toggle.checked);
    }
  });
}

document.addEventListener('DOMContentLoaded', () => {
  initErrorReportingToggle();
});
