# Offline Windows PowerShell regression test for the shared ForeverDB budget.
# This deliberately does not contact ForeverDB or touch the real budget file.
$ErrorActionPreference='Stop'
$script:Base=$PSScriptRoot
. (Join-Path $PSScriptRoot 'ForeverDB.Quota.ps1')

$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('FCM-Quota-Test-'+[guid]::NewGuid().ToString('N'))
$testFile=Join-Path $testRoot 'isolated-budget.json'
$created=$false
try {
    New-Item -ItemType Directory -Path $testRoot -ErrorAction Stop | Out-Null
    $created=$true
    $first=[ordered]@{utcDay='2026-11-14';requests=1;cap=4500;lastRequestUtc='2026-11-14T07:00:00Z'}
    $second=[ordered]@{utcDay='2026-11-14';requests=2;cap=4500;lastRequestUtc='2026-11-14T07:00:04Z'}
    Write-FCMForeverDBAtomicJson $testFile $first
    Write-FCMForeverDBAtomicJson $testFile $second
    $current=Get-Content -LiteralPath $testFile -Raw | ConvertFrom-Json
    $previous=Get-Content -LiteralPath ($testFile+'.previous') -Raw | ConvertFrom-Json
    if ([int]$current.requests -ne 2) {throw 'Current budget failed to advance to two requests.'}
    if ([int]$previous.requests -ne 1) {throw 'Previous budget backup did not preserve the prior count.'}
    Write-Host 'PASS: quota ledger created, atomically updated, and previous count preserved.'
    exit 0
} catch {
    Write-Host ('FAIL: quota ledger test: '+$_.Exception.Message) -ForegroundColor Red
    exit 1
} finally {
    # Clean up only the exact newly created temporary test directory.
    if ($created -and (Test-Path -LiteralPath $testRoot)) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
