# Private local AH history and Gold Advisor

FCM archives existing files; it makes no provider requests. Retain provider
tables only where the provider has explicitly authorized personal retention.
No permission to redistribute data or third-party addon source is implied.

Run the existing Setup-FCM-AHHistory.ps1 against the installed addon first.
The companion's FCM-AHHistory.ps1 supports Sync, Enable, Disable and Status.
The matching CMD controls are installed beside it. Enable registers one
FCM-AHHistory task, repeating every 30 minutes while the Windows user is signed
in. It needs no running game. Disable prevents future runs without deleting
archives or interrupting an active safe copy. The task ignores overlapping
runs, and a file lock also covers manual invocations.

RawScans holds personal SavedVariables snapshots. MarketTables holds downloaded
AHledger_Data.lua snapshots. Source-path hashes separate accounts without
putting account identifiers in filenames. Metadata contains private source
paths locally. Archives use SHA-256 and UTC metadata, exclusive copying,
flushed temporary files and same-volume publication. No retention deletion runs.

The official AHLedger Sync app supplies fresh price tables. A standard Windows
Startup shortcut can launch that installed app at sign-in. FCM does not change
its source, authentication, contribution settings or refresh frequency.

The Python 3.10+ processor requires IANA timezone data (tzdata on Windows).
python-path.local.txt may select an installed interpreter and remains private.
The processor parses literal Lua data without evaluating Lua code. It verifies
archive hashes and incrementally imports into a private SQLite database. Unknown
formats, ambiguous scan markets and corrupt inputs produce no invented prices.
Original archives remain intact. Quarantine records validation failures.

Observations are provider snapshot medians or quantity-weighted personal scan
buyout medians, in copper. Bid-only listings are excluded. Provider rolling
averages are never imported as observations. Market identity includes ruleset,
region and faction. A personal scan wins an exact timestamp collision with a
provider snapshot. The 365-day window excludes older observations; archives and
the underlying database retain them. Each window averages its observed daily
means equally. Missing dates are never filled. Historical extrema are extrema
of observed snapshot medians, not every individual auction listing.

summary.json is private. AHHistory.generated.lua exports packed numeric summaries
only for the configured companion market's region/ruleset and both factions.
The addon decodes a market lazily. All raw parsing and historical calculations
run outside WoW. Load the next login or reload to see new summaries.

The Gold tab uses the Crafting palette and shows current quotes, five historical
windows, coverage, confidence and explanations. Rankings use estimated value,
estimated demand, supply and volatility. Unknown eligibility is withheld. Owned
materials carry market opportunity cost. Crafting requires a recorded learned
recipe, matching profession, verified transferable output, all reagent prices,
and explicit fee assumptions entered with the Gold fee button. Farming requires
a measured rate and explicit opportunity-cost assumptions entered with the Gold
farm button. Rates and fees are user assumptions, never fabricated observations.
Inventory and bank values are snapshots. Farm assumptions use copper/hour;
craft deposit is expected unrecovered copper per crafting batch. Buy/sell/hold
spreads assume a 5% faction AH cut and explicitly exclude deposits; sell spreads
are premiums over baseline, not acquisition profit. No auctions are automated.

Day/hour comparisons preserve UTC observations and display America/Los_Angeles,
including DST rules. Relative daily prices reduce long-term trend bias. At least
two adequately sampled buckets are required: 10 observations on 4 dates for a
weekday, or 10 observations on 5 dates for an hour. These are descriptive
listing-price patterns, not proven causal effects or guaranteed buying/selling
windows. Confirmed personal sale-mail records are summarized separately by item,
with gross, recorded cut, net proceeds and refunded deposits. The ledger lacks
market identity, so these records remain account-scoped and are excluded from
market statistics/rankings. Recorded times are not assumed to be exact sale times.
Acquisition costs are unknown: proceeds are never labeled profit. Listing
snapshots are never represented as completed sales.

Tests: qa_ah_archive.ps1 (PowerShell 5.1); qa_ah_history.py; qa_gold_advisor.lua
(Lua 5.1); check_private_paths.py. All committed fixtures are synthetic.
Live Task Scheduler, sign-in startup and in-game visual behavior require their
own Windows/client verification. A failing task installation must be reported,
never presented as active automation. No release is authorized by these changes.
