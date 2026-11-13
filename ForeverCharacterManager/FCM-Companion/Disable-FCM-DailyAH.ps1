# Remove only FCM's scheduled refresh. Does not touch WoW or other tasks.
$ErrorActionPreference='Stop'
$taskName='FCM Daily Auction House Refresh'
$task=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($task) { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false; Write-Host 'FCM daily AH refresh disabled.' }
else {Write-Host 'FCM daily AH refresh is not currently scheduled.'}
