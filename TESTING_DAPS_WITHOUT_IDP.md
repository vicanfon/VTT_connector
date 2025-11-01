# Testing DAPS Validation Without Connecting to IdP

This guide explains how to verify that a connector has valid DAPS registration **without directly connecting to the DAPS IdP**. Instead, we test the connector's own endpoints to prove DAPS validation is working.

## The Strategy

The key insight is: **If a connector properly validates DAPS tokens, its protected endpoints will reject unauthorized requests.**

By calling the connector's API endpoints:
- **401/403 responses** = Connector is enforcing DAPS authentication ✅
- **200 responses without auth** = Endpoint is public or DAPS not enforced ⚠️

## Quick Test

```bash
# Run the automated DAPS validation test
./scripts/test-daps-validation.sh

# Or test a specific connector
./scripts/test-daps-validation.sh https://other-connector.example.com
```

This script will:
1. Query the OpenAPI spec to find endpoints
2. Test endpoints without authentication
3. Identify which ones require DAPS validation
4. Provide a clear verdict on DAPS enforcement

## Manual Testing Approach

### Step 1: Find Available Endpoints

```bash
# Get the OpenAPI spec
curl -k https://localhost:8081/v3/api-docs | jq '.paths | keys'

# Common endpoints to test:
# - /api/offers
# - /api/resources
# - /api/catalogs
# - /api/agreements
# - /api/contracts
# - /api/ids/data
```

### Step 2: Test Without Authentication

Try calling endpoints **without** providing any authentication:

```bash
# Test offers endpoint
curl -k -w "\nHTTP: %{http_code}\n" https://localhost:8081/api/offers

# Test resources endpoint
curl -k -w "\nHTTP: %{http_code}\n" https://localhost:8081/api/resources

# Test IDS protocol endpoint
curl -k -w "\nHTTP: %{http_code}\n" -X POST https://localhost:8081/api/ids/data
```

**Interpret the responses:**

| HTTP Code | Meaning | DAPS Status |
|-----------|---------|-------------|
| **401** | Unauthorized - Authentication required | ✅ **DAPS validation active** |
| **403** | Forbidden - Authentication failed | ✅ **DAPS validation active** |
| **400** | Bad request - Wrong format | ℹ️ Endpoint exists, may need proper format |
| **415** | Unsupported media type | ℹ️ IDS endpoint needs multipart format |
| **200** | Success | ⚠️ Public endpoint OR DAPS not enforced |
| **404** | Not found | Endpoint doesn't exist |

### Step 3: Test With Invalid Authentication

Try with a fake/invalid token:

```bash
curl -k -w "\nHTTP: %{http_code}\n" \
  -H "Authorization: Bearer FAKE_TOKEN" \
  https://localhost:8081/api/offers
```

**Expected result if DAPS is working:**
- **403 Forbidden** - The connector validated the token and rejected it ✅

**If you get 200 OK:**
- Either the endpoint doesn't require auth, OR
- DAPS validation is not properly enforced ⚠️

### Step 4: The Definitive Test - IDS Protocol Endpoint

The `/api/ids/data` endpoint is the main IDS protocol endpoint and **must** validate DAPS tokens in production:

```bash
# Test with a multipart IDS message (no valid token)
curl -k -X POST https://localhost:8081/api/ids/data \
  -F 'header={"@type":"ids:DescriptionRequestMessage","@id":"test"};type=application/json'
```

**Look for the response:**

If you get an **IDS RejectionMessage** with `ids:rejectionReason`, this means:
- ✅ Connector is processing IDS messages
- ✅ Connector is validating message structure
- ✅ IDS protocol is active

Common rejection reasons:
- `MALFORMED_MESSAGE` - Message format issue (endpoint is working)
- `NOT_AUTHENTICATED` - Authentication missing/invalid (DAPS validation active!)
- `NOT_AUTHORIZED` - Authentication valid but insufficient permissions

## Understanding the Results

### Scenario 1: Protected Endpoints (DAPS Working) ✅

```bash
$ curl -k https://localhost:8081/api/offers
HTTP 401 Unauthorized

$ curl -k -H "Authorization: Bearer fake" https://localhost:8081/api/offers
HTTP 403 Forbidden
```

**Verdict:** DAPS validation is active! The connector:
- Requires authentication for protected endpoints
- Validates provided tokens
- This connector is properly checking DAPS credentials

### Scenario 2: Public Endpoints (May Be Normal) ℹ️

```bash
$ curl -k https://localhost:8081/api/offers
HTTP 200 OK
[... list of offers ...]
```

**Verdict:** This endpoint is public. This might be intentional:
- Some connectors allow anonymous browsing of offers
- DAPS validation may still be enforced for data access
- Check other endpoints like `/api/agreements` or `/api/artifacts`

### Scenario 3: All Endpoints Public (Warning) ⚠️

```bash
$ curl -k https://localhost:8081/api/offers
HTTP 200 OK

$ curl -k https://localhost:8081/api/resources
HTTP 200 OK

$ curl -k https://localhost:8081/api/agreements
HTTP 200 OK
```

**Verdict:** DAPS validation may not be enforced!
- All endpoints return 200 without auth
- This might be a development/test configuration
- Check if `DAPS_VALIDATE_INCOMING=true` is set

## Advanced: Testing with Valid DAT Token

To **definitively prove** DAPS is working, test with a real DAT token:

### Step 1: Get a DAT Token from DAPS

```bash
# Request token from DAPS
curl -k -X POST https://localhost/auth/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=YOUR_CLIENT_ID" \
  -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
  -d "client_assertion=YOUR_JWT_ASSERTION" \
  -d "scope=idsc:IDS_CONNECTOR_ATTRIBUTES_ALL"
```

This requires:
- Your client to be registered in DAPS
- A certificate for signing the JWT assertion
- See DAPS documentation for full details

### Step 2: Use the Token

```bash
# Extract the token from the response
DAT_TOKEN="<token from above>"

# Call protected endpoint WITH valid token
curl -k -H "Authorization: Bearer $DAT_TOKEN" \
  https://localhost:8081/api/offers
```

**Expected results:**
- **Without token:** 401 Unauthorized
- **With fake token:** 403 Forbidden
- **With valid token:** 200 OK ✅

If this pattern works → **DAPS validation is fully functional!**

## Checking Specific DAPS Configuration

### Check Environment Variables

```bash
# See how connector is configured for DAPS
docker compose exec connector env | grep DAPS

# Should show:
# DAPS_URL=https://localhost/auth
# DAPS_TOKEN_URL=https://localhost/auth/token
# DAPS_KEY_URL=https://localhost/auth/jwks.json
# DAPS_VALIDATE_INCOMING=true  (important!)
```

### Check Connector Logs

```bash
# Look for DAPS validation activity
docker compose logs connector | grep -i "daps\|token\|validat"

# Look for:
# - "Validating DAT token"
# - "Token validation successful"
# - "Token validation failed"
# - "DAPS validation enabled"
```

## Practical Validation Methods

### Method 1: Use the Provider UI

```bash
# Access Provider UI
http://localhost:8091

# Try to:
# 1. Publish a resource
# 2. Create an offer
# 3. Register with broker

# If these work, DAPS must be functioning
```

### Method 2: Query the Broker

```bash
# Check if connector is registered in broker
curl -k https://localhost/broker/connectors/

# If your connector appears in the list:
# ✅ It successfully authenticated with the broker via DAPS
# ✅ Broker validated its DAT token
# ✅ Connector is a valid dataspace participant
```

### Method 3: Test Consumer Flow

```bash
# Access Consumer UI
http://localhost:8092

# Try to:
# 1. Query broker for connectors
# 2. Browse offers from other connectors
# 3. Request data

# If you can see and interact with other connectors:
# ✅ Your connector has valid DAPS credentials
```

## Troubleshooting

### Issue: All endpoints return 200 (no auth required)

**Possible causes:**
1. DAPS validation disabled in development mode
2. `DAPS_VALIDATE_INCOMING=false` in environment
3. Security bypassed for testing

**Check:**
```bash
docker compose exec connector env | grep DAPS_VALIDATE
```

**Fix:**
Set `DAPS_VALIDATE_INCOMING=true` in docker-compose.yml

### Issue: All endpoints return 403 (even with valid token)

**Possible causes:**
1. DAPS URL misconfigured
2. Connector can't reach DAPS to validate tokens
3. DAPS JWKS keys not accessible

**Check:**
```bash
# Can connector reach DAPS?
docker compose exec connector curl -k https://daps:4567/jwks.json

# Check logs for DAPS connection errors
docker compose logs connector | grep -i "daps\|error"
```

### Issue: Endpoints return 500 (internal server error)

**Possible causes:**
1. DAPS configuration incomplete
2. Keystore/certificate issues
3. Internal connector error

**Check:**
```bash
# View full error details
docker compose logs connector | tail -50

# Check if keystore is loaded
docker compose logs connector | grep -i "keystore\|certificate"
```

## Summary: The Key Indicators

A connector with valid DAPS registration will show:

| Indicator | What It Means |
|-----------|---------------|
| **Protected endpoints return 401** | Authentication is required ✅ |
| **Invalid tokens return 403** | Token validation is working ✅ |
| **Valid tokens return 200** | DAPS trust is established ✅ |
| **IDS messages include DAT tokens** | Connector has DAPS credentials ✅ |
| **Appears in broker catalog** | Successfully authenticated with broker ✅ |
| **Logs show token validation** | DAPS integration is active ✅ |

## Quick Reference Commands

```bash
# Test endpoint protection
curl -k -w "\nHTTP: %{http_code}\n" https://localhost:8081/api/offers

# Test with invalid token
curl -k -w "\nHTTP: %{http_code}\n" \
  -H "Authorization: Bearer INVALID" \
  https://localhost:8081/api/offers

# Check DAPS configuration
docker compose exec connector env | grep DAPS

# View validation logs
docker compose logs connector | grep -i "validat"

# Check broker registration
curl -k https://localhost/broker/connectors/ | jq

# Run comprehensive test
./scripts/test-daps-validation.sh
```

## Conclusion

You **don't need to connect to DAPS directly** to verify a connector is properly registered. Instead:

1. ✅ Test the connector's protected endpoints
2. ✅ Verify they require authentication (401/403)
3. ✅ Check for token validation in logs
4. ✅ Confirm registration in broker catalog

If protected endpoints reject unauthorized requests and accept valid tokens, the connector is properly validating DAPS credentials and is a legitimate dataspace participant!
