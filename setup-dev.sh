#!/usr/bin/env bash

# Setup script for development environment
# Run this once to setup all development tools

set -e

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

echo "Setting up development environment for v2.0 refactoring..."
echo "Repository: $REPO_ROOT"
echo ""

# 1. Install Git hooks
echo "=== Installing Git hooks ==="
if [ -d ".git/hooks" ]; then
    # Install pre-commit hook
    if [ -f "pre-commit-hook.sh" ]; then
        ln -sf ../../pre-commit-hook.sh .git/hooks/pre-commit
        echo "✅ Pre-commit hook installed"
    else
        echo "⚠️  pre-commit-hook.sh not found, skipping"
    fi
else
    echo "⚠️  .git/hooks directory not found, skipping hooks installation"
fi

# 2. Verify required tools
echo ""
echo "=== Checking required tools ==="

check_tool() {
    if command -v "$1" &> /dev/null; then
        echo "✅ $1 is installed"
        return 0
    else
        echo "❌ $1 is NOT installed"
        return 1
    fi
}

TOOLS_OK=true

check_tool "go" || TOOLS_OK=false
check_tool "make" || TOOLS_OK=false
check_tool "git" || TOOLS_OK=false
check_tool "grep" || TOOLS_OK=false
check_tool "gofmt" || TOOLS_OK=false

if [ "$TOOLS_OK" = false ]; then
    echo ""
    echo "⚠️  Some required tools are missing. Please install them."
    exit 1
fi

# 3. Check Go version
echo ""
echo "=== Checking Go version ==="
GO_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
echo "Go version: $GO_VERSION"

if [ "$GO_VERSION" \< "1.19" ]; then
    echo "⚠️  Go 1.19+ is recommended, you have $GO_VERSION"
else
    echo "✅ Go version is compatible"
fi

# 4. Download dependencies
echo ""
echo "=== Downloading Go dependencies ==="
if go mod download; then
    echo "✅ Dependencies downloaded"
else
    echo "❌ Failed to download dependencies"
    exit 1
fi

# 5. Run go mod tidy
echo ""
echo "=== Running go mod tidy ==="
if go mod tidy; then
    echo "✅ Go modules cleaned"
else
    echo "❌ Failed to run go mod tidy"
    exit 1
fi

# 6. Test compilation
echo ""
echo "=== Testing compilation ==="
if go build ./...; then
    echo "✅ Code compiles successfully"
else
    echo "❌ Compilation failed"
    exit 1
fi

# 7. Run tests
echo ""
echo "=== Running tests ==="
if make test; then
    echo "✅ Tests passed"
else
    echo "⚠️  Some tests failed (this might be expected)"
fi

# 8. Create feature branch
echo ""
echo "=== Git branch setup ==="
CURRENT_BRANCH=$(git branch --show-current)
echo "Current branch: $CURRENT_BRANCH"

if [ "$CURRENT_BRANCH" != "feature/v2-refactoring" ]; then
    read -p "Create feature/v2-refactoring branch? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        git checkout -b feature/v2-refactoring
        echo "✅ Created and switched to feature/v2-refactoring branch"
    else
        echo "⏭️  Skipped branch creation"
    fi
else
    echo "✅ Already on feature/v2-refactoring branch"
fi

# 9. Summary
echo ""
echo "===================================="
echo "✅ Setup complete!"
echo "===================================="
echo ""
echo "Next steps:"
echo "  1. Read TODO.md for implementation plan"
echo "  2. Read .copilot-instructions.md for coding guidelines"
echo "  3. Run ./pre-commit-check.sh to verify everything works"
echo "  4. Start implementing (recommended: Этап 13 or Этап 1)"
echo ""
echo "Quick commands:"
echo "  ./pre-commit-check.sh    - Verify code before commit"
echo "  make test                - Run tests"
echo "  go build ./...           - Compile code"
echo ""
echo "Documentation:"
echo "  DOCS_INDEX.md            - Index of all documentation"
echo "  TODO.md                  - Implementation plan"
echo "  DEVELOPMENT.md           - Development workflow"
echo ""
echo "Happy coding! 🚀"
