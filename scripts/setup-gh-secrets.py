"""
WhisPaste GitHub Secrets Setup
Set GitHub secrets from .env or command-line arguments.
Usage:
  python3 scripts/setup-gh-secrets.py                  # Load from .env
  python3 scripts/setup-gh-secrets.py --list           # List current secrets
"""

import os
import sys
import subprocess
import argparse
from pathlib import Path


def run_gh_command(args):
    """Run a GitHub CLI command."""
    try:
        result = subprocess.run(
            ["gh"] + args,
            capture_output=True,
            text=True,
            check=True
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        print(f"❌ Error: {e.stderr}")
        sys.exit(1)
    except FileNotFoundError:
        print("❌ GitHub CLI (gh) not found. Install from: https://cli.github.com")
        sys.exit(1)


def check_auth():
    """Verify GitHub CLI authentication."""
    try:
        run_gh_command(["auth", "status"])
        return True
    except SystemExit:
        return False


def set_secret(name, value, repo):
    """Set a single GitHub secret."""
    try:
        run_gh_command(["secret", "set", name, "-b", value, "--repo", repo])
        print(f"✓ Set {name}")
    except SystemExit:
        print(f"✗ Failed to set {name}")


def list_secrets(repo):
    """List all GitHub secrets."""
    output = run_gh_command(["secret", "list", "--repo", repo])
    print("\nCurrent secrets:")
    print(output)


def load_from_env(file_path):
    """Load secrets from .env file."""
    secrets = {}
    if not os.path.exists(file_path):
        print(f"⚠ {file_path} not found")
        return secrets

    with open(file_path, "r") as f:
        for line in f:
            line = line.strip()
            if line.startswith("#") or not line:
                continue
            if "=" in line:
                key, value = line.split("=", 1)
                secrets[key.strip()] = value.strip()

    return secrets


def main():
    parser = argparse.ArgumentParser(
        description="WhisPaste GitHub Secrets Setup"
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="List current GitHub secrets"
    )
    parser.add_argument(
        "--secrets-file",
        default=".env",
        help="Path to secrets file (default: .env)"
    )

    args = parser.parse_args()
    repo = "whispaste/whispaste"

    print("WhisPaste GitHub Secrets Setup")
    print(f"Repository: {repo}")
    print()

    # Check auth
    if not check_auth():
        print("❌ GitHub CLI not authenticated. Run: gh auth login")
        sys.exit(1)

    print("✓ GitHub CLI authenticated")
    print()

    if args.list:
        list_secrets(repo)
        return

    # Load and set secrets
    secrets = load_from_env(args.secrets_file)

    if secrets:
        print(f"Loading secrets from {args.secrets_file}:")
        print()
        for key, value in secrets.items():
            if value:
                set_secret(key, value, repo)
            else:
                print(f"⊘ Skipped {key} (empty value)")
    else:
        print(f"❌ No secrets found in {args.secrets_file}")
        print("Create .env from .env.example and fill in values.")
        sys.exit(1)

    print()
    print("✓ GitHub secrets setup complete!")
    print()
    list_secrets(repo)


if __name__ == "__main__":
    main()
