#!/usr/bin/env bash
# Final simple test with embedded context

TOKEN="$1"

if [ -z "$TOKEN" ]; then
    echo "Usage: $0 <token>"
    echo ""
    echo "Get token first:"
    echo '  curl -k -s -X POST https://localhost/auth/token \'
    echo '    -H "Content-Type: application/x-www-form-urlencoded" \'
    echo '    -d "grant_type=client_credentials" \'
    echo '    -d "client_id=test-client" \'
    echo '    -d "client_secret=test-secret-123" \'
    echo '    -d "scope=idsc:IDS_CONNECTOR_ATTRIBUTES_ALL" \'
    echo '  | jq -r ".access_token"'
    exit 1
fi

echo "========================================"
echo "Testing Token with Connector"
echo "========================================"
echo ""
echo "Token (first 50 chars): ${TOKEN:0:50}..."
echo ""

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
MSG_ID="https://w3id.org/idsa/autogen/descriptionRequestMessage/$(date +%s)"

# Message with embedded context (proven to work past JSON-LD parsing)
IDS_MESSAGE=$(cat <<EOF
{
  "@context": {
    "ids": "https://w3id.org/idsa/core/",
    "idsc": "https://w3id.org/idsa/code/"
  },
  "@type": "ids:DescriptionRequestMessage",
  "@id": "$MSG_ID",
  "ids:modelVersion": "4.2.7",
  "ids:issued": {
    "@value": "$TIMESTAMP",
    "@type": "http://www.w3.org/2001/XMLSchema#dateTimeStamp"
  },
  "ids:issuerConnector": {
    "@id": "https://test-client/connector"
  },
  "ids:senderAgent": {
    "@id": "https://test-client/agent"
  },
  "ids:securityToken": {
    "@type": "ids:DynamicAttributeToken",
    "@id": "https://w3id.org/idsa/autogen/dynamicAttributeToken/test",
    "ids:tokenValue": "$TOKEN",
    "ids:tokenFormat": {
      "@id": "idsc:JWT"
    }
  }
}
EOF
)

echo "Sending IDS message to connector..."
echo ""

RESPONSE=$(curl -k -s -w "\nHTTP_STATUS:%{http_code}\n" -X POST "https://localhost:8081/api/ids/data" \
    -F "header=$IDS_MESSAGE;type=application/json")

HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS:" | cut -d: -f2)

echo "HTTP Status: $HTTP_STATUS"
echo ""
echo "Response:"
echo "$RESPONSE" | grep -v "HTTP_STATUS:"
echo ""
echo "========================================"
echo "Analysis"
echo "========================================"
echo ""

if echo "$RESPONSE" | grep -q "DescriptionResponseMessage"; then
    echo "✓✓✓ TOKEN IS VALID ✓✓✓"
    echo ""
    echo "The connector ACCEPTED the token!"
    echo "This means:"
    echo "  - Token signature is valid"
    echo "  - Token is not expired"
    echo "  - Token issuer is trusted"
    echo ""
    echo "Result: PARTICIPANT IS LEGITIMATE"
    exit 0
elif echo "$RESPONSE" | grep -q "NOT_AUTHENTICATED"; then
    echo "✗✗✗ TOKEN IS INVALID ✗✗✗"
    echo ""
    echo "Rejection reason: NOT_AUTHENTICATED"
    echo "This means the token failed DAPS validation"
    echo ""
    echo "Result: PARTICIPANT IS NOT LEGITIMATE"
    exit 1
elif echo "$RESPONSE" | grep -q "NOT_AUTHORIZED"; then
    echo "✗✗✗ TOKEN IS INVALID ✗✗✗"
    echo ""
    echo "Rejection reason: NOT_AUTHORIZED"
    echo "Token was validated but insufficient permissions"
    echo ""
    echo "Result: PARTICIPANT IS NOT LEGITIMATE"
    exit 1
elif echo "$RESPONSE" | grep -q "MALFORMED_MESSAGE"; then
    echo "⚠ MALFORMED_MESSAGE"
    echo ""
    echo "Message format issue (not token validity)"
    echo "This is inconclusive for token validation"
    echo ""
    echo "Check logs: docker compose logs connector --tail=30"
    exit 2
elif echo "$RESPONSE" | grep -q '"message"'; then
    echo "⚠ Generic error response"
    echo ""
    echo "The connector returned a generic error."
    echo "This might indicate an internal connector issue."
    echo ""
    echo "To debug, check the FULL connector logs:"
    echo "  docker compose logs connector --tail=100 | less"
    echo ""
    echo "Look for exceptions or ERROR messages that occurred"
    echo "at approximately: $(date)"
    exit 2
else
    echo "? Unknown response format"
    exit 2
fi
