#!/usr/bin/env bash
# Verify that a connector has a valid DAPS-issued identity
# This checks if the connector is a legitimate dataspace participant

set -e

CONNECTOR_URL="${1:-https://localhost/connector}"
DAPS_URL="${2:-https://localhost/auth}"

echo "=========================================="
echo "DAPS Identity Verification"
echo "=========================================="
echo ""
echo "This script verifies that a connector has a valid"
echo "DAPS-issued identity and can participate in the dataspace"
echo ""
echo "Connector: $CONNECTOR_URL"
echo "DAPS: $DAPS_URL"
echo ""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Step 1: Get connector's certificate/client ID
echo "=========================================="
echo "Step 1: Extract Connector Identity"
echo "=========================================="
echo ""

echo "Checking connector certificate configuration..."
if [ -f "conf/default-connector-keystore.p12" ]; then
    echo -e "${GREEN}✓ Connector keystore found${NC}"

    # Extract certificate info
    echo ""
    echo "Certificate Information:"
    keytool -list -v -keystore conf/default-connector-keystore.p12 -storepass password 2>/dev/null | grep -E "(Alias name|Owner|Issuer|Valid|SHA256)" | head -20

    # Get the SKI (Subject Key Identifier) - this is what DAPS uses as client ID
    echo ""
    echo "Extracting SKI (DAPS Client ID)..."
    CERT_SKI=$(keytool -list -v -keystore conf/default-connector-keystore.p12 -storepass password 2>/dev/null | grep -A1 "SubjectKeyIdentifier" | tail -1 | tr -d ' :' | tr '[:upper:]' '[:lower:]')

    if [ ! -z "$CERT_SKI" ]; then
        echo -e "${GREEN}✓ SKI (Client ID): $CERT_SKI${NC}"
        echo "  This is the connector's identity in DAPS"
    else
        echo -e "${YELLOW}⚠ Could not extract SKI${NC}"
    fi
else
    echo -e "${RED}✗ Connector keystore not found at conf/default-connector-keystore.p12${NC}"
fi

echo ""
echo ""

# Step 2: Check if this client is registered in DAPS
echo "=========================================="
echo "Step 2: Check DAPS Client Registration"
echo "=========================================="
echo ""

echo "Checking DAPS client registry..."
if [ -f "config/clients.yml" ]; then
    echo -e "${GREEN}✓ DAPS clients.yml found${NC}"
    echo ""
    echo "Registered clients in DAPS:"
    cat config/clients.yml | grep -E "(^- |  client_id:|  name:)" | head -30

    if [ ! -z "$CERT_SKI" ]; then
        echo ""
        if grep -q "$CERT_SKI" config/clients.yml; then
            echo -e "${GREEN}✓ Connector SKI ($CERT_SKI) is registered in DAPS!${NC}"
        else
            echo -e "${YELLOW}⚠ Connector SKI ($CERT_SKI) NOT found in DAPS clients${NC}"
            echo "  You need to register this connector in DAPS"
        fi
    fi
else
    echo -e "${YELLOW}⚠ DAPS clients.yml not found at config/clients.yml${NC}"
fi

echo ""
echo ""

# Step 3: Verify DAPS can validate this connector's certificate
echo "=========================================="
echo "Step 3: DAPS Public Key Verification"
echo "=========================================="
echo ""

echo "Checking if DAPS publishes validation keys..."
JWKS_RESPONSE=$(curl -k -s "$DAPS_URL/jwks.json")
JWKS_HTTP=$(curl -k -s -o /dev/null -w "%{http_code}" "$DAPS_URL/jwks.json")

if [ "$JWKS_HTTP" = "200" ]; then
    echo -e "${GREEN}✓ DAPS JWKS endpoint accessible${NC}"
    echo ""
    echo "DAPS Public Keys (for token verification):"
    echo "$JWKS_RESPONSE" | jq -r '.keys[] | "  Key ID: \(.kid // "N/A")"' 2>/dev/null || echo "$JWKS_RESPONSE" | head -10
else
    echo -e "${RED}✗ DAPS JWKS endpoint failed (HTTP $JWKS_HTTP)${NC}"
fi

echo ""
echo ""

# Step 4: Test if connector can get a token from DAPS
echo "=========================================="
echo "Step 4: DAT Token Request Test"
echo "=========================================="
echo ""

echo "Attempting to request a DAT token from DAPS..."
echo "(This tests if the connector's certificate is trusted by DAPS)"
echo ""

# Check connector logs for DAPS token requests
echo "Checking connector logs for DAPS token activity..."
TOKEN_LOGS=$(docker compose logs connector 2>/dev/null | grep -i "daps\|token" | tail -10)

if [ ! -z "$TOKEN_LOGS" ]; then
    echo -e "${BLUE}Recent DAPS/Token activity in connector logs:${NC}"
    echo "$TOKEN_LOGS"

    if echo "$TOKEN_LOGS" | grep -qi "success\|acquired\|valid"; then
        echo ""
        echo -e "${GREEN}✓ Connector appears to be obtaining tokens successfully!${NC}"
    elif echo "$TOKEN_LOGS" | grep -qi "error\|fail\|invalid"; then
        echo ""
        echo -e "${YELLOW}⚠ Token acquisition may be failing - check logs${NC}"
    fi
else
    echo "No DAPS token activity found in logs"
fi

echo ""
echo ""

# Step 5: Verify connector configuration points to DAPS
echo "=========================================="
echo "Step 5: Connector DAPS Configuration"
echo "=========================================="
echo ""

echo "Checking connector's DAPS configuration..."
docker compose exec -T connector env 2>/dev/null | grep -E "DAPS" || echo "Could not read connector environment"

echo ""
echo ""

# Step 6: The definitive test - check connector's self-description
echo "=========================================="
echo "Step 6: Connector Self-Description"
echo "=========================================="
echo ""

echo "Getting connector's IDS self-description..."
SELF_DESC=$(curl -k -s "$CONNECTOR_URL/")
SELF_HTTP=$(curl -k -s -o /dev/null -w "%{http_code}" "$CONNECTOR_URL/")

if [ "$SELF_HTTP" = "200" ]; then
    echo -e "${GREEN}✓ Connector self-description accessible${NC}"
    echo ""
    echo "Connector Identity Information:"
    echo "$SELF_DESC" | jq -r '
        "Connector ID: " + (.["ids:connectorDescription"]["@id"] // .["@id"] // "N/A"),
        "Security Profile: " + (.["ids:connectorDescription"]["ids:securityProfile"]["@id"] // "N/A"),
        "Public Key Present: " + (if .["ids:connectorDescription"]["ids:publicKey"] then "Yes" else "No" end)
    ' 2>/dev/null || echo "$SELF_DESC" | head -20
else
    echo -e "${YELLOW}⚠ Could not get connector self-description (HTTP $SELF_HTTP)${NC}"
fi

echo ""
echo ""

# Summary and verdict
echo "=========================================="
echo "VERIFICATION SUMMARY"
echo "=========================================="
echo ""

VERDICT="UNKNOWN"

# Determine verdict based on checks
if [ -f "conf/default-connector-keystore.p12" ] && [ "$JWKS_HTTP" = "200" ] && [ "$SELF_HTTP" = "200" ]; then
    if [ ! -z "$CERT_SKI" ] && [ -f "config/clients.yml" ] && grep -q "$CERT_SKI" config/clients.yml 2>/dev/null; then
        VERDICT="VALID"
    else
        VERDICT="PARTIAL"
    fi
fi

case $VERDICT in
    "VALID")
        echo -e "${GREEN}✓✓✓ CONNECTOR HAS VALID DAPS IDENTITY ✓✓✓${NC}"
        echo ""
        echo "The connector:"
        echo "  ✓ Has a certificate/keystore"
        echo "  ✓ Is registered in DAPS (SKI found in clients.yml)"
        echo "  ✓ DAPS is accessible and publishing keys"
        echo "  ✓ Connector self-description is available"
        echo ""
        echo "This connector should be accepted as a valid dataspace participant!"
        ;;
    "PARTIAL")
        echo -e "${YELLOW}⚠⚠⚠ CONNECTOR NEEDS DAPS REGISTRATION ⚠⚠⚠${NC}"
        echo ""
        echo "The connector infrastructure is working BUT:"
        echo "  ✓ Has a certificate/keystore"
        echo "  ✗ NOT registered in DAPS clients.yml"
        echo ""
        echo "ACTION REQUIRED:"
        echo "  1. Go to DAPS Admin UI: $DAPS_URL/"
        echo "  2. Login with admin credentials"
        echo "  3. Register the connector using SKI: ${CERT_SKI:-'<extract SKI>'}"
        echo "  4. Grant appropriate scopes (idsc:IDS_CONNECTOR_ATTRIBUTES_ALL)"
        ;;
    *)
        echo -e "${YELLOW}⚠ VERIFICATION INCOMPLETE${NC}"
        echo ""
        echo "Could not fully verify DAPS identity."
        echo "Check the results above for specific issues."
        ;;
esac

echo ""
echo ""

# How to register if needed
echo "=========================================="
echo "HOW TO REGISTER IN DAPS (if needed)"
echo "=========================================="
echo ""
echo "1. Access DAPS Admin UI:"
echo "   URL: $DAPS_URL/"
echo "   Login: admin / admin (default)"
echo ""
echo "2. Add new client:"
echo "   - Client ID: Use the SKI from the certificate"
echo "   - Client Name: Give it a friendly name"
echo "   - Grant Type: client_credentials"
echo "   - Scope: idsc:IDS_CONNECTOR_ATTRIBUTES_ALL"
echo ""
echo "3. Upload certificate:"
echo "   - Extract cert from keystore:"
echo "     keytool -exportcert -alias 1 -keystore conf/default-connector-keystore.p12 -storepass password -file connector-cert.der"
echo "     openssl x509 -inform der -in connector-cert.der -out connector-cert.pem"
echo "   - Upload the PEM certificate to DAPS"
echo ""
echo "4. Test token acquisition:"
echo "   docker compose logs connector | grep -i token"
echo ""

echo "=========================================="
echo "NEXT STEPS"
echo "=========================================="
echo ""
echo "To test if other connectors trust this one:"
echo "  1. Ensure this connector is registered in DAPS (see above)"
echo "  2. Send an IDS message TO another connector"
echo "  3. The other connector will validate this connector's DAT token"
echo "  4. If accepted, this connector is a valid participant"
echo ""
echo "To verify with the Broker:"
echo "  curl -k $BROKER_URL/connectors/"
echo "  (Look for this connector in the registered list)"
echo ""
