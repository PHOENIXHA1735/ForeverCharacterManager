# Remove only the FCM overnight catalog task, leaving user data and other tasks.
$ErrorActionPreference='Stop'
$name='FCM ForeverDB Overnight Catalog'
$task=Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
if ($task) {
    Unregister-ScheduledTask -TaskName $name -Confirm:$false
    Write-Host ('Disabled: '+$name)
} else {
    Write-Host ('Not installed: '+$name)
}
