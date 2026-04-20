#!/bin/bash
set -e

# WhisPaste GitHub Secrets Setup
# This script sets up all required GitHub secrets for CI/CD workflows
# Reads from .env and sets each secret on GitHub via 'gh secret set'
# Run: ./scripts/setup-gh-secrets.sh

REPO="whispaste/whispaste"
SECRETS_FILE=".env"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}WhisPaste GitHub Secrets Setup${NC}"
echo "Repository: $REPO"
echo ""

# Check GitHub CLI auth
if ! gh auth status > /dev/null 2>&1; then
  echo -e "${YELLOW}GitHub CLI not authenticated. Run: gh auth login${NC}"
  exit 1
fi

echo -e "${GREEN}✓ GitHub CLI authenticated${NC}"
echo ""

# Function to prompt and set secret
set_secret() {
  local secret_name=$1
  local secret_desc=$2
  local secret_value=$3

  if [ -z "$secret_value" ]; then
    echo -n "Enter $secret_desc ($secret_name): "
    read -rs secret_value
    echo ""
  fi

  if [ -n "$secret_value" ]; then
    gh secret set "$secret_name" -b "$secret_value" --repo "$REPO"
    echo -e "${GREEN}✓ Set $secret_name${NC}"
  else
    echo -e "${YELLOW}✗ Skipped $secret_name (empty value)${NC}"
  fi
}

echo "Loading secrets from $SECRETS_FILE:"
echo ""

# Load from .env if it exists
if [ -f "$SECRETS_FILE" ]; then
  # Extract and set each secret
  while IFS='=' read -r key value; do
    # Skip comments and empty lines
    [[ $key =~ ^[[:space:]]*# ]] && continue
    [[ -z "$key" ]] && continue

    # Trim whitespace
    key=$(echo "$key" | xargs)
    value=$(echo "$value" | xargs)

    if [ -n "$value" ]; then
      gh secret set "$key" -b "$value" --repo "$REPO"
      echo -e "${GREEN}✓ Set $key${NC}"
    fi
  done < "$SECRETS_FILE"
else
  echo -e "${YELLOW}$SECRETS_FILE not found. Prompting for values:${NC}"
  echo ""
  set_secret "SENTRY_AUTH_TOKEN" "Sentry Auth Token"
  set_secret "SUPABASE_URL" "Supabase URL"
  set_secret "SUPABASE_PUBLISHABLE_KEY" "Supabase Publishable Key"
fi

echo ""
echo -e "${GREEN}GitHub secrets setup complete!${NC}"
echo ""
echo "Verify secrets:"
gh secret list --repo "$REPO"
