FCM LOCAL AUCTION-HOUSE SCAN ARCHIVE

This folder contains PRIVATE local auction-house history.
RawScans stores personal scans. MarketTables is excluded by default; provider
tables may be archived only using -IncludeProviderTables when their retention
has been explicitly authorized for personal use.
Permission to retain never implies permission to redistribute.

The Windows folder setup script creates the following directories:
Incoming, RawScans, Parsed, Index, Reports\Daily, Reports\Weekly,
Reports\Monthly, Logs, Quarantine.

The folder setup alone does NOT copy data or enable a task. FCM-Companion's
FCM-AHHistory.ps1 provides Sync/Enable/Disable/Status controls. See
docs/AH_HISTORY.md in the source repository for the processing model.

Keep AHHistory when updating the addon. Never include its private scan files
in a public GitHub commit or a distributable addon ZIP.
