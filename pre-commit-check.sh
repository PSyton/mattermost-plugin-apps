#!/usr/bin/env bash

# Pre-commit verification script for Mattermost Apps Plugin v2.0
# Run this before every commit to ensure code quality

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
CHECKS_PASSED=0
CHECKS_FAILED=0

function print_header() {
    echo -e "\n${YELLOW}=== $1 ===${NC}"
}

function check_pass() {
    echo -e "${GREEN}✅ $1${NC}"
    ((CHECKS_PASSED++))
}

function check_fail() {
    echo -e "${RED}❌ $1${NC}"
    ((CHECKS_FAILED++))
}

function check_warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Change to repo root
cd "$(git rev-parse --show-toplevel)"

echo "Starting pre-commit checks..."
echo "Working directory: $(pwd)"

# Check 1: Compilation
print_header "Check 1: Compilation"
if go build ./... 2>&1 | tee /tmp/go-build.log; then
    check_pass "Code compiles successfully"
else
    check_fail "Compilation failed"
    cat /tmp/go-build.log
    exit 1
fi

# Check 2: Tests
print_header "Check 2: Unit Tests"
if make test 2>&1 | tee /tmp/go-test.log; then
    check_pass "All tests passed"
else
    check_fail "Some tests failed"
    tail -30 /tmp/go-test.log
    exit 1
fi

# Check 3: Old namespace check
print_header "Check 3: Namespace Verification"
OLD_NS_COUNT=$(grep -r "com\.mattermost\.apps\"" --include="*.go" --include="*.json" 2>/dev/null | \
    grep -v "2gis" | grep -v "CHANGELOG" | grep -v "MIGRATION" | grep -v "TODO" | wc -l || true)

if [ "$OLD_NS_COUNT" -eq 0 ]; then
    check_pass "No old namespace references found"
else
    check_fail "Found $OLD_NS_COUNT old namespace references"
    echo "Files with old namespace:"
    grep -r "com\.mattermost\.apps\"" --include="*.go" --include="*.json" 2>/dev/null | \
        grep -v "2gis" | grep -v "CHANGELOG" | grep -v "MIGRATION" | grep -v "TODO" | head -10
    exit 1
fi

# Check 4: New namespace presence (if namespace stage implemented)
print_header "Check 4: New Namespace Check"
NEW_NS_COUNT=$(grep -r "com\.2gis\.apps" --include="*.go" --include="*.json" 2>/dev/null | wc -l || true)

if [ "$NEW_NS_COUNT" -gt 0 ]; then
    check_pass "New namespace found in $NEW_NS_COUNT places"
elif git diff --cached --name-only | grep -q "plugin.json\|mattermost_client_pp.go"; then
    check_warn "Namespace change in progress but new namespace not found"
else
    check_warn "New namespace not yet implemented (OK if before Этап 13)"
fi

# Check 5: No periodic cache refresh
print_header "Check 5: No Periodic Cache Refresh"
PERIODIC_COUNT=$(grep -r "BindingsCacheInterval" --include="*.go" 2>/dev/null | wc -l || true)

if [ "$PERIODIC_COUNT" -eq 0 ]; then
    check_pass "No periodic cache refresh code found"
else
    check_fail "Found $PERIODIC_COUNT references to BindingsCacheInterval"
    echo "Should not have periodic cache refresh!"
    grep -r "BindingsCacheInterval" --include="*.go" 2>/dev/null
    exit 1
fi

# Check 6: Health check implementation
print_header "Check 6: Health Check Implementation"
HEALTH_CHECK_NIL=$(grep -r "OnHealthCheck.*nil" --include="*.go" 2>/dev/null | wc -l || true)

if [ "$HEALTH_CHECK_NIL" -eq 0 ]; then
    check_pass "No OnHealthCheck nil checks found"
else
    check_fail "Found $HEALTH_CHECK_NIL OnHealthCheck nil checks"
    echo "Health check should use fixed path, not check manifest!"
    grep -rn "OnHealthCheck.*nil" --include="*.go" 2>/dev/null
    exit 1
fi

PATH_HEALTH_COUNT=$(grep -r "path\.Health" --include="*.go" 2>/dev/null | wc -l || true)
if [ "$PATH_HEALTH_COUNT" -gt 0 ]; then
    check_pass "path.Health constant used ($PATH_HEALTH_COUNT references)"
elif git diff --cached --name-only | grep -q "app_activity_tracker.go\|paths.go"; then
    check_warn "Health check in progress"
else
    check_warn "path.Health not yet implemented (OK if before Этап 8)"
fi

# Check 7: Code formatting
print_header "Check 7: Code Formatting"
UNFORMATTED=$(gofmt -l . 2>/dev/null | grep -v "^vendor/" | grep -v "^node_modules/" || true)

if [ -z "$UNFORMATTED" ]; then
    check_pass "All code is properly formatted"
else
    check_warn "Some files need formatting:"
    echo "$UNFORMATTED"
    echo "Run: go fmt ./..."
fi

# Check 8: Go mod tidy
print_header "Check 8: Go Modules"
if go mod tidy 2>&1 | grep -q "no required module"; then
    check_pass "Go modules are clean"
else
    go mod tidy
    if git diff --exit-code go.mod go.sum > /dev/null 2>&1; then
        check_pass "Go modules are up to date"
    else
        check_warn "go.mod or go.sum were updated, please review and commit"
    fi
fi

# Summary
print_header "Summary"
echo "Checks passed: ${GREEN}$CHECKS_PASSED${NC}"
echo "Checks failed: ${RED}$CHECKS_FAILED${NC}"

if [ "$CHECKS_FAILED" -gt 0 ]; then
    echo -e "\n${RED}❌ Pre-commit checks FAILED${NC}"
    echo "Please fix the issues above before committing."
    exit 1
else
    echo -e "\n${GREEN}✅ All pre-commit checks PASSED${NC}"
    echo "You can proceed with commit."

    # Show what will be committed
    echo -e "\n${YELLOW}Files to be committed:${NC}"
    git diff --cached --name-only

    exit 0
fi
