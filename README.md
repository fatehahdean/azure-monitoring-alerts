# Azure Monitoring & Alerting Pipeline

Infrastructure-as-code monitoring stack for Azure: a Log Analytics workspace, an email action group, and three production-style alert rules, all deployed from a single Bicep template with CI validation.

## The business problem

Cloud infrastructure fails silently. A VM can max out its CPU, an agent can stop reporting, or a deployment can fail repeatedly — and nobody knows until users complain. This project demonstrates the monitoring layer every production environment needs: centralised logs, automated detection, and alerting that reaches a human.

## What gets deployed

| Resource | Purpose |
|---|---|
| Log Analytics workspace | Central log store (30-day retention, free-tier friendly) |
| Action group | Email notification channel for all alerts |
| `alert-vm-cpu-high` | Metric alert: VM CPU > 80% for 5 minutes (Severity 2) |
| `alert-vm-heartbeat-lost` | Log alert: a reporting VM goes silent for 10 minutes (Severity 1) |
| `alert-activity-failures` | Log alert: 5+ failed admin operations in 15 minutes (Severity 3) |

## Repository structure

```
bicep/       Bicep IaC templates
kql/         Reusable KQL query library
scripts/     Python health-report tool (Azure SDK)
.github/     CI pipeline (Bicep validation on every push)
```

## Deploy

```bash
az group create --name rg-monitoring --location southeastasia

az deployment group create \
  --resource-group rg-monitoring \
  --template-file bicep/main.bicep \
  --parameters alertEmail=you@example.com
```

To monitor a VM's CPU, pass its resource ID:

```bash
  --parameters alertEmail=you@example.com vmResourceId=/subscriptions/.../virtualMachines/vm-demo
```

To feed the activity-failure alert, export the subscription Activity Log to the workspace:

```bash
az monitor diagnostic-settings subscription create \
  --name activity-to-law \
  --location southeastasia \
  --workspace <workspace-resource-id> \
  --logs '[{"category":"Administrative","enabled":true}]'
```

## Design decisions

- **Metric alert for CPU, log alerts for the rest.** Metric alerts evaluate in near real-time and are the right tool for threshold breaches; log alerts (KQL) handle anything requiring correlation or absence detection, like a lost heartbeat.
- **Absence detection via `max(TimeGenerated)`.** The heartbeat alert only considers machines seen in the last 24 hours, so decommissioned VMs don't create permanent false alarms.
- **Common alert schema enabled** on the action group, so payloads stay consistent if webhook or ITSM receivers are added later.

## Cost

Log Analytics includes 5 GB/month free ingestion; the alert rules cost a few cents per month at these evaluation frequencies. The whole stack tears down with `az group delete --name rg-monitoring`.

## Deployment evidence

**[Deployed resources]** <img width="1470" height="956" alt="alert-email" src="https://github.com/user-attachments/assets/3e3ed142-b160-474f-bb60-a97af2a4ffeb" />


**[Health report — all clear]** <img width="1470" height="956" alt="health-report" src="https://github.com/user-attachments/assets/c67e4a3f-5159-47b6-8cb0-29e5b0220b32" />


**[Fired alert email]** <img width="1470" height="956" alt="portal-resources" src="https://github.com/user-attachments/assets/e4a09eef-717f-4f27-96d7-8ba4b44fc660" />

