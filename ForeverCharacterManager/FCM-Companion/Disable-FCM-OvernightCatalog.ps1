# Remove only the FCM overnight catalog task, leaving user data and other tasks.
$ErrorActionPreference='Stop'
foreach ($name in @('FCM ForeverDB Overnight Catalog','FCM ForeverDB Morning Catalog')) {
    $task=Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
    if ($task) {
        Unregister-ScheduledTask -TaskName $name -Confirm:$false
        Write-Host ('Disabled: '+$name)
    } else {
        Write-Host ('Not installed: '+$name)
    }
}
