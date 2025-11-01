#!/usr/bin/env bash
# Test with EMBEDDED JSON-LD context (no remote fetch needed)

TOKEN="${1}"

if [ -z "$TOKEN" ]; then
    echo "Usage: $0 <token>"
    exit 1
fi

echo "Testing with embedded JSON-LD context (no remote fetch)..."
echo ""

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
MSG_ID="https://w3id.org/idsa/autogen/descriptionRequestMessage/$(date +%s)"

# Use inline/embedded context instead of remote URL
IDS_MESSAGE=$(cat <<'EOF'
{
  "@context": {
    "ids": "https://w3id.org/idsa/core/",
    "idsc": "https://w3id.org/idsa/code/"
  },
  "@type": "ids:DescriptionRequestMessage",
  "@id": "MSG_ID_PLACEHOLDER",
  "ids:modelVersion": "4.2.7",
  "ids:issued": {
    "@value": "TIMESTAMP_PLACEHOLDER",
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
    "ids:tokenValue": "TOKEN_PLACEHOLDER",
    "ids:tokenFormat": {
      "@id": "idsc:JWT"
    }
  }
}
EOF
)

# Replace placeholders
IDS_MESSAGE="${IDS_MESSAGE//MSG_ID_PLACEHOLDER/$MSG_ID}"
IDS_MESSAGE="${IDS_MESSAGE//TIMESTAMP_PLACEHOLDER/$TIMESTAMP}"
IDS_MESSAGE="${IDS_MESSAGE//TOKEN_PLACEHOLDER/$TOKEN}"

echo "Sending message with embedded context..."
echo ""

RESPONSE=$(curl -k -s -X POST "https://localhost:8081/api/ids/data" \
    -F "header=$IDS_MESSAGE;type=application/json")

echo "Response:"
echo "$RESPONSE"
echo ""

# Analyze response
if echo "$RESPONSE" | grep -q "DescriptionResponseMessage"; then
    echo "✓✓✓ TOKEN IS VALID ✓✓✓"
    echo "Connector accepted the token!"
    exit 0
elif echo "$RESPONSE" | grep -q "NOT_AUTHENTICATED"; then
    echo "✗✗✗ TOKEN IS INVALID ✗✗✗"
    echo "Connector rejected: NOT_AUTHENTICATED"
    exit 1
elif echo "$RESPONSE" | grep -q "NOT_AUTHORIZED"; then
    echo "✗✗✗ TOKEN IS INVALID ✗✗✗"
    echo "Connector rejected: NOT_AUTHORIZED"
    exit 1
elif echo "$RESPONSE" | grep -q "MALFORMED_MESSAGE"; then
    echo "⚠ Still MALFORMED_MESSAGE"
    echo "Check logs: docker compose logs connector --tail=20"
    exit 2
else
    echo "? Unknown response"
    exit 2
fi
