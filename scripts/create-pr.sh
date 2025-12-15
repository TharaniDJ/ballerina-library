#!/bin/bash

# Script to create PR in api-specs repo after detecting updates
# Works with Documents/GitHub/ structure

set -e

echo "════════════════════════════════════════════════════════"
echo "  Creating PR for OpenAPI Spec Updates"
echo "════════════════════════════════════════════════════════"
echo ""

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BALLERINA_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"

# Check if UPDATE_SUMMARY.md exists
if [ ! -f "$BALLERINA_DIR/UPDATE_SUMMARY.md" ]; then
    echo "❌ Error: UPDATE_SUMMARY.md not found"
    echo "Run the Ballerina version checker first:"
    echo "  cd $BALLERINA_DIR"
    echo "  bal run src/repo_fetcher"
    exit 1
fi

# Determine api-specs location
# Try relative path first (side by side repos)
API_SPECS_DIR="$BALLERINA_DIR/../api-specs"

if [ ! -d "$API_SPECS_DIR" ]; then
    echo "❌ Error: api-specs directory not found at $API_SPECS_DIR"
    echo ""
    echo "Expected structure:"
    echo "  Documents/GitHub/"
    echo "    ├── ballerina-library/"
    echo "    └── api-specs/"
    exit 1
fi

echo "✓ Found api-specs at: $API_SPECS_DIR"
echo ""

cd "$API_SPECS_DIR"

# Check for changes
if [ -z "$(git status --porcelain)" ]; then
    echo "ℹ️  No changes detected in api-specs"
    exit 0
fi

echo "📋 Changes detected:"
git status --short openapi/
echo ""

# Create a new branch
BRANCH_NAME="openapi-update-$(date +%Y%m%d-%H%M%S)"
echo "🌿 Creating branch: $BRANCH_NAME"
git checkout -b "$BRANCH_NAME"

# Stage all changes in openapi/ directory
echo "📦 Staging changes..."
git add openapi/

# Commit with the summary
echo "💾 Creating commit..."
git commit -F "$BALLERINA_DIR/UPDATE_SUMMARY.md"

# Push to origin
echo "⬆️  Pushing to origin..."
git push origin "$BRANCH_NAME"

# Create PR using GitHub CLI
if command -v gh &> /dev/null; then
    echo "📬 Creating Pull Request..."
    
    # Extract title from first line
    TITLE=$(head -n 1 "$BALLERINA_DIR/UPDATE_SUMMARY.md" | sed 's/^# //')
    
    gh pr create \
        --title "$TITLE" \
        --body-file "$BALLERINA_DIR/UPDATE_SUMMARY.md" \
        --base main \
        --head "$BRANCH_NAME"
    
    echo ""
    echo "✅ Pull request created successfully!"
    echo ""
    echo "View PR at: https://github.com/TharaniDJ/api-specs/pulls"
else
    echo ""
    echo "⚠️  GitHub CLI (gh) not found"
    echo ""
    echo "📝 Manual steps to create PR:"
    echo "   1. Go to: https://github.com/TharaniDJ/api-specs/pulls"
    echo "   2. Click 'New Pull Request'"
    echo "   3. Click 'compare: main' and select: $BRANCH_NAME"
    echo "   4. Copy the content from UPDATE_SUMMARY.md as the description"
    echo ""
    echo "Or install GitHub CLI:"
    echo "   macOS:   brew install gh"
    echo "   Ubuntu:  sudo apt install gh"
    echo "   Windows: winget install GitHub.cli"
fi

# Return to original directory
cd "$BALLERINA_DIR"

echo ""
echo "════════════════════════════════════════════════════════"
echo "  ✨ Done!"
echo "════════════════════════════════════════════════════════"