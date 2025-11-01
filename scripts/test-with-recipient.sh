#!/usr/bin/env bash
# Test with recipientConnector matching the actual connector

TOKEN="${1}"

if [ -z "$TOKEN" ]; then
    echo "Usage: $0 <token>"
    exit 1
fi

echo "Testing with recipientConnector field..."
echo ""

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
MSG_ID="https://w3id.org/idsa/autogen/descriptionRequestMessage/$(date +%s)"

# Create message with recipientConnector
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
    "@id": "https://test-client/connector"
  },
  "ids:recipientConnector": [{
    "@id": "https://digi4live.collab-cloud.eu/connector/"
  }],
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
  },
  "ids:requestedElement": {
    "@id": "https://digi4live.collab-cloud.eu/connector/"
  }
}
EOF
)

echo "Message:"
echo "$IDS_MESSAGE" | jq '.'
echo ""

RESPONSE=$(curl -k -s -X POST "https://localhost:8081/api/ids/data" \
    -F "header=$IDS_MESSAGE;type=application/json")

echo "Response:"
echo "$RESPONSE"
echo ""

# Check response
if echo "$RESPONSE" | grep -q "DescriptionResponseMessage"; then
    echo "✓✓✓ SUCCESS - Token accepted!"
    exit 0
elif echo "$RESPONSE" | grep -q "NOT_AUTHENTICATED"; then
    echo "✗ Token rejected - NOT_AUTHENTICATED"
    exit 1
elif echo "$RESPONSE" | grep -q "MALFORMED_MESSAGE"; then
    echo "⚠ Still getting MALFORMED_MESSAGE"
    echo ""
    echo "Please run: docker compose logs connector --tail=50"
    echo "And look for the specific parsing error"
    exit 2
else
    echo "? Unknown response"
    exit 2
fi
