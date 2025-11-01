#!/usr/bin/env bash
# Test connector endpoints with a valid DAPS token

echo "=========================================="
echo "Testing Connector with Valid DAPS Token"
echo "=========================================="
echo ""

# Check if token exists
if [ ! -f /tmp/daps-token.txt ]; then
    echo "Error: No token found at /tmp/daps-token.txt"
    echo "Run ./scripts/fix-daps-client.sh first to get a token"
    exit 1
fi

TOKEN=$(cat /tmp/daps-token.txt)

echo "Token loaded from /tmp/daps-token.txt"
echo "Token (first 50 chars): ${TOKEN:0:50}..."
echo ""

# First, check if connector is even responding
echo "=========================================="
echo "Step 1: Check Connector Accessibility"
echo "=========================================="
echo ""

echo "Testing basic connectivity to connector..."
CONN_TEST=$(curl -k -s -o /dev/null -w "%{http_code}" --connect-timeout 5 https://localhost:8081/ 2>&1)
echo "HTTP Status: $CONN_TEST"

if [ "$CONN_TEST" = "000" ]; then
    echo "⚠ Cannot connect to connector"
    echo ""
    echo "Checking if connector is running..."
    docker compose ps connector
    echo ""
    echo "Connector logs (last 20 lines):"
    docker compose logs connector | tail -20
    exit 1
fi

echo "✓ Connector is responding"
echo ""

# Test without token (should get 401 or similar)
echo "=========================================="
echo "Step 2: Test WITHOUT Token (Baseline)"
echo "=========================================="
echo ""

echo "Testing /api/offers without authentication..."
NO_AUTH_RESPONSE=$(curl -k -s -w "\nHTTP_CODE:%{http_code}\nTIME:%{time_total}s\n" https://localhost:8081/api/offers 2>&1)
echo "$NO_AUTH_RESPONSE"
echo ""

# Test with invalid token
echo "=========================================="
echo "Step 3: Test With INVALID Token"
echo "=========================================="
echo ""

echo "Testing with a fake token..."
INVALID_RESPONSE=$(curl -k -s -w "\nHTTP_CODE:%{http_code}\nTIME:%{time_total}s\n" \
    -H "Authorization: Bearer FAKE_INVALID_TOKEN" \
    https://localhost:8081/api/offers 2>&1)
echo "$INVALID_RESPONSE"
echo ""

# Test with valid token (verbose)
echo "=========================================="
echo "Step 4: Test With VALID Token (Verbose)"
echo "=========================================="
echo ""

echo "Testing with valid DAPS token (verbose mode)..."
echo ""

curl -k -v -H "Authorization: Bearer $TOKEN" https://localhost:8081/api/offers 2>&1

echo ""
echo ""

# Test with valid token (with timeout and status)
echo "=========================================="
echo "Step 5: Test With VALID Token (Detailed)"
echo "=========================================="
echo ""

echo "Testing with timeout and detailed output..."
VALID_RESPONSE=$(curl -k -s -w "\n---\nHTTP_CODE:%{http_code}\nCONTENT_TYPE:%{content_type}\nTIME_TOTAL:%{time_total}s\nSIZE:%{size_download} bytes\n" \
    --max-time 30 \
    -H "Authorization: Bearer $TOKEN" \
    https://localhost:8081/api/offers 2>&1)

echo "$VALID_RESPONSE"
echo ""

# Extract just the HTTP code
HTTP_CODE=$(echo "$VALID_RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)

echo ""
echo "Result: HTTP $HTTP_CODE"
echo ""

# Analyze the result
case $HTTP_CODE in
    200)
        echo "✓✓✓ SUCCESS! Authenticated access granted"
        echo ""
        echo "This proves:"
        echo "  ✓ Connector is validating DAPS tokens"
        echo "  ✓ Your token is valid and accepted"
        echo "  ✓ Connector is a valid dataspace participant"
        ;;
    401)
        echo "⚠ Still getting 401 Unauthorized"
        echo "This might mean:"
        echo "  - Token is not being sent correctly"
        echo "  - Connector doesn't recognize the token format"
        echo "  - Check connector logs for details"
        ;;
    403)
        echo "⚠ Getting 403 Forbidden"
        echo "This might mean:"
        echo "  - Token is valid but insufficient permissions"
        echo "  - Connector validated but rejected the token"
        echo "  - Check required scopes"
        ;;
    000)
        echo "⚠ No response (timeout or connection issue)"
        echo "This might mean:"
        echo "  - Request is hanging"
        echo "  - Connector is processing but slow"
        echo "  - Network issue"
        ;;
    *)
        echo "⚠ Unexpected HTTP code: $HTTP_CODE"
        ;;
esac

echo ""

# Check connector logs for this request
echo "=========================================="
echo "Step 6: Check Connector Logs"
echo "=========================================="
echo ""

echo "Recent connector logs (looking for authentication/token activity):"
docker compose logs connector 2>/dev/null | grep -i "token\|auth\|bearer\|401\|403" | tail -20

echo ""
echo ""

# Test other endpoints
echo "=========================================="
echo "Step 7: Test Other Endpoints"
echo "=========================================="
echo ""

ENDPOINTS=(
    "/api/offers"
    "/api/resources"
    "/api/catalogs"
    "/"
)

for endpoint in "${ENDPOINTS[@]}"; do
    echo "Testing $endpoint with valid token..."
    HTTP=$(curl -k -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $TOKEN" https://localhost:8081$endpoint)
    echo "  HTTP $HTTP"
done

echo ""
echo ""

# Summary
echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""

echo "If you got HTTP 200 on any endpoint, DAPS validation is working!"
echo "If all endpoints return nothing or timeout, there may be an issue"
echo "with how the connector is processing the token."
echo ""
echo "Next steps:"
echo "  1. Check connector logs: docker compose logs connector"
echo "  2. Try direct port: curl -k -H \"Authorization: Bearer \$TOKEN\" https://localhost:8081/api/offers"
echo "  3. Try via nginx: curl -k -H \"Authorization: Bearer \$TOKEN\" https://localhost/connector/api/offers"
echo ""
