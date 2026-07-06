"""
Azure environment health report.

Runs the same KQL used by the alert rules (see kql/) against a
Log Analytics workspace and prints a plain-language summary.

Usage:
    az login
    python health_report.py <workspace-customer-id>

The workspace customer ID (a GUID) is shown in the Azure Portal on
the workspace Overview page, or in the deployment output
`workspaceCustomerId`.
"""

import sys
from datetime import timedelta

from azure.identity import DefaultAzureCredential
from azure.monitor.query import LogsQueryClient, LogsQueryStatus

HEARTBEAT_QUERY = """
Heartbeat
| summarize LastHeartbeat = max(TimeGenerated) by Computer
| extend MinutesSilent = datetime_diff("minute", now(), LastHeartbeat)
| extend Status = iff(MinutesSilent > 10, "SILENT", "OK")
| order by MinutesSilent desc
"""

CPU_QUERY = """
Perf
| where ObjectName == "Processor" and CounterName == "% Processor Time"
| where InstanceName == "_Total"
| summarize AvgCPU = round(avg(CounterValue), 1),
            MaxCPU = round(max(CounterValue), 1) by Computer
"""

FAILURES_QUERY = """
AzureActivity
| where CategoryValue == "Administrative"
| where ActivityStatusValue == "Failure"
| summarize FailureCount = count() by Caller
| order by FailureCount desc
"""


def run_query(client, workspace_id, query):
    """Run a KQL query and return its rows, or None on failure."""
    response = client.query_workspace(
        workspace_id, query, timespan=timedelta(hours=24)
    )
    if response.status != LogsQueryStatus.SUCCESS:
        return None
    table = response.tables[0]
    return [dict(zip(table.columns, row)) for row in table.rows]


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(1)

    workspace_id = sys.argv[1]
    client = LogsQueryClient(DefaultAzureCredential())
    issues = 0

    print("=" * 52)
    print("AZURE HEALTH REPORT (last 24 hours)")
    print("=" * 52)

    # --- VM heartbeats -------------------------------------
    print("\n[1] VM heartbeat status")
    rows = run_query(client, workspace_id, HEARTBEAT_QUERY)
    if not rows:
        print("    No heartbeat data (no VMs connected yet).")
    else:
        for r in rows:
            flag = "!!" if r["Status"] == "SILENT" else "ok"
            if r["Status"] == "SILENT":
                issues += 1
            print(f"    [{flag}] {r['Computer']}: "
                  f"last seen {r['MinutesSilent']} min ago")

    # --- CPU ------------------------------------------------
    print("\n[2] CPU usage by machine")
    rows = run_query(client, workspace_id, CPU_QUERY)
    if not rows:
        print("    No performance data collected yet.")
    else:
        for r in rows:
            flag = "!!" if r["MaxCPU"] > 80 else "ok"
            if r["MaxCPU"] > 80:
                issues += 1
            print(f"    [{flag}] {r['Computer']}: "
                  f"avg {r['AvgCPU']}%, peak {r['MaxCPU']}%")

    # --- Failed operations ---------------------------------
    print("\n[3] Failed administrative operations")
    rows = run_query(client, workspace_id, FAILURES_QUERY)
    if not rows:
        print("    None recorded. All clear.")
    else:
        for r in rows:
            issues += 1
            print(f"    [!!] {r['Caller']}: {r['FailureCount']} failures")

    # --- Summary --------------------------------------------
    print("\n" + "=" * 52)
    print("RESULT: all clear" if issues == 0
          else f"RESULT: {issues} item(s) need attention")
    print("=" * 52)
    sys.exit(0 if issues == 0 else 2)


if __name__ == "__main__":
    main()
