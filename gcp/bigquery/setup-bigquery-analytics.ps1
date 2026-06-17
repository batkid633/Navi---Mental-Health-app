param(
  [Parameter(Mandatory = $true)]
  [string]$ProjectId,

  [string]$Dataset = "navi_analytics",

  [string]$Table = "product_events",

  [string]$Location = "US",

  [string]$CloudRunServiceAccount = "712966180400-compute@developer.gserviceaccount.com"
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$schemaPath = Join-Path $scriptDir "analytics_events_schema.json"
$tableRef = "${ProjectId}:${Dataset}.${Table}"

gcloud.cmd config set project $ProjectId | Out-Null

$datasetExists = bq.cmd --project_id=$ProjectId ls --format=prettyjson |
  ConvertFrom-Json |
  Where-Object { $_.datasetReference.datasetId -eq $Dataset }

if ($datasetExists) {
  Write-Host "BigQuery dataset already exists: $ProjectId.$Dataset"
} else {
  bq.cmd --project_id=$ProjectId --location=$Location mk --dataset $Dataset
}

$tableExists = $false
bq.cmd --project_id=$ProjectId show --format=prettyjson $tableRef | Out-Null
if ($LASTEXITCODE -eq 0) {
  $tableExists = $true
}

if ($tableExists) {
  Write-Host "BigQuery table already exists: $tableRef"
  bq.cmd --project_id=$ProjectId update $tableRef $schemaPath
} else {
  bq.cmd --project_id=$ProjectId mk `
    --table `
    --time_partitioning_field=event_date `
    --time_partitioning_type=DAY `
    --clustering_fields=event_name,platform,event_source `
    $tableRef `
    $schemaPath
}

gcloud.cmd projects add-iam-policy-binding $ProjectId `
  --member="serviceAccount:$CloudRunServiceAccount" `
  --role="roles/bigquery.dataEditor" `
  --condition=None | Out-Null

gcloud.cmd projects add-iam-policy-binding $ProjectId `
  --member="serviceAccount:$CloudRunServiceAccount" `
  --role="roles/bigquery.jobUser" `
  --condition=None | Out-Null

Write-Host "BigQuery analytics ready: $ProjectId.$Dataset.$Table"
