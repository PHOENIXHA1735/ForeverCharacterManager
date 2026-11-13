# Forever Character Manager v0.9.0 — Your own ForeverDB API key

The GitHub source ZIP and addon ZIP contain **no API keys or personal credentials**. Everyone who wants ForeverDB reference updates must use their **own approved key**. Do not copy the developer's key or anybody else's.

## ForeverDB API key — optional, private, and per user

**No API keys, tokens, or personal character data are included in the FCM v0.9.0 GitHub source or release ZIP.** Every person who wants authenticated ForeverDB updates must obtain their **own approved key**. FCM can run without a ForeverDB key; public AHledger and TheWoWDB updates may still work.

### Steps to obtain your own key

1. Open the [ForeverDB developer portal](https://foreverdb.net/developers).
2. Log in through **Battle.net**.
3. Request API access. Describe **Forever Character Manager (FCM)** as a **local Windows companion application/plugin for a WoW Forever addon**, supply a contact email, and agree to credit ForeverDB.net.
4. After ForeverDB approves your request, return to the developers page and create your own key (up to three per approved account).
5. When describing key use, select the option for a **personal application or plugin**, if offered. A local companion is not a website; follow ForeverDB's current key restrictions.
6. On your Windows PC, launch `ForeverCharacterManager/FCM-Companion/OPEN-FCM-DATA-UPDATER.cmd`.
7. Paste **your own key locally** into **ForeverDB API key**. Optionally tick **Remember encrypted for this Windows user**, which uses Windows DPAPI to save the key for that Windows account.
8. Click **Scan and Update**. A successful connection reports **ForeverDB API connected** in the companion log.

**Do not paste keys in GitHub issues, chats, screenshots, support requests, or source files.** Do not share a key or redistribute one in an addon. The companion keeps the key out of generated Lua reference data and GitHub downloads. Credentials saved with DPAPI are for the local Windows user, not for other users to copy.

ForeverDB currently advertises a free tier of **5,000 requests/day and 30 requests/minute per account**. Quotas, pricing, approvals, and attribution requirements may change; review [ForeverDB's current documentation](https://foreverdb.net/developers). Always credit ForeverDB.net with a visible link when displaying its data.

## Public alternatives without a ForeverDB key

The in-game addon runs without ForeverDB access. The Windows companion can still use public AHledger auction references and TheWoWDB lookups when those services are available. Cached local reference data is preserved across updates.

## Troubleshooting

- **Not configured:** Leave the key empty if you don't need ForeverDB, or request access at the portal.
- **Authentication failed (401/403):** Confirm the API request was approved and the correct key was entered on your own PC.
- **Rate limit (429):** Follow the provider's Retry-After guidance; don't bypass the quota.
- **Saved key cannot be unlocked:** DPAPI is tied to your Windows user. Re-enter your own key while signed into the appropriate Windows account.

See also `ForeverCharacterManager/FCM-Companion/ABOUT_DATA_SOURCES.txt` for the sources used by the companion.
