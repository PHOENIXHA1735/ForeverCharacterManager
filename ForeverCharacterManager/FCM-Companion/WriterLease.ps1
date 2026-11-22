# Shared with fcm_writer_lease.py. Keep the handle open across all writes.
function Enter-FCMWriterLease([string]$Addon) {
    $item = Get-Item -LiteralPath $Addon -Force -ErrorAction Stop
    if (!$item.PSIsContainer) { throw 'FCM writer root is not a directory.' }
    for ($parent=$item; $parent; $parent=$parent.Parent) {
        if ($parent.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw 'FCM writer root contains a reparse point.'
        }
    }
    $lock = Join-Path $item.FullName '.fcm-writer.lock'
    $marker = Join-Path $item.FullName '.fcm-maintenance.json'
    if ([IO.File]::GetAttributes($item.FullName) -band [IO.FileAttributes]::ReadOnly) {
        throw 'FCM writer root is read-only.'
    }
    $existing=Get-Item -LiteralPath $lock -Force -ErrorAction SilentlyContinue
    if ($existing -and ($existing.PSIsContainer -or ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint))) {
        throw 'FCM writer lock is not a regular file.'
    }
    $handle=[IO.File]::Open($lock,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::ReadWrite)
    try {
        $handle.Lock(0,1)
        # Stat directly so permissions and other errors cannot look like absence.
        try {
            [void][IO.File]::GetAttributes($marker)
            throw 'FCM maintenance is active or requires recovery.'
        } catch [IO.FileNotFoundException] {}
        return $handle
    } catch {
        $handle.Dispose()
        throw
    }
}
