## 2024-05-18 - Missing semantic label on stateful window controls
**Learning:** Found that custom window controls (like maximize/restore toggles) sometimes miss semantic labels entirely, preventing screen reader users from understanding what the control does, especially when its icon and action change dynamically based on state.
**Action:** Always wrap stateful icon-only window controls in `Semantics` and provide dynamic labels that reflect the current state (e.g., 'Restore window' vs 'Maximize window').
