#!/usr/bin/env bash
# Simple token validation: call connector endpoint with token
# If accepted → VALID, if rejected → INVALID

TOKEN="$1"
CONNECTOR_URL="${2:-https://localhost:8081}"

if [ -z "$TOKEN" ]; then
    echo "Usage: $0 <token> [connector_url]"
    exit 1
fi

echo "Testing token against connector..."

# Try the self-description endpoint with the token
RESPONSE=$(curl -k -s -w "\nHTTP_CODE:%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    "$CONNECTOR_URL/api/connector")

HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)

if [ "$HTTP_CODE" = "200" ]; then
    echo "✓ TOKEN IS VALID"
    echo "The connector accepted the token"
    exit 0
elif [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
    echo "✗ TOKEN IS INVALID"
    echo "The connector rejected the token (HTTP $HTTP_CODE)"
    exit 1
else
    echo "? INCONCLUSIVE (HTTP $HTTP_CODE)"
    echo "$RESPONSE" | grep -v "HTTP_CODE:"
    exit 2
fi
