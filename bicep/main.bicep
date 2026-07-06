// =============================================================
// Azure Monitoring & Alerting Pipeline
// Deploys: Log Analytics workspace, action group (email),
//          and three alert rules (CPU, heartbeat, activity failures)
//
// Deploy:
//   az deployment group create \
//     --resource-group rg-monitoring \
//     --template-file bicep/main.bicep \
//     --parameters alertEmail=you@example.com
// =============================================================

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Name of the Log Analytics workspace')
param workspaceName string = 'log-monitoring-${uniqueString(resourceGroup().id)}'

@description('Email address that receives alert notifications')
param alertEmail string

@description('Optional: resource ID of a VM to monitor with the CPU alert. Leave empty to skip.')
param vmResourceId string = ''

@description('Log retention in days (30 = free-tier friendly)')
@minValue(30)
@maxValue(730)
param retentionInDays int = 30

// -------------------------------------------------------------
// Log Analytics workspace
// -------------------------------------------------------------
resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
  tags: {
    project: 'azure-monitoring-alerts'
    environment: 'demo'
  }
}

// -------------------------------------------------------------
// Action group: who gets notified, and how
// -------------------------------------------------------------
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-monitoring-email'
  location: 'global'
  properties: {
    groupShortName: 'MonAlerts'
    enabled: true
    emailReceivers: [
      {
        name: 'primary-email'
        emailAddress: alertEmail
        useCommonAlertSchema: true
      }
    ]
  }
  tags: {
    project: 'azure-monitoring-alerts'
  }
}

// -------------------------------------------------------------
// Alert 1 — VM CPU above 80% (metric alert, near real-time)
// Only deployed when a VM resource ID is supplied.
// -------------------------------------------------------------
resource cpuAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (!empty(vmResourceId)) {
  name: 'alert-vm-cpu-high'
  location: 'global'
  properties: {
    description: 'Fires when average CPU exceeds 80% over a 5-minute window'
    severity: 2
    enabled: true
    scopes: [
      vmResourceId
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          name: 'HighCpu'
          metricName: 'Percentage CPU'
          metricNamespace: 'Microsoft.Compute/virtualMachines'
          operator: 'GreaterThan'
          threshold: 80
          timeAggregation: 'Average'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// -------------------------------------------------------------
// Alert 2 — VM heartbeat lost (log alert on the workspace)
// Detects agents that reported in the last 24h but have gone
// silent for 10+ minutes.
// -------------------------------------------------------------
resource heartbeatAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-vm-heartbeat-lost'
  location: location
  properties: {
    displayName: 'VM heartbeat lost'
    description: 'Fires when a previously reporting VM stops sending heartbeats for 10 minutes'
    severity: 1
    enabled: true
    scopes: [
      workspace.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'P1D'
    criteria: {
      allOf: [
        {
          query: '''
            Heartbeat
            | summarize LastHeartbeat = max(TimeGenerated) by Computer
            | where LastHeartbeat < ago(10m)
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [
        actionGroup.id
      ]
    }
  }
}

// -------------------------------------------------------------
// Alert 3 — Failed administrative operations (log alert)
// Requires the subscription Activity Log to be exported to this
// workspace (see README: one-line az monitor diagnostic-settings).
// -------------------------------------------------------------
resource activityFailureAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-activity-failures'
  location: location
  properties: {
    displayName: 'Failed administrative operations'
    description: 'Fires when 5 or more administrative operations fail within 15 minutes'
    severity: 3
    enabled: true
    scopes: [
      workspace.id
    ]
    evaluationFrequency: 'PT15M'
    windowSize: 'PT15M'
    criteria: {
      allOf: [
        {
          query: '''
            AzureActivity
            | where CategoryValue == "Administrative"
            | where ActivityStatusValue == "Failure"
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThanOrEqual'
          threshold: 5
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [
        actionGroup.id
      ]
    }
  }
}

// -------------------------------------------------------------
// Outputs
// -------------------------------------------------------------
output workspaceId string = workspace.id
output workspaceCustomerId string = workspace.properties.customerId
output actionGroupId string = actionGroup.id
