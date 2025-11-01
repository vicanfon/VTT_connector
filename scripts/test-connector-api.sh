#!/usr/bin/env bash
# Quick connector API tests

echo "======================================"
echo "Testing Connector REST API Endpoints"
echo "======================================"
echo ""

CONNECTOR_URL="${1:-https://localhost/connector}"

echo "Test 1: Connector Configuration"
echo "--------------------------------"
curl -k -s "$CONNECTOR_URL/api/configuration" | head -20
echo ""
echo ""

echo "Test 2: Connector Offers"
echo "------------------------"
HTTP_CODE=$(curl -k -s -o /tmp/offers.json -w "%{http_code}" "$CONNECTOR_URL/api/offers")
echo "HTTP Status: $HTTP_CODE"
if [ -f /tmp/offers.json ]; then
    cat /tmp/offers.json | head -20
fi
echo ""
echo ""

echo "Test 3: Connector Resources"
echo "----------------------------"
HTTP_CODE=$(curl -k -s -o /tmp/resources.json -w "%{http_code}" "$CONNECTOR_URL/api/resources")
echo "HTTP Status: $HTTP_CODE"
if [ -f /tmp/resources.json ]; then
    cat /tmp/resources.json | head -20
fi
echo ""
echo ""

echo "Test 4: Connector Catalogs"
echo "---------------------------"
HTTP_CODE=$(curl -k -s -o /tmp/catalogs.json -w "%{http_code}" "$CONNECTOR_URL/api/catalogs")
echo "HTTP Status: $HTTP_CODE"
if [ -f /tmp/catalogs.json ]; then
    cat /tmp/catalogs.json | head -20
fi
echo ""
echo ""

echo "Test 5: Connector Self-Description"
echo "-----------------------------------"
curl -k -s "$CONNECTOR_URL/" | head -30
echo ""
echo ""

echo "Test 6: Connector Health (if available)"
echo "----------------------------------------"
curl -k -s "$CONNECTOR_URL/actuator/health" 2>/dev/null || echo "Health endpoint not available or not exposed"
echo ""
echo ""

echo "Test 7: IDS Description Request (Multipart)"
echo "---------------------------------------------"
echo "Testing IDS endpoint with multipart message..."

# Create a proper IDS message
IDS_MESSAGE='{
  "@context": "https://w3id.org/idsa/contexts/context.jsonld",
  "@type": "ids:DescriptionRequestMessage",
  "@id": "https://w3id.org/idsa/autogen/descriptionRequestMessage/test-'"$(date +%s)"'",
  "ids:modelVersion": "4.2.7",
  "ids:issued": {
    "@value": "'"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"'",
    "@type": "http://www.w3.org/2001/XMLSchema#dateTimeStamp"
  },
  "ids:issuerConnector": {
    "@id": "https://localhost/connector"
  },
  "ids:senderAgent": {
    "@id": "https://localhost/connector"
  },
  "ids:securityToken": {
    "@type": "ids:DynamicAttributeToken",
    "@id": "https://w3id.org/idsa/autogen/dynamicAttributeToken/test",
    "ids:tokenValue": "test-token",
    "ids:tokenFormat": {
      "@id": "idsc:JWT"
    }
  }
}'

# Try multipart request
HTTP_CODE=$(curl -k -s -w "\n%{http_code}" -X POST "$CONNECTOR_URL/api/ids/data" \
  -F "header=$IDS_MESSAGE;type=application/json" 2>&1 | tail -1)

echo "HTTP Status: $HTTP_CODE"

case $HTTP_CODE in
  200)
    echo "✓ Success! IDS endpoint accepted the request"
    ;;
  400)
    echo "⚠ Bad Request - Message format issue (but endpoint is working)"
    ;;
  401|403)
    echo "⚠ Authentication required - Need valid DAT token from DAPS"
    ;;
  415)
    echo "⚠ Unsupported Media Type - Multipart format issue"
    ;;
  *)
    echo "Status: $HTTP_CODE"
    ;;
esac

echo ""
echo ""

echo "======================================"
echo "Summary"
echo "======================================"
echo ""
echo "If you see HTTP 200 responses above, your connector is working!"
echo "If you see HTTP 401/403, you need DAPS authentication"
echo "If you see HTTP 415, the message format needs adjustment"
echo ""
echo "Next steps:"
echo "1. Check Swagger docs at: $CONNECTOR_URL/api/docs"
echo "2. Use Provider UI at: http://localhost:8091"
echo "3. Use Consumer UI at: http://localhost:8092"
echo ""
