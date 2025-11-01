# How to Get a Valid DAPS Token

This guide explains how to obtain a valid DAT (Dynamic Attribute Token) from DAPS to test your connector.

## Quick Start

```bash
# Run the token acquisition script
./scripts/get-daps-token.sh

# Or with specific DAPS URL and client ID
./scripts/get-daps-token.sh https://localhost/auth YOUR_CLIENT_ID
```

## Important: Do You Actually Need a Token?

**For testing DAPS validation, you usually DON'T need a valid token!**

Here's why:

```bash
# Test 1: Without any token
curl -k https://localhost:8081/api/offers
# If you get HTTP 401 → DAPS validation IS working! ✅

# Test 2: With a fake token
curl -k -H "Authorization: Bearer FAKE_INVALID_TOKEN" https://localhost:8081/api/offers
# If you get HTTP 403 → Connector validated the token and rejected it! ✅
```

**If you get 401 or 403, that PROVES DAPS validation is active.** You don't need a valid token to confirm this.

## When You DO Need a Valid Token

You need a real DAT token only if you want to:
1. Actually access protected data/resources
2. Test the full end-to-end authentication flow
3. Verify that DAPS accepts your credentials (not just that validation is active)
4. Test as a real connector would operate

## How to Get a DAT Token

### Method 1: Via DAPS Admin UI (Easiest)

1. **Access DAPS Admin UI:**
   ```
   URL: https://localhost/
   Username: admin
   Password: admin
   ```

2. **Register a Client:**
   - Go to "Clients" section
   - Click "Add Client"
   - Fill in:
     - **Client ID**: Use your certificate's SKI (Subject Key Identifier)
     - **Client Name**: Any friendly name (e.g., "My Test Connector")
     - **Grant Types**: Select `client_credentials`
     - **Scope**: `idsc:IDS_CONNECTOR_ATTRIBUTES_ALL`

3. **Configure Authentication:**

   **Option A: Client Secret (Simpler for testing)**
   - Set a client secret (e.g., "my-secret-123")
   - Note this down

   **Option B: Certificate (More secure, IDS standard)**
   - Export your certificate:
     ```bash
     keytool -exportcert -alias 1 \
       -keystore conf/default-connector-keystore.p12 \
       -storepass password -file connector.crt
     ```
   - Upload the certificate in DAPS UI

4. **Request a Token:**

   **If using client secret:**
   ```bash
   curl -k -X POST https://localhost/auth/token \
     -H "Content-Type: application/x-www-form-urlencoded" \
     -d "grant_type=client_credentials" \
     -d "client_id=YOUR_CLIENT_ID" \
     -d "client_secret=YOUR_CLIENT_SECRET" \
     -d "scope=idsc:IDS_CONNECTOR_ATTRIBUTES_ALL"
   ```

   **Expected response:**
   ```json
   {
     "access_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
     "token_type": "bearer",
     "expires_in": 3600
   }
   ```

5. **Use the Token:**
   ```bash
   # Extract the access_token from the response
   TOKEN="eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9..."

   # Use it to access protected endpoints
   curl -k -H "Authorization: Bearer $TOKEN" \
     https://localhost:8081/api/offers
   ```

### Method 2: Using Certificate Authentication (IDS Standard)

This is the proper IDS way, but more complex:

1. **Create a JWT Assertion:**

   You need to create a JWT signed with your client certificate's private key:

   ```json
   {
     "iss": "YOUR_CLIENT_ID",
     "sub": "YOUR_CLIENT_ID",
     "aud": "https://localhost/auth",
     "exp": 1234567890,
     "iat": 1234567890,
     "nbf": 1234567890
   }
   ```

2. **Sign the JWT:**

   Using your private key from the keystore:
   ```bash
   # This is complex and typically requires programming
   # See example scripts in the IDS documentation
   ```

3. **Request Token with JWT Assertion:**
   ```bash
   curl -k -X POST https://localhost/auth/token \
     -H "Content-Type: application/x-www-form-urlencoded" \
     -d "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer" \
     -d "assertion=YOUR_SIGNED_JWT" \
     -d "scope=idsc:IDS_CONNECTOR_ATTRIBUTES_ALL"
   ```

### Method 3: Extract from Connector Logs (Quick & Dirty)

The connector itself requests tokens from DAPS. You can try to extract one:

```bash
# Look for tokens in logs
docker compose logs connector | grep -i "token" | grep -E "bearer|eyJ"

# Look for DAT tokens specifically
docker compose logs connector | grep -i "dat" | grep -v "update"
```

**Note:** This may not work as connectors typically don't log full tokens for security reasons.

### Method 4: Use Test/Development Credentials

In development environments, DAPS might have test credentials:

```bash
# Try default admin credentials
curl -k -X POST https://localhost/auth/token \
  -d "grant_type=client_credentials" \
  -d "client_id=admin" \
  -d "client_secret=admin" \
  -d "scope=idsc:IDS_CONNECTOR_ATTRIBUTES_ALL"
```

Or try the connector's own client ID (if registered):

```bash
# Extract connector's SKI
CONNECTOR_SKI=$(keytool -list -v \
  -keystore conf/default-connector-keystore.p12 \
  -storepass password 2>/dev/null | \
  grep -A1 "SubjectKeyIdentifier" | tail -1 | \
  tr -d ' :' | tr '[:upper:]' '[:lower:]')

echo "Connector SKI: $CONNECTOR_SKI"

# Try to get token (if this client has a secret configured)
curl -k -X POST https://localhost/auth/token \
  -d "grant_type=client_credentials" \
  -d "client_id=$CONNECTOR_SKI" \
  -d "client_secret=<CHECK_DAPS_CONFIG>" \
  -d "scope=idsc:IDS_CONNECTOR_ATTRIBUTES_ALL"
```

## Finding Your Client ID

Your client ID is typically the **SKI (Subject Key Identifier)** from your certificate:

```bash
# Extract SKI from connector keystore
keytool -list -v -keystore conf/default-connector-keystore.p12 \
  -storepass password | grep -A1 "SubjectKeyIdentifier"

# You'll see something like:
# SubjectKeyIdentifier [
#   KeyIdentifier [
#     0000: 12 34 56 78 9A BC ...
#   ]
# ]

# The hex value (12:34:56:78:9A:BC:...) is your client ID
```

Or use this one-liner:

```bash
keytool -list -v -keystore conf/default-connector-keystore.p12 \
  -storepass password 2>/dev/null | \
  grep -A1 "SubjectKeyIdentifier" | tail -1 | \
  tr -d ' :' | tr '[:upper:]' '[:lower:]'
```

## Checking If Your Client Is Registered

```bash
# Check DAPS clients configuration
cat config/clients.yml

# Look for your client ID (SKI) in the output
```

Or via DAPS UI:
1. Go to https://localhost/
2. Login (admin/admin)
3. Navigate to Clients
4. Look for your client ID in the list

## Testing with the Token

Once you have a valid token:

```bash
# Set the token
TOKEN="your-access-token-here"

# Test connector endpoint
curl -k -H "Authorization: Bearer $TOKEN" \
  https://localhost:8081/api/offers

# Expected: HTTP 200 with list of offers
```

**Compare with no token:**
```bash
# Without token
curl -k https://localhost:8081/api/offers
# Expected: HTTP 401 Unauthorized

# With valid token
curl -k -H "Authorization: Bearer $TOKEN" \
  https://localhost:8081/api/offers
# Expected: HTTP 200 OK

# With invalid token
curl -k -H "Authorization: Bearer FAKE" \
  https://localhost:8081/api/offers
# Expected: HTTP 403 Forbidden
```

This pattern (401 → 200 → 403) proves DAPS validation is working!

## Token Response Format

A successful token response looks like:

```json
{
  "access_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJodHRwczovL2xvY2FsaG9zdC9hdXRoIiwic3ViIjoiMTI6MzQ6NTY6Nzg6OUE6QkMiLCJhdWQiOiJpZHNjOklEU19DT05ORUNUT1JTX0FMTCIsImV4cCI6MTczMDQ2MDAwMCwiaWF0IjoxNzMwNDU2NDAwLCJuYmYiOjE3MzA0NTY0MDAsInNjb3BlIjoiaWRzYzpJRFNfQ09OTkVDVE9SX0FUVFJJQlVURVNfQUxMIn0.signature",
  "token_type": "bearer",
  "expires_in": 3600,
  "scope": "idsc:IDS_CONNECTOR_ATTRIBUTES_ALL"
}
```

The `access_token` is the DAT token - a signed JWT that contains:
- **Issuer (iss)**: DAPS URL
- **Subject (sub)**: Your client ID
- **Audience (aud)**: Who can use this token
- **Expiration (exp)**: When it expires
- **Scope**: What permissions it grants

## Decoding a Token (Optional)

You can decode the JWT to see what's inside (without verification):

```bash
# Use jwt.io or jq
echo "YOUR_TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | jq

# Or visit: https://jwt.io
# Paste your token to see the decoded contents
```

## Troubleshooting

### "Invalid client" or "Client not found"

- Your client ID is not registered in DAPS
- Solution: Register the client via DAPS UI or config

### "Invalid client secret" or "Authentication failed"

- Wrong client secret
- Solution: Check the secret in DAPS config or reset it

### "Invalid scope"

- Requesting a scope the client doesn't have
- Solution: Add the scope to the client configuration in DAPS

### "Token request returns 401/403"

- DAPS itself requires authentication to request tokens
- Solution: Provide client credentials or certificate

### "Connection refused" or "Cannot connect to DAPS"

- DAPS is not running or not accessible
- Solution: Check `docker compose ps` and ensure DAPS container is up

## Quick Reference

```bash
# Get client ID (SKI)
./scripts/get-daps-token.sh

# Request token (with client secret)
curl -k -X POST https://localhost/auth/token \
  -d "grant_type=client_credentials" \
  -d "client_id=CLIENT_ID" \
  -d "client_secret=CLIENT_SECRET" \
  -d "scope=idsc:IDS_CONNECTOR_ATTRIBUTES_ALL"

# Use token
curl -k -H "Authorization: Bearer TOKEN" \
  https://localhost:8081/api/offers

# Test DAPS validation (no token needed)
./scripts/test-daps-validation.sh
```

## Remember

**For most testing purposes, you don't need a valid token!**

Testing with invalid or missing tokens is enough to verify that DAPS validation is working:

- ✅ No token → 401 = Validation is active
- ✅ Invalid token → 403 = Validation is working correctly
- ✅ Valid token → 200 = Full authentication flow works

Run `./scripts/test-daps-validation.sh` to test without needing a real token!
