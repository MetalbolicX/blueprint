#!/usr/bin/env bash
set -euo pipefail

echo "Fetching .gitignore from gitignore.io..."
curl -sL "https://www.toptal.com/developers/gitignore/api/node" -o .gitignore
echo "Done."

echo "Installing dependencies..."
npm install
echo "Dependencies installed."