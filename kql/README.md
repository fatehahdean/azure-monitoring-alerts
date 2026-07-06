# KQL Query Library

Investigation queries paired with the alert rules in `bicep/main.bicep`.
The alerts detect; these queries diagnose.

| Query | Pairs with alert | Question it answers |
|---|---|---|
| `vm-cpu-trend.kql` | alert-vm-cpu-high | Is CPU load sustained or a spike? |
| `vm-heartbeat-status.kql` | alert-vm-heartbeat-lost | Which machines went silent, and when? |
| `failed-operations.kql` | alert-activity-failures | What failed, who ran it, how often? |

Run any query in the Log Analytics workspace: **Logs** blade → paste → Run.
