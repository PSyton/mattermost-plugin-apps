#!/usr/bin/env bash

# Git pre-commit hook
# Automatically runs pre-commit-check.sh before allowing commit
# To install: ln -s ../../pre-commit-hook.sh .git/hooks/pre-commit

# Get repo root
REPO_ROOT=$(git rev-parse --show-toplevel)

echo "Running pre-commit checks..."

# Run the pre-commit check script
if "$REPO_ROOT/pre-commit-check.sh"; then
    echo ""
    echo "✅ Pre-commit checks passed. Proceeding with commit."
    exit 0
else
    echo ""
    echo "❌ Pre-commit checks failed. Commit aborted."
    echo ""
    echo "To fix:"
    echo "  1. Review the errors above"
    echo "  2. Fix the issues"
    echo "  3. Try committing again"
    echo ""
    echo "To skip checks (NOT RECOMMENDED):"
    echo "  git commit --no-verify"
    exit 1
fi
