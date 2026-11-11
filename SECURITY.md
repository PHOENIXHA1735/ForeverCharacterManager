# Data and credential safety

Do not commit personal character data, WoW SavedVariables, generated `ExternalData.generated.lua`, local configuration, credentials, personal API keys, or logs.

The public source includes an `ExternalData.generated.template.lua` template only. The Windows companion should be run locally to populate reference data for your installation.

Before opening a pull request, review the diff for identifying information and credentials. To report a security issue, contact the maintainer privately rather than posting secrets in a public issue.
