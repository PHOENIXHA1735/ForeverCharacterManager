# Stops only FCM-owned recurring tasks. Existing addon files/cache remain.
$ErrorActionPreference='Stop'
foreach ($name in @('FCM Auction House Price Refresh','FCM ForeverDB Build Check','FCM Daily Auction House Refresh')) {
    $task=Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
    if ($task) {Unregister-ScheduledTask -TaskName $name -Confirm:$false;Write-Host ('Disabled: '+$name)}
}
