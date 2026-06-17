param(
  [Parameter(Mandatory = $true)]
  [string]$ProjectId,

  [Parameter(Mandatory = $true)]
  [string]$BackendHost,

  [Parameter(Mandatory = $true)]
  [string]$NotificationChannel
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$tmpDir = Join-Path $scriptDir ".tmp"
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null

function Expand-Template {
  param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
  )

  $content = Get-Content -LiteralPath $InputPath -Raw
  $content = $content.Replace("PROJECT_ID", $ProjectId)
  $content = $content.Replace("BACKEND_HOST", $BackendHost)
  $content = $content.Replace("NOTIFICATION_CHANNEL", $NotificationChannel)
  Set-Content -LiteralPath $OutputPath -Value $content -Encoding UTF8
}

gcloud.cmd config set project $ProjectId | Out-Null

$uptimeDisplayName = "Navi backend health uptime"
$existingUptimeChecks = gcloud.cmd monitoring uptime list-configs `
  --project=$ProjectId `
  --filter="displayName=`"$uptimeDisplayName`"" `
  --format="value(name)"

if ($existingUptimeChecks) {
  Write-Host "Uptime check already exists; skipping create: $uptimeDisplayName"
} else {
  gcloud.cmd monitoring uptime create $uptimeDisplayName `
    --resource-type=uptime-url `
    --resource-labels=host=$BackendHost,project_id=$ProjectId `
    --protocol=https `
    --path=/health `
    --port=443 `
    --validate-ssl=true `
    --request-method=get `
    --period=1 `
    --timeout=10 `
    --regions=usa-iowa,usa-oregon,usa-virginia
}

foreach ($name in @(
  "alert-cloud-run-5xx.json",
  "alert-cloud-run-latency.json",
  "alert-cloud-run-timeouts.json"
)) {
  $expanded = Join-Path $tmpDir $name
  Expand-Template `
    -InputPath (Join-Path $scriptDir $name) `
    -OutputPath $expanded

  $policyDisplayName = (Get-Content -LiteralPath $expanded -Raw | ConvertFrom-Json).displayName
  $existingPolicy = gcloud.cmd monitoring policies list `
    --project=$ProjectId `
    --filter="displayName=`"$policyDisplayName`"" `
    --format="value(name)"

  if ($existingPolicy) {
    Write-Host "Alert policy already exists; skipping create: $policyDisplayName"
  } else {
    gcloud.cmd monitoring policies create `
      --policy-from-file=$expanded `
      --notification-channels=$NotificationChannel
  }
}

$existingProductEventsMetric = gcloud.cmd logging metrics list `
  --project=$ProjectId `
  --filter="name=product_events" `
  --format="value(name)"

if ($existingProductEventsMetric) {
  Write-Host "Log metric already exists; skipping create: product_events"
} else {
  gcloud.cmd logging metrics create product_events `
    --description="Counts privacy-safe Navi backend product_event logs." `
    --log-filter="resource.type=`"cloud_run_revision`" AND jsonPayload.message=`"product_event`""
}

$existingBackend5xxMetric = gcloud.cmd logging metrics list `
  --project=$ProjectId `
  --filter="name=backend_5xx_completions" `
  --format="value(name)"

if ($existingBackend5xxMetric) {
  Write-Host "Log metric already exists; skipping create: backend_5xx_completions"
} else {
  gcloud.cmd logging metrics create backend_5xx_completions `
    --description="Counts Navi backend request_complete logs with 5xx status codes." `
    --log-filter="resource.type=`"cloud_run_revision`" AND jsonPayload.message=`"request_complete`" AND jsonPayload.status_code>=500"
}

Write-Host "Monitoring setup submitted for project $ProjectId"
