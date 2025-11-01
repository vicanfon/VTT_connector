#!/usr/bin/env bash
# Test connector REST API endpoints with Basic Authentication

echo "========================================"
echo "Testing Connector REST API"
echo "========================================"
echo ""
echo "Using Basic Authentication (admin:password)"
echo ""

# Test 1: Connector self-description
echo "Test 1: GET /api/connector (self-description)"
echo "--------------------------------------"
RESPONSE=$(curl -k -s -w "\nHTTP_STATUS:%{http_code}\n" \
    -u admin:password \
    https://localhost:8081/api/connector)

HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS:" | cut -d: -f2)
echo "HTTP Status: $HTTP_STATUS"
echo ""

if [ "$HTTP_STATUS" = "200" ]; then
    echo "✓ SUCCESS - Connector endpoint accessible with Basic Auth"
    echo ""
    echo "Response (first 500 chars):"
    echo "$RESPONSE" | grep -v "HTTP_STATUS:" | head -c 500
    echo "..."
else
    echo "✗ FAILED - Status $HTTP_STATUS"
    echo "$RESPONSE" | grep -v "HTTP_STATUS:"
fi

echo ""
echo ""

# Test 2: List offers
echo "Test 2: GET /api/offers"
echo "--------------------------------------"
RESPONSE2=$(curl -k -s -w "\nHTTP_STATUS:%{http_code}\n" \
    -u admin:password \
    https://localhost:8081/api/offers)

HTTP_STATUS2=$(echo "$RESPONSE2" | grep "HTTP_STATUS:" | cut -d: -f2)
echo "HTTP Status: $HTTP_STATUS2"
echo ""

if [ "$HTTP_STATUS2" = "200" ]; then
    echo "✓ SUCCESS - Offers endpoint accessible"
    echo ""
    OFFER_COUNT=$(echo "$RESPONSE2" | grep -v "HTTP_STATUS:" | jq '._embedded.resources | length' 2>/dev/null)
    if [ -n "$OFFER_COUNT" ] && [ "$OFFER_COUNT" != "null" ]; then
        echo "Found $OFFER_COUNT offer(s)"
    else
        echo "Response:"
        echo "$RESPONSE2" | grep -v "HTTP_STATUS:" | head -20
    fi
else
    echo "✗ FAILED - Status $HTTP_STATUS2"
fi

echo ""
echo ""

# Test 3: List resources
echo "Test 3: GET /api/resources"
echo "--------------------------------------"
RESPONSE3=$(curl -k -s -w "\nHTTP_STATUS:%{http_code}\n" \
    -u admin:password \
    https://localhost:8081/api/resources)

HTTP_STATUS3=$(echo "$RESPONSE3" | grep "HTTP_STATUS:" | cut -d: -f2)
echo "HTTP Status: $HTTP_STATUS3"
echo ""

if [ "$HTTP_STATUS3" = "200" ]; then
    echo "✓ SUCCESS - Resources endpoint accessible"
else
    echo "✗ FAILED - Status $HTTP_STATUS3"
fi

echo ""
echo ""

# Summary
echo "========================================"
echo "Summary"
echo "========================================"
echo ""

if [ "$HTTP_STATUS" = "200" ]; then
    echo "✓ The connector REST API is accessible with Basic Auth"
    echo ""
    echo "Credentials that work:"
    echo "  Username: admin"
    echo "  Password: password"
    echo ""
    echo "These endpoints use Basic Authentication, NOT DAPS tokens."
    echo ""
    echo "Example usage:"
    echo "  curl -k -u admin:password https://localhost:8081/api/connector"
    echo "  curl -k -u admin:password https://localhost:8081/api/offers"
    echo "  curl -k -u admin:password https://localhost:8081/api/resources"
    echo ""
    echo "Note: These endpoints do NOT validate participant tokens."
    echo "They are for managing the connector itself, not for validating"
    echo "other participants' tokens."
else
    echo "✗ Basic Authentication failed"
    echo ""
    echo "The credentials admin:password did not work."
    echo "Check docker-compose logs for authentication errors."
fi

echo ""
