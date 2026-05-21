---
to: scripts/setup.sh
sh: chmod +x scripts/setup.sh
---
#!/usr/bin/env bash
set -euo pipefail

echo "Fetching .gitignore from gitignore.io..."
curl -sL "https://www.toptal.com/developers/gitignore/api/node" -o .gitignore
echo "Done."