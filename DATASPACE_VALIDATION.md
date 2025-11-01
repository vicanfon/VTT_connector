# Dataspace Validation & DAPS Registration Guide

This guide explains how to verify that your connector is properly registered in DAPS and is a valid participant in the dataspace.

## Quick Validation

Run the automated verification script:

```bash
./scripts/verify-dataspace-registration.sh
```

Or with custom URLs:

```bash
./scripts/verify-dataspace-registration.sh https://your-connector.com https://your-daps.com https://your-broker.com
```

## Understanding DAPS & Dataspace Validation

### What is DAPS?

**DAPS (Dynamic Attribute Provisioning Service)** is the identity provider for the IDS (International Data Spaces). It:
- Manages connector identities and certificates
- Issues DAT (Dynamic Attribute Token) tokens for authenticated connectors
- Validates connector participation in the dataspace

### What Does "Valid Participant" Mean?

A valid dataspace participant must:
1. ✅ Be registered in DAPS with a valid certificate
2. ✅ Be able to request and receive DAT tokens from DAPS
3. ✅ Include valid DAT tokens in IDS messages
4. ✅ Have other connectors accept its DAT tokens

## Methods to Verify Connector Registration

### Method 1: Check DAPS JWKS (Public Keys)

DAPS publishes its public keys for token verification:

```bash
# Check DAPS JWKS endpoint
curl -k https://localhost/auth/jwks.json

# You should see JSON with "keys" array
```

**What this tells you**: DAPS is running and can provide keys for token verification.

### Method 2: Check Connector Self-Description

Every valid IDS connector must provide a self-description:

```bash
# Get connector self-description
curl -k https://localhost/connector/

# Or via direct port
curl -k https://localhost:8081/
```

**Expected response**: JSON-LD document with:
- `@type: "ids:BaseConnector"`
- `ids:securityProfile`: Security level
- `ids:publicKey`: Connector's public key
- `ids:hasDefaultEndpoint`: IDS endpoint URL

**What this tells you**: The connector is configured with IDS metadata.

### Method 3: Test IDS Description Request

This is the **most definitive test** - it requires a valid DAT token:

```bash
# Send an IDS DescriptionRequestMessage to the connector
curl -k -X POST https://localhost/connector/api/ids/data \
  -H "Content-Type: application/json" \
  -d '{
    "@context": "https://w3id.org/idsa/contexts/context.jsonld",
    "@type": "ids:DescriptionRequestMessage",
    "@id": "https://w3id.org/idsa/autogen/descriptionRequestMessage/test",
    "ids:modelVersion": "4.2.7",
    "ids:issued": {
      "@value": "2025-11-01T12:00:00.000Z",
      "@type": "http://www.w3.org/2001/XMLSchema#dateTimeStamp"
    }
  }'
```

**Expected responses**:
- **401/403**: Requires authentication (DAT token missing)
- **400**: Message validation failed (but connector is responding)
- **200**: Success with connector self-description

**What this tells you**:
- If you get 401/403: Connector is validating DAPS tokens (good!)
- If you get 400: IDS protocol is working, message format issue
- If you get 200: You have a valid DAT token and connector trusts it

### Method 4: Check Broker Registration

Query the broker to see if your connector is registered:

```bash
# Get list of registered connectors from broker
curl -k https://localhost/broker/connectors/

# Or check broker infrastructure
curl -k https://localhost/broker/infrastructure/
```

**What this tells you**: Whether your connector has successfully registered with the broker.

### Method 5: Check Connector Logs for DAPS Activity

```bash
# Look for DAPS token requests
docker compose logs connector | grep -i "daps\|token\|dat"

# Look for successful token retrieval
docker compose logs connector | grep -i "successfully\|acquired\|token"
```

**What to look for**:
- Token request attempts
- Successful token responses
- Token validation messages
- Certificate/keystore loading

### Method 6: Test with Authentication (Advanced)

To test the full authentication flow, you need to:

#### Step 1: Register Your Client in DAPS

1. Access DAPS admin UI: `https://localhost/`
2. Login with admin credentials (default: admin/admin)
3. Register a new client with:
   - Client ID
   - Client certificate
   - Allowed scopes (e.g., `idsc:IDS_CONNECTOR_ATTRIBUTES_ALL`)

#### Step 2: Request a DAT Token

```bash
# Request token from DAPS (simplified example)
curl -k -X POST https://localhost/auth/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=YOUR_CLIENT_ID" \
  -d "client_secret=YOUR_CLIENT_SECRET" \
  -d "scope=idsc:IDS_CONNECTOR_ATTRIBUTES_ALL"
```

**Expected response**: JWT token (DAT)

#### Step 3: Use the Token in IDS Messages

```bash
# Use the DAT token in an IDS message
curl -k -X POST https://localhost/connector/api/ids/data \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_DAT_TOKEN" \
  -d '{
    "@type": "ids:DescriptionRequestMessage",
    ...
  }'
```

**Expected response**: 200 OK with connector description

## Testing Scenarios

### Scenario 1: Basic Connectivity Test

Tests if services are reachable:

```bash
# DAPS
curl -k https://localhost/auth/jwks.json
# Expected: 200 OK with JSON

# Connector
curl -k https://localhost/connector/
# Expected: 200 OK with connector self-description

# Broker
curl -k https://localhost/broker/infrastructure/
# Expected: 200 or 400 (both indicate broker is responding)
```

### Scenario 2: IDS Protocol Test

Tests if the connector speaks IDS protocol:

```bash
# Send minimal IDS message without auth
curl -k -X POST https://localhost/connector/api/ids/data \
  -H "Content-Type: application/json" \
  -d '{"@type":"ids:DescriptionRequestMessage"}'
```

**Interpretation**:
- **401/403**: Good! Connector requires authentication
- **400**: IDS endpoint is working, message needs fixing
- **500**: Server error, check logs
- **Connection refused**: Connector not running

### Scenario 3: Broker Query Test

Check if connector is registered in the broker:

```bash
# Query broker for registered connectors
curl -k https://localhost/broker/connectors/ | jq '.'

# Look for your connector ID in the response
# Your connector ID is in conf/config.json under "ids:connectorDescription"."@id"
```

### Scenario 4: End-to-End Authentication Test

Full test with proper DAPS authentication:

1. Register connector in DAPS via UI
2. Configure connector with client certificate
3. Request DAT from DAPS
4. Send authenticated IDS message
5. Verify connector accepts and responds

## Common Issues & Solutions

### Issue: "Unauthorized" or "Forbidden" Responses

**Symptom**: HTTP 401 or 403 when accessing connector endpoints

**This is actually GOOD!** It means:
- Connector is enforcing DAPS authentication
- You need a valid DAT token to proceed
- The security model is working correctly

**Solution**:
- Register your client in DAPS
- Request a DAT token
- Include the token in your requests

### Issue: "Bad Request" (400) on IDS Endpoints

**Symptom**: HTTP 400 when sending IDS messages

**This means**:
- Connector is responding to IDS protocol
- Your message format is incorrect or incomplete
- DAPS validation might be passing but message validation fails

**Solution**:
- Check IDS message format in logs
- Ensure all required fields are present
- Verify message uses correct IDS vocabulary

### Issue: Cannot Reach Connector or DAPS

**Symptom**: Connection refused or timeout

**Solution**:
```bash
# Check if containers are running
docker compose ps

# Check logs
docker compose logs nginx
docker compose logs connector
docker compose logs daps

# Restart services
docker compose restart
```

### Issue: Connector Not in Broker Catalog

**Symptom**: Connector not listed when querying broker

**Possible causes**:
1. Connector hasn't registered yet
2. Broker registration failed
3. Network connectivity issues

**Solution**:
```bash
# Check connector logs for broker registration
docker compose logs connector | grep -i broker

# Manually trigger registration (if endpoint exists)
curl -k -X POST https://localhost/connector/api/broker/register

# Check broker logs
docker compose logs broker
```

## Verification Checklist

Use this checklist to verify your connector is a valid dataspace participant:

- [ ] **DAPS is accessible**: `curl -k https://localhost/auth/jwks.json` returns 200
- [ ] **Connector self-description works**: `curl -k https://localhost/connector/` returns JSON-LD
- [ ] **IDS endpoint responds**: `curl -k https://localhost/connector/api/ids/data` returns 400/401/403 (not connection error)
- [ ] **Connector has certificate**: Check `conf/default-connector-keystore.p12` exists
- [ ] **DAPS environment configured**: `docker compose exec connector env | grep DAPS` shows URLs
- [ ] **Broker is accessible**: `curl -k https://localhost/broker/infrastructure/` responds
- [ ] **Connector logs show startup**: No errors in `docker compose logs connector`
- [ ] **Can access DAPS admin UI**: `https://localhost/` loads Omejdn
- [ ] **Certificates are valid**: Check expiration dates
- [ ] **Network connectivity works**: All containers can reach each other

## Security Notes

### In Local Development

- Self-signed certificates are acceptable
- `proxy_ssl_verify off` is used for convenience
- Default credentials (admin/admin) are okay
- All services run on localhost

### In Production

- ⚠️ **Use valid CA-signed certificates**
- ⚠️ **Enable SSL verification**
- ⚠️ **Change all default passwords**
- ⚠️ **Use proper FQDN**
- ⚠️ **Restrict network access**
- ⚠️ **Monitor DAPS token usage**
- ⚠️ **Regular certificate rotation**

## Additional Resources

### Connector Configuration

The connector's IDS configuration is in:
- `conf/config.json` - Connector ID, security profile, endpoints
- `conf/default-connector-keystore.p12` - Connector certificate

### DAPS Configuration

DAPS configuration is in:
- `config/omejdn.yml` - DAPS server settings
- `keys/` - DAPS certificates and keys
- `.env` - DAPS environment variables

### Useful Commands

```bash
# Check connector certificate
keytool -list -v -keystore conf/default-connector-keystore.p12 -storepass password

# View DAPS configuration
docker compose exec daps cat /opt/config/omejdn.yml

# Test internal connectivity
docker compose exec nginx curl http://connector:8081/

# Monitor all logs
docker compose logs -f

# Check DAPS clients
docker compose exec daps cat /opt/config/clients.yml
```

## Getting Help

If you're having trouble validating your connector:

1. Run the verification script: `./scripts/verify-dataspace-registration.sh`
2. Check all logs: `docker compose logs > all-logs.txt`
3. Verify configuration files haven't been corrupted
4. Test each component individually
5. Check the TROUBLESHOOTING_LOCAL.md guide

## Next Steps

Once your connector is validated:

1. **Register with Broker**: Use connector API to register with broker
2. **Publish Resources**: Add data resources via Provider UI
3. **Test Discovery**: Query broker for your connector
4. **Enable Consumption**: Allow other connectors to access your data
5. **Monitor Activity**: Watch logs for IDS message exchanges
