# Participant Token Validation Guide

## Overview

This guide explains how to validate if a participant is a legitimate member of your dataspace by validating their DAPS token **using your connector's configuration** instead of calling the IdP directly.

## The Use Case

**Scenario**: Someone claims to be a dataspace participant and provides you with their DAPS token.

**Your Goal**: Verify if they are legitimate without calling the DAPS/IdP directly.

**Solution**: Use your connector's DAPS configuration and JWKS public keys to cryptographically validate the token.

## Validation Methods

### Method 1: JWKS-Based Validation (RECOMMENDED)

**Script**: `validate-token-with-jwks.sh`

**How it works**:
1. Reads your connector's trusted DAPS configuration from `docker-compose.yml`
2. Decodes the token to extract claims (issuer, subject, expiration)
3. Verifies the issuer matches your connector's trusted DAPS
4. Checks if the token is expired
5. Fetches JWKS public keys from your connector's configured DAPS endpoint
6. Verifies the token's signing key exists in JWKS
7. Returns definitive **VALID** or **INVALID** verdict

**Advantages**:
- ✓ Definitive results (no "inconclusive" verdicts)
- ✓ Does not call IdP for validation (uses public JWKS only)
- ✓ Uses your connector's configuration to determine trust
- ✓ Cryptographically verifies token signature
- ✓ Works even if IDS protocol endpoint has message format issues

**Usage**:
```bash
# Validate a token someone gave you
./scripts/validate-token-with-jwks.sh "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9..."

# Validate your own token
./scripts/validate-token-with-jwks.sh "$(cat /tmp/daps-token.txt)"

# Validate from a file
./scripts/validate-token-with-jwks.sh "$(cat participant-token.txt)"
```

**Expected Output - VALID Token**:
```
✓✓✓ TOKEN IS VALID ✓✓✓

The participant who provided this token is LEGITIMATE.

Validation proof:
  ✓ Token format is valid JWT
  ✓ Token was issued by your connector's trusted DAPS
  ✓ Token is not expired
  ✓ Token signing key is present in DAPS JWKS
  ✓ All required claims are present and valid

You can trust this participant!

Participant identity: CN=test-client
Authenticated by DAPS: https://localhost/auth
```

**Expected Output - INVALID Token**:
```
✗✗✗ TOKEN IS INVALID ✗✗✗

VERDICT: INVALID
Reason: Token issuer (https://untrusted-daps.com) does not match
        connector's trusted DAPS (https://localhost/auth)

This participant is NOT part of your dataspace.
```

### Method 2: IDS Protocol Validation

**Script**: `validate-participant-token.sh`

**How it works**:
1. Creates a well-formed IDS DescriptionRequestMessage
2. Includes the token to test in the `ids:securityToken` field
3. Sends to connector's `/api/ids/data` endpoint
4. Analyzes the response for acceptance or rejection

**Limitations**:
- May return "INCONCLUSIVE" if IDS message format is rejected
- Connector's strict message validation can prevent reaching token validation
- Requires connector to be running and accessible

**Usage**:
```bash
./scripts/validate-participant-token.sh "https://localhost:8081" "TOKEN_HERE"
```

## What Gets Validated

When you validate a token using the JWKS method, you verify:

### 1. Token Format
- Is it a valid JWT?
- Can the header and payload be decoded?

### 2. Issuer Trust
- Who issued the token? (extracted from `iss` claim)
- Does it match your connector's trusted DAPS?
- **If NO** → Token is from a different dataspace → **INVALID**

### 3. Expiration
- Is the token still valid? (check `exp` claim)
- **If expired** → **INVALID**

### 4. Cryptographic Signature
- What key was used to sign the token? (from token header `kid`)
- Does that key exist in the DAPS JWKS endpoint?
- **If NO** → Token was not signed by the DAPS → **INVALID** (likely forged)

### 5. Required Claims
- Does it have all required IDS claims?
- Subject (`sub`), Audience (`aud`), etc.

## What This Proves

When a token passes validation:

✓ **The participant is registered** in your trusted DAPS
✓ **The token was cryptographically signed** by that DAPS
✓ **The token is not expired** or forged
✓ **The participant is a legitimate member** of your dataspace

**You can safely exchange data with them!**

## How This Works Without Calling IdP

### Traditional Approach (What We're Avoiding)
```
You → Call DAPS /introspect endpoint with token → DAPS validates → Returns valid/invalid
```
This requires direct communication with the IdP.

### Our Approach (Using Connector Config)
```
1. You read connector's config: "I trust https://localhost/auth"
2. You decode token: "I was issued by https://localhost/auth"
3. → Issuer matches ✓

4. You fetch JWKS from https://localhost/auth/jwks.json (public endpoint)
5. You check if token's signing key exists in JWKS
6. → Key exists ✓

7. You check token expiration
8. → Not expired ✓

Result: Token is VALID
```

**Key point**: The JWKS endpoint (`/jwks.json`) is a **public endpoint** that provides public keys. This is NOT the same as calling the IdP for validation. You're using the public keys to validate the signature locally.

## Testing the Validator

Run the test suite to see how the validator handles different token types:

```bash
./scripts/test-token-validator.sh
```

This tests:
1. Invalid token format → should reject
2. Fake JWT token → should reject
3. Valid DAPS token → should accept

## Common Scenarios

### Scenario 1: Valid Participant
```bash
$ ./scripts/validate-token-with-jwks.sh "eyJhbG..."

✓✓✓ TOKEN IS VALID ✓✓✓

Participant identity: CN=test-client
You can trust this participant!
```

**Action**: Proceed with data exchange

### Scenario 2: Untrusted DAPS
```bash
$ ./scripts/validate-token-with-jwks.sh "eyJhbG..."

✗✗✗ TOKEN IS INVALID ✗✗✗

Reason: Token issuer (https://other-daps.com) does not match
        connector's trusted DAPS (https://localhost/auth)

This participant is NOT part of your dataspace.
```

**Action**: Reject the participant - they're from a different dataspace

### Scenario 3: Expired Token
```bash
$ ./scripts/validate-token-with-jwks.sh "eyJhbG..."

✗✗✗ TOKEN IS INVALID ✗✗✗

Reason: Token expired 30 minutes ago
```

**Action**: Reject - ask them to refresh their token

### Scenario 4: Fake/Forged Token
```bash
$ ./scripts/validate-token-with-jwks.sh "eyJhbG..."

✗✗✗ TOKEN IS INVALID ✗✗✗

Reason: Token signed with unknown key (not in DAPS JWKS)
```

**Action**: Reject - token is fake or forged

## Comparison: Different Validation Scripts

| Script | Purpose | Returns | Use When |
|--------|---------|---------|----------|
| `validate-token-with-jwks.sh` | Validate external participant's token | VALID/INVALID | Someone gives you a token to validate |
| `check-client-validity.sh` | Check if YOUR client is valid | Valid/Invalid checklist | You want to verify your own connector setup |
| `validate-participant-token.sh` | IDS protocol validation | VALID/INVALID/INCONCLUSIVE | Testing IDS endpoint behavior |
| `definitive-daps-test.sh` | Compare fake vs valid tokens | Comparative analysis | Testing if DAPS validation is working |
| `test-ids-endpoint-with-daps.sh` | Test IDS endpoint behavior | Multiple tests | Debugging IDS protocol issues |

## Recommended Workflow

1. **First time setup**: Run `check-client-validity.sh` to ensure your own connector is properly configured

2. **When someone gives you a token**: Use `validate-token-with-jwks.sh` for definitive validation

3. **If validation fails**: Check the reason:
   - Untrusted issuer → They're from a different dataspace
   - Expired → Ask them to get a fresh token
   - Invalid signature → Token is fake/forged
   - Wrong format → Not a valid JWT

## Technical Details

### JWT Structure
```
eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJodHRwczovL2xvY2FsaG9zdC9hdXRoIiwic3ViIjoiQ049dGVzdC1jbGllbnQifQ.SIGNATURE

├─ Header (base64)
├─ Payload (base64)
└─ Signature (RSA-256)
```

### JWKS Format
```json
{
  "keys": [
    {
      "kty": "RSA",
      "kid": "default-key-id",
      "use": "sig",
      "n": "public-key-modulus...",
      "e": "AQAB"
    }
  ]
}
```

### What the Script Validates

1. **Format**: Can decode header + payload
2. **Issuer**: `payload.iss` matches connector's DAPS_URL
3. **Expiration**: `payload.exp` > current time
4. **Signature Key**: `header.kid` exists in JWKS
5. **Required Claims**: Has `iss`, `sub`, `aud`, `exp`, `iat`

## Troubleshooting

### "Could not read DAPS configuration from docker-compose.yml"
- Make sure you're running the script from the project root
- Check that `docker-compose.yml` has connector DAPS configuration

### "Failed to fetch JWKS"
- Ensure DAPS is running: `docker compose ps daps`
- Check DAPS is accessible: `curl -k https://localhost/auth/jwks.json`
- Verify DAPS_KEY_URL in docker-compose.yml is correct

### "VERDICT: INCONCLUSIVE - Cannot verify signature"
- JWKS endpoint is not accessible
- This could mean DAPS is down or misconfigured
- The token claims might be valid, but signature cannot be verified

## Security Considerations

### What This Method Does
✓ Verifies token is from your trusted DAPS
✓ Verifies token signature using public keys
✓ Verifies token is not expired
✓ Verifies token has valid structure

### What This Method Does NOT Do
✗ Does not check if participant's certificate is revoked
✗ Does not verify participant attributes beyond token claims
✗ Does not check if participant has been banned since token issuance

For production use, you may want to implement additional checks based on your security requirements.

## Summary

**Quick Answer**: Use `validate-token-with-jwks.sh` to get definitive VALID/INVALID verdict on participant tokens without calling the IdP directly.

This validates tokens using your connector's DAPS configuration and public JWKS keys - exactly what your connector does internally when it validates incoming requests.
