#!/usr/bin/env bash
set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=== OpenAPI Dependabot Monitor ===${NC}\n"

# Step 1: Run the Ballerina monitor
echo -e "${BLUE}Step 1: Checking for OpenAPI updates...${NC}"
bal run main.bal

# Step 2: Check if updates were found
if [ ! -f "UPDATE_SUMMARY.txt" ]; then
  echo -e "${YELLOW}No updates found. Exiting.${NC}"
  exit 0
fi

# Step 3: Ask user if they want to create a PR
echo -e "\n${GREEN}Updates found!${NC}"
cat UPDATE_SUMMARY.txt
echo ""

read -p "Create a Pull Request with these updates? (y/n) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo -e "${BLUE}Step 2: Creating Pull Request...${NC}"
  ./scripts/create-pr.sh
else
  echo -e "${YELLOW}Skipping PR creation${NC}"
  echo "You can manually create a PR later by running: ./scripts/create-pr.sh"
fi