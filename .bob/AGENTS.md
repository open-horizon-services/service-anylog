# AnyLog Service - Agent Context

## Service Configuration

### SERVICE_VERSION

The `SERVICE_VERSION` environment variable tracks the version of the AnyLog service being deployed using semantic versioning format.

**Format:** Semantic versioning (e.g., "1", "1.0", "1.25.03")

**Default:** "1.0.0" if not explicitly set

**Validation:** 
- Must follow semantic versioning pattern: `^[0-9]+(\.[0-9]+)?(\.[0-9]+)?$`
- Non-semantic values like "latest", "dev", or "main" are rejected
- Validation occurs in `deploy.sh` via `_validate_service_version()` function

**Location:**
- Set in `docker-makefiles/<ANYLOG_TYPE>/node_configs.env`
- Referenced in `service.definition.json` and `service.deployment.json`
- Exported in `Makefile` (defaults to TAG value for OH compatibility)

**Usage:**
```bash
# Explicit version
export SERVICE_VERSION=1.2.5
make up ANYLOG_TYPE=anylog-operator

# Using default
make up ANYLOG_TYPE=anylog-operator  # Uses 1.0.0
```

### LICENSE_KEY

The `LICENSE_KEY` environment variable is **required** for publish, register (agent-run), and start operations.

**Requirement:** Mandatory for deployment authorization

**Validation:**
- Checked in `Makefile` targets: `publish-service`, `agent-run`
- Checked in `deploy.sh` via `cmd_license_check()` function
- Missing LICENSE_KEY causes clear error messages directing users to set it

**Location:**
- Stored in `docker-makefiles/<ANYLOG_TYPE>/node_configs.env`
- Written automatically by `license-check` target after user acceptance
- Can be set via environment variable or `--license-key` flag

**Automatic Handling:**
- `make up` and `make prep-service` automatically run `license-check`
- If LICENSE_KEY not found, prompts user interactively (via `/dev/tty`)
- Saves accepted key to `node_configs.env` for future runs
- Set `PROMPT_LICENSE=false` to fail fast instead of prompting (useful for CI/CD)

**Usage:**
```bash
# Set via environment
export LICENSE_KEY="your-license-key"
make publish ANYLOG_TYPE=anylog-operator

# Interactive prompt
make up ANYLOG_TYPE=anylog-operator
# Prompts: "License Key: "

# Explicit check
make license-check ANYLOG_TYPE=anylog-operator
```

**Security:**
- Never commit LICENSE_KEY to version control
- Ensure `node_configs.env` is in `.gitignore`
- Use secure methods to distribute keys to deployment environments

## Implementation Details

### Files Modified

1. **Environment Files:**
   - `docker-makefiles/.env`
   - `docker-makefiles/anylog_master.env`
   - `docker-makefiles/anylog_operator.env`
   - `docker-makefiles/anylog_query.env`
   - All `docker-makefiles/*/node_configs.env` files

2. **Service Definitions:**
   - `service.definition.json` - Added to userInput section
   - `service.deployment.json` - Added to inputs array

3. **Deployment Scripts:**
   - `deploy.sh` - Added validation functions and checks
   - `Makefile` - Added LICENSE_KEY validation to publish/register/start targets

4. **Documentation:**
   - `README.md` - Comprehensive documentation for both variables

### Validation Functions

**deploy.sh:**
```bash
_validate_service_version()  # Validates semantic versioning format
cmd_license_check()          # Resolves/prompts for LICENSE_KEY
```

**Makefile:**
- `publish-service` - Checks LICENSE_KEY before publishing
- `agent-run` - Checks LICENSE_KEY before starting agent
- `check-vars` - Displays validation status for both variables

## Testing

### Pre-Deployment Validation

```bash
# Check configuration
make check-vars ANYLOG_TYPE=anylog-operator

# Validate license key
make license-check ANYLOG_TYPE=anylog-operator
```

### Test Cases

1. **SERVICE_VERSION:**
   - Valid: "1", "1.0", "1.25.03" ✓
   - Invalid: "latest", "dev", "main" ✗
   - Empty/unset: Uses default "1.0.0" ✓

2. **LICENSE_KEY:**
   - Set: Publish/register/start succeed ✓
   - Missing: Clear error message ✗
   - Interactive prompt: Saves to config ✓

## Best Practices

1. **SERVICE_VERSION:**
   - Use explicit versions for production deployments
   - Follow semantic versioning conventions
   - Update version when deploying new releases
   - Document version changes in deployment logs

2. **LICENSE_KEY:**
   - Store securely (environment variables or secrets management)
   - Never commit to version control
   - Use `make license-check` to validate and save
   - Set `PROMPT_LICENSE=false` in CI/CD environments

## Related Skills

- `.bob/skills/test-anylog-service/SKILL.md` - Pre-deployment validation skill
- `.bob/skills/publish-anylog-service/SKILL.md` - Publishing workflow
- `.bob/skills/deploy-anylog-network/SKILL.md` - Deployment workflow
