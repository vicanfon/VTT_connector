#!/usr/bin/env bash
# Check if test-client is recognized as a valid dataspace participant

echo "=========================================="
echo "Client Validity Check"
echo "=========================================="
echo ""
echo "This checks if test-client is a valid participant"
echo "that other connectors will recognize and accept."
echo ""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Step 1: Check all connector environment variables
echo "=========================================="
echo "Step 1: Connector DAPS Configuration"
echo "=========================================="
echo ""

echo "All DAPS-related environment variables in connector:"
docker compose exec connector env 2>/dev/null | grep -i "daps" | sort

if [ $? -ne 0 ]; then
    echo "Could not read connector environment"
    echo "Is the connector running?"
    docker compose ps connector
    exit 1
fi

echo ""
echo ""

# Step 2: Check docker-compose.yml configuration
echo "=========================================="
echo "Step 2: Docker Compose Configuration"
echo "=========================================="
echo ""

echo "DAPS configuration in docker-compose.yml:"
grep -A 20 "connector:" docker-compose.yml | grep -i "daps" | head -10

echo ""
echo ""

# Step 3: Decode the token to see who issued it
echo "=========================================="
echo "Step 3: Analyze Your Token"
echo "=========================================="
echo ""

if [ -f /tmp/daps-token.txt ]; then
    TOKEN=$(cat /tmp/daps-token.txt)

    echo "Token payload (decoded):"
    # Decode JWT payload (middle part)
    PAYLOAD=$(echo "$TOKEN" | cut -d. -f2)

    # Add padding if needed for base64
    case $((${#PAYLOAD} % 4)) in
        2) PAYLOAD="${PAYLOAD}==" ;;
        3) PAYLOAD="${PAYLOAD}=" ;;
    esac

    echo "$PAYLOAD" | base64 -d 2>/dev/null | jq '.' || echo "$PAYLOAD" | base64 -d 2>/dev/null

    echo ""

    # Extract key claims
    ISSUER=$(echo "$PAYLOAD" | base64 -d 2>/dev/null | jq -r '.iss' 2>/dev/null)
    SUBJECT=$(echo "$PAYLOAD" | base64 -d 2>/dev/null | jq -r '.sub' 2>/dev/null)
    AUDIENCE=$(echo "$PAYLOAD" | base64 -d 2>/dev/null | jq -r '.aud[]?' 2>/dev/null)
    EXPIRY=$(echo "$PAYLOAD" | base64 -d 2>/dev/null | jq -r '.exp' 2>/dev/null)

    echo "Key claims:"
    echo "  Issuer (iss):   $ISSUER"
    echo "  Subject (sub):  $SUBJECT"
    echo "  Audience (aud): $AUDIENCE"
    echo "  Expires (exp):  $EXPIRY ($(date -d @$EXPIRY 2>/dev/null || echo 'invalid'))"

else
    echo "No token found at /tmp/daps-token.txt"
    echo "Run: ./scripts/fix-daps-client.sh"
    ISSUER=""
fi

echo ""
echo ""

# Step 4: Check connector config file
echo "=========================================="
echo "Step 4: Connector Configuration File"
echo "=========================================="
echo ""

if [ -f conf/config.json ]; then
    echo "Connector configuration (conf/config.json):"
    cat conf/config.json | jq '.' 2>/dev/null || cat conf/config.json
else
    echo "conf/config.json not found"
fi

echo ""
echo ""

# Step 5: Check if DAPS URLs match
echo "=========================================="
echo "Step 5: DAPS URL Matching"
echo "=========================================="
echo ""

echo "Checking if connector trusts the DAPS that issued your token..."
echo ""

# Get DAPS URL from docker-compose
COMPOSE_DAPS=$(grep -A 5 "connector:" docker-compose.yml | grep "DAPS_URL" | cut -d= -f2 | tr -d ' ')

echo "DAPS URL in docker-compose.yml:     $COMPOSE_DAPS"
echo "DAPS issuer in your token:          $ISSUER"

if [ "$COMPOSE_DAPS" = "$ISSUER" ]; then
    echo ""
    echo -e "${GREEN}✓ MATCH! Connector trusts the DAPS that issued your token${NC}"
    TRUST_MATCH=true
elif [ -z "$COMPOSE_DAPS" ]; then
    echo ""
    echo -e "${YELLOW}⚠ DAPS_URL not found in docker-compose.yml${NC}"
    TRUST_MATCH=false
elif [ -z "$ISSUER" ]; then
    echo ""
    echo -e "${YELLOW}⚠ No token to compare${NC}"
    TRUST_MATCH=false
else
    echo ""
    echo -e "${RED}✗ MISMATCH! Connector trusts different DAPS${NC}"
    TRUST_MATCH=false
fi

echo ""
echo ""

# Step 6: Check JWKS URL (where connector gets public keys to verify tokens)
echo "=========================================="
echo "Step 6: JWKS Configuration"
echo "=========================================="
echo ""

JWKS_URL=$(grep -A 10 "connector:" docker-compose.yml | grep -i "jwks\|key_url" | head -1 | cut -d= -f2 | tr -d ' ')

echo "JWKS URL configured: $JWKS_URL"
echo ""

if [ ! -z "$JWKS_URL" ]; then
    echo "Testing if JWKS is accessible..."
    JWKS_RESPONSE=$(curl -k -s "$JWKS_URL" 2>/dev/null)

    if echo "$JWKS_RESPONSE" | grep -q "keys"; then
        echo -e "${GREEN}✓ JWKS endpoint is accessible${NC}"
        echo ""
        echo "Public keys available for token verification:"
        echo "$JWKS_RESPONSE" | jq -r '.keys[] | "  Key ID: " + (.kid // "N/A")' 2>/dev/null
    else
        echo -e "${YELLOW}⚠ JWKS endpoint not accessible or invalid${NC}"
    fi
else
    echo -e "${YELLOW}⚠ JWKS URL not configured${NC}"
fi

echo ""
echo ""

# Step 7: Check validation setting
echo "=========================================="
echo "Step 7: Incoming Token Validation"
echo "=========================================="
echo ""

VALIDATE_INCOMING=$(docker compose exec connector env 2>/dev/null | grep "DAPS_VALIDATE_INCOMING" | cut -d= -f2)

echo "DAPS_VALIDATE_INCOMING setting: $VALIDATE_INCOMING"
echo ""

if [ "$VALIDATE_INCOMING" = "true" ]; then
    echo -e "${GREEN}✓ Connector is configured to validate incoming tokens${NC}"
    VALIDATION_ENABLED=true
elif [ "$VALIDATE_INCOMING" = "false" ]; then
    echo -e "${YELLOW}⚠ Connector is NOT validating incoming tokens${NC}"
    echo "  This means tokens are accepted without verification!"
    VALIDATION_ENABLED=false
else
    echo -e "${YELLOW}⚠ DAPS_VALIDATE_INCOMING not set (check default)${NC}"
    VALIDATION_ENABLED=false
fi

echo ""
echo ""

# Final Verdict
echo "=========================================="
echo "FINAL VERDICT"
echo "=========================================="
echo ""

echo "Is test-client a valid dataspace participant?"
echo ""

# Check all conditions
CONDITIONS_MET=0
CONDITIONS_TOTAL=4

echo "Checklist:"
echo ""

# Condition 1: Client registered in DAPS
if [ -f config/clients.yml ] && grep -q "test-client" config/clients.yml; then
    echo -e "${GREEN}✓ 1. test-client is registered in DAPS${NC}"
    CONDITIONS_MET=$((CONDITIONS_MET + 1))
else
    echo -e "${RED}✗ 1. test-client NOT registered in DAPS${NC}"
fi

# Condition 2: Can get tokens
if [ -f /tmp/daps-token.txt ]; then
    echo -e "${GREEN}✓ 2. test-client can obtain DAT tokens${NC}"
    CONDITIONS_MET=$((CONDITIONS_MET + 1))
else
    echo -e "${RED}✗ 2. No valid token obtained${NC}"
fi

# Condition 3: Connector trusts issuing DAPS
if $TRUST_MATCH; then
    echo -e "${GREEN}✓ 3. Connector trusts the DAPS that issued the token${NC}"
    CONDITIONS_MET=$((CONDITIONS_MET + 1))
else
    echo -e "${RED}✗ 3. DAPS trust mismatch or not configured${NC}"
fi

# Condition 4: Token validation enabled
if $VALIDATION_ENABLED; then
    echo -e "${GREEN}✓ 4. Connector validates incoming tokens${NC}"
    CONDITIONS_MET=$((CONDITIONS_MET + 1))
else
    echo -e "${YELLOW}⚠ 4. Token validation disabled (might still work)${NC}"
    # Don't count this as failure, just warning
    CONDITIONS_MET=$((CONDITIONS_MET + 1))
fi

echo ""
echo "Score: $CONDITIONS_MET/$CONDITIONS_TOTAL conditions met"
echo ""

if [ $CONDITIONS_MET -eq $CONDITIONS_TOTAL ]; then
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✓✓✓ YES - test-client IS a valid participant! ✓✓✓${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "Your test-client:"
    echo "  ✓ Is registered in DAPS"
    echo "  ✓ Can authenticate and get tokens"
    echo "  ✓ Tokens are issued by trusted DAPS"
    echo "  ✓ Will be recognized by other connectors in this dataspace"
    echo ""
    echo -e "${GREEN}Other connectors that trust $ISSUER will accept${NC}"
    echo -e "${GREEN}your tokens and recognize you as legitimate!${NC}"
elif [ $CONDITIONS_MET -ge 3 ]; then
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}MOSTLY VALID - Minor issues to address${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "test-client is mostly valid, but check the failures above."
else
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}NOT VALID - Issues need to be resolved${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "test-client is NOT a valid participant yet."
    echo "Resolve the issues marked with ✗ above."
fi

echo ""
echo ""

# Recommendations
echo "=========================================="
echo "What This Means"
echo "=========================================="
echo ""

if [ $CONDITIONS_MET -eq $CONDITIONS_TOTAL ]; then
    echo "When you send your DAPS token to another connector:"
    echo ""
    echo "1. The connector will verify the token signature using"
    echo "   DAPS public keys from: $JWKS_URL"
    echo ""
    echo "2. It will check that the issuer is: $ISSUER"
    echo ""
    echo "3. If both match → You are ACCEPTED as a valid participant"
    echo ""
    echo "4. You can then exchange data, access resources, etc."
else
    echo "To become a valid participant:"
    echo ""

    if ! $TRUST_MATCH; then
        echo "• Fix DAPS URL mismatch"
        echo "  - Update docker-compose.yml to use: $ISSUER"
        echo "  - Or get token from: $COMPOSE_DAPS"
    fi

    if [ ! -f /tmp/daps-token.txt ]; then
        echo "• Get a valid token:"
        echo "  ./scripts/fix-daps-client.sh"
    fi
fi

echo ""
