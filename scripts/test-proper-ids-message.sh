#!/usr/bin/env bash
# Test token validation with PROPERLY FORMATTED IDS message

TOKEN="${1}"

if [ -z "$TOKEN" ]; then
    echo "Usage: $0 <token>"
    echo ""
    echo "Example:"
    echo "  $0 \"\$(cat /tmp/daps-token.txt)\""
    exit 1
fi

echo "Testing token with properly formatted IDS message..."
echo ""

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
MSG_ID="https://w3id.org/idsa/autogen/descriptionRequestMessage/$(date +%s)"

# Create COMPLETE IDS message with ALL required fields
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
    "@id": "https://test-connector/connector"
  },
  "ids:senderAgent": {
    "@id": "https://test-connector/agent"
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

echo "Sending properly formatted IDS message to connector..."
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
    echo "⚠ MALFORMED_MESSAGE"
    echo "Message format still rejected (this shouldn't happen with all fields)"
    exit 2
else
    echo "? Unknown response"
    exit 2
fi
