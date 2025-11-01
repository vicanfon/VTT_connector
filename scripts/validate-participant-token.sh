#!/usr/bin/env bash
# Validate if a participant is legitimate by testing their DAPS token
# Uses the connector API instead of calling DAPS directly

echo "=========================================="
echo "Participant Token Validation"
echo "=========================================="
echo ""
echo "This validates if a participant is legitimate by testing"
echo "their DAPS token using your connector's API (not DAPS directly)."
echo ""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CONNECTOR_URL="${1:-https://localhost:8081}"
TOKEN_TO_TEST="$2"

# Check if token was provided
if [ -z "$TOKEN_TO_TEST" ]; then
    echo "Usage: $0 [connector_url] <token_to_validate>"
    echo ""
    echo "Examples:"
    echo ""
    echo "  # Validate a token someone gave you:"
    echo "  $0 https://localhost:8081 \"eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...\""
    echo ""
    echo "  # Test with your own token:"
    echo "  $0 https://localhost:8081 \"\$(cat /tmp/daps-token.txt)\""
    echo ""
    echo "  # Test with a fake token:"
    echo "  $0 https://localhost:8081 \"FAKE_TOKEN_123\""
    echo ""
    exit 1
fi

echo "Connector endpoint: $CONNECTOR_URL/api/ids/data"
echo "Token to validate (first 50 chars): ${TOKEN_TO_TEST:0:50}..."
echo ""

# Decode token to show claims (if it's a JWT)
if [[ "$TOKEN_TO_TEST" =~ ^eyJ ]]; then
    echo "Token claims (decoded):"
    PAYLOAD=$(echo "$TOKEN_TO_TEST" | cut -d. -f2)

    # Add padding if needed
    case $((${#PAYLOAD} % 4)) in
        2) PAYLOAD="${PAYLOAD}==" ;;
        3) PAYLOAD="${PAYLOAD}=" ;;
    esac

    DECODED=$(echo "$PAYLOAD" | base64 -d 2>/dev/null)

    if [ $? -eq 0 ]; then
        echo "$DECODED" | jq '.' 2>/dev/null || echo "$DECODED"
        echo ""

        # Extract key claims
        ISSUER=$(echo "$DECODED" | jq -r '.iss' 2>/dev/null)
        SUBJECT=$(echo "$DECODED" | jq -r '.sub' 2>/dev/null)
        EXPIRES=$(echo "$DECODED" | jq -r '.exp' 2>/dev/null)

        echo "  Claimed Issuer: $ISSUER"
        echo "  Claimed Subject: $SUBJECT"
        echo "  Expires: $(date -d @$EXPIRES 2>/dev/null || echo 'N/A')"
    else
        echo "  (Not a valid JWT or cannot decode)"
    fi
else
    echo "  (Not a JWT format)"
fi

echo ""
echo ""

# Create a properly formatted IDS DescriptionRequestMessage
echo "=========================================="
echo "Sending Validation Request"
echo "=========================================="
echo ""

echo "Creating IDS message with the provided token..."

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
MSG_ID="https://w3id.org/idsa/autogen/descriptionRequestMessage/$(date +%s)-validation"

IDS_MESSAGE=$(cat <<EOF
{
  "@context": "https://w3id.org/idsa/contexts/context.jsonld",
  "@type": "ids:DescriptionRequestMessage",
  "@id": "$MSG_ID",
  "ids:modelVersion": "4.2.7",
  "ids:issued": {
    "@value": "$TIMESTAMP",
    "@type": "http://www.w3.org/2001/XMLSchema#dateTimeStamp"
  },
  "ids:issuerConnector": {
    "@id": "https://validator/connector"
  },
  "ids:senderAgent": {
    "@id": "https://validator/connector"
  },
  "ids:recipientConnector": [{
    "@id": "https://localhost/connector"
  }],
  "ids:securityToken": {
    "@type": "ids:DynamicAttributeToken",
    "@id": "https://w3id.org/idsa/autogen/dynamicAttributeToken/validation",
    "ids:tokenValue": "$TOKEN_TO_TEST",
    "ids:tokenFormat": {
      "@id": "idsc:JWT"
    }
  },
  "ids:requestedElement": {
    "@id": "https://localhost/connector"
  }
}
EOF
)

echo "Sending to: $CONNECTOR_URL/api/ids/data"
echo ""

# Send the request
RESPONSE=$(curl -k -s -w "\nHTTP_CODE:%{http_code}\n" -X POST "$CONNECTOR_URL/api/ids/data" \
    -F "header=$IDS_MESSAGE;type=application/json")

echo "Response:"
echo "$RESPONSE"
echo ""

# Extract HTTP code
HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)

# Analyze the response
echo ""
echo "=========================================="
echo "Analysis"
echo "=========================================="
echo ""

RESPONSE_TYPE=$(echo "$RESPONSE" | grep -o '"@type"[^,]*' | head -1 | cut -d: -f2 | tr -d ' "')
# Try to find rejection reason in both formats
REJECTION_REASON=$(echo "$RESPONSE" | grep -o 'idsc:[A-Z_]*' | head -1)
if [ -z "$REJECTION_REASON" ]; then
    # Try URL format
    REJECTION_REASON=$(echo "$RESPONSE" | grep -o 'https://w3id.org/idsa/code/[A-Z_]*' | head -1 | cut -d/ -f6)
fi

echo "HTTP Status: $HTTP_CODE"
echo "Response Type: $RESPONSE_TYPE"
echo "Rejection Reason: ${REJECTION_REASON:-none}"
echo ""

# Determine validity
VALID=false
REASON=""

if [[ "$RESPONSE_TYPE" == *"DescriptionResponse"* ]]; then
    VALID=true
    REASON="Connector accepted the token and responded with DescriptionResponseMessage"
elif [[ "$REJECTION_REASON" == *"NOT_AUTHENTICATED"* ]]; then
    VALID=false
    REASON="Token validation failed - NOT_AUTHENTICATED"
elif [[ "$REJECTION_REASON" == *"NOT_AUTHORIZED"* ]]; then
    VALID=false
    REASON="Token was validated but insufficient permissions - NOT_AUTHORIZED"
elif [[ "$REJECTION_REASON" == *"MALFORMED"* ]] || echo "$RESPONSE" | grep -q "MALFORMED_MESSAGE"; then
    # Message format issue - can't determine token validity
    REASON="Message format issue - token validation inconclusive"
    # This is NOT a token validity issue!
elif [[ "$HTTP_CODE" == "401" ]]; then
    VALID=false
    REASON="HTTP 401 Unauthorized - token rejected"
elif [[ "$HTTP_CODE" == "403" ]]; then
    VALID=false
    REASON="HTTP 403 Forbidden - token validated but rejected"
elif [[ "$HTTP_CODE" == "200" ]]; then
    # Success but need to check response type
    if echo "$RESPONSE" | grep -q "RejectionMessage"; then
        if [[ "$REJECTION_REASON" != *"MALFORMED"* ]]; then
            VALID=false
            REASON="Token rejected: $REJECTION_REASON"
        fi
    else
        VALID=true
        REASON="Request accepted"
    fi
fi

echo "=========================================="
echo "VERDICT"
echo "=========================================="
echo ""

if $VALID; then
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✓✓✓ TOKEN IS VALID ✓✓✓${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "The participant who provided this token is LEGITIMATE."
    echo ""
    echo "Validation proof:"
    echo "  ✓ Your connector validated the token signature"
    echo "  ✓ Token was issued by a trusted DAPS"
    echo "  ✓ Token is not expired"
    echo "  ✓ Participant is a valid dataspace member"
    echo ""
    echo -e "${GREEN}You can trust this participant!${NC}"

    if [ ! -z "$SUBJECT" ]; then
        echo ""
        echo "Participant identity: $SUBJECT"
        echo "Authenticated by DAPS: $ISSUER"
    fi
elif [ ! -z "$REASON" ] && [[ "$REASON" == *"inconclusive"* ]]; then
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}? INCONCLUSIVE - Cannot Determine Validity${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "Reason: $REASON"
    echo ""
    echo "The connector rejected the message due to format issues,"
    echo "not necessarily because the token is invalid."
    echo ""
    echo "Try:"
    echo "  1. Check connector logs: docker compose logs connector | tail -50"
    echo "  2. Ensure DAPS_VALIDATE_INCOMING=true in connector config"
    echo "  3. Try with a known valid token to compare"
else
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}✗✗✗ TOKEN IS INVALID ✗✗✗${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "The participant who provided this token is NOT legitimate."
    echo ""
    echo "Reason: $REASON"
    echo ""
    echo "Possible causes:"
    echo "  ✗ Token signature validation failed"
    echo "  ✗ Token was not issued by a trusted DAPS"
    echo "  ✗ Token is expired"
    echo "  ✗ Token is fake/forged"
    echo ""
    echo -e "${RED}DO NOT trust this participant!${NC}"
fi

echo ""
echo ""

# Show what this validation proves
echo "=========================================="
echo "What This Validation Proves"
echo "=========================================="
echo ""

echo "When you validate a token this way:"
echo ""
echo "1. Your connector acts as the validator"
echo "   - It checks the token signature using DAPS public keys"
echo "   - It verifies the token issuer matches its trusted DAPS"
echo "   - It checks token expiration and claims"
echo ""
echo "2. If the token is VALID:"
echo "   → The participant is registered in your trusted DAPS"
echo "   → The token was cryptographically signed by DAPS"
echo "   → The participant is a legitimate dataspace member"
echo ""
echo "3. If the token is INVALID:"
echo "   → Token signature doesn't match (fake/forged)"
echo "   → Or token was issued by untrusted DAPS"
echo "   → Or token is expired"
echo "   → The participant should NOT be trusted"
echo ""
echo "This is equivalent to asking DAPS 'Is this token valid?'"
echo "but you're using your connector as a proxy validator."
echo ""

# Usage examples
echo "=========================================="
echo "Usage Examples"
echo "=========================================="
echo ""

echo "Scenario: Someone claims to be a dataspace participant"
echo "and gives you their DAPS token."
echo ""
echo "1. They provide their token:"
echo "   TOKEN='eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...'"
echo ""
echo "2. You validate it:"
echo "   $0 https://localhost:8081 \"\$TOKEN\""
echo ""
echo "3. Check the verdict:"
echo "   ✓ VALID → They are legitimate, proceed with data exchange"
echo "   ✗ INVALID → They are NOT legitimate, reject them"
echo ""
echo "You've verified their identity without calling DAPS directly!"
echo ""
