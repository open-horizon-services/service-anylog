# Test AnyLog Service Configuration

## Description
Validates AnyLog service configuration before publishing or running the service. Checks for required environment variables, validates semantic versioning format, ensures sane defaults, and provides clear guidance for fixing any deficiencies.

## When to Use
- Before running `make publish` to publish the service
- Before running `make register` to register the service
- Before running `make start` to start the service
- When setting up a new AnyLog service deployment
- When troubleshooting configuration issues

**Note**: This skill validates configuration only. For operator nodes, full runtime testing requires a master node to be available for blockchain synchronization. An operator can start successfully but will show connection errors without a master node.

## What It Does
1. Validates SERVICE_VERSION is present and follows semantic versioning format
2. Validates LICENSE_KEY is present and not a placeholder
3. Checks all environment files for required variables
4. Verifies sane defaults are in place
5. Provides actionable error messages and correction guidance
6. Suggests fixes for common configuration issues

## Usage

```bash
# Test current configuration
bob test-anylog-service

# Test specific environment file
bob test-anylog-service --env-file docker-makefiles/anylog_master.env

# Test all node configurations
bob test-anylog-service --all-nodes
```

## Validation Checks

### 1. SERVICE_VERSION Validation
- **Check**: Variable is defined
- **Check**: Value follows semantic versioning (e.g., "1", "1.0", "1.25.03")
- **Reject**: Non-semantic values like "latest", "dev", "main"
- **Default**: "1.0.0" if not set

### 2. LICENSE_KEY Validation
- **Check**: Variable is defined
- **Check**: Value is not a placeholder (e.g., "<placeholder>", "CHANGEME")
- **Check**: Value is a non-empty string
- **Error**: Clear message directing user to obtain a valid license key

### 3. Environment File Checks
Files to validate:
- `docker-makefiles/.env`
- `docker-makefiles/anylog_master.env`
- `docker-makefiles/anylog_operator.env`
- `docker-makefiles/anylog_query.env`
- `docker-makefiles/*/node_configs.env`

### 4. Service Definition Checks
- **Check**: `service.definition.json` includes SERVICE_VERSION
- **Check**: `service.definition.json` includes LICENSE_KEY
- **Check**: `service.deployment.json` references both variables

## Error Messages and Guidance

### Missing SERVICE_VERSION
```
❌ ERROR: SERVICE_VERSION is not defined

SERVICE_VERSION is required and must be a semantic version.

To fix:
1. Add to your environment file: SERVICE_VERSION=1.0.0
2. Or set explicitly: export SERVICE_VERSION=1.0.0

Examples of valid versions: "1", "1.0", "1.25.03"
```

### Invalid SERVICE_VERSION Format
```
❌ ERROR: SERVICE_VERSION="latest" is not a valid semantic version

SERVICE_VERSION must follow semantic versioning format.

To fix:
1. Change to a semantic version: SERVICE_VERSION=1.0.0
2. Valid formats: "1", "1.0", "1.25.03"

Note: Use TAG=latest for Docker image tags, not SERVICE_VERSION
```

### Missing LICENSE_KEY
```
❌ ERROR: LICENSE_KEY is not defined

LICENSE_KEY is required for publish, register, and start operations.

To fix:
1. Obtain a license key from your administrator
2. Add to your environment file: LICENSE_KEY=your-actual-key
3. Or set explicitly: export LICENSE_KEY=your-actual-key

⚠️  Do not commit LICENSE_KEY to version control
```

### Placeholder LICENSE_KEY
```
❌ ERROR: LICENSE_KEY is set to a placeholder value

LICENSE_KEY must be a valid license key, not a placeholder.

Current value: "<placeholder>"

To fix:
1. Replace with your actual license key
2. Update environment file: LICENSE_KEY=your-actual-key
```

## Success Output

```
✅ Configuration validation passed!

SERVICE_VERSION: 1.0.0 (semantic version ✓)
LICENSE_KEY: ********** (present ✓)

Environment files checked:
  ✓ docker-makefiles/.env
  ✓ docker-makefiles/anylog_master.env
  ✓ docker-makefiles/anylog_operator.env
  ✓ docker-makefiles/anylog_query.env
  ✓ docker-makefiles/anylog-master/node_configs.env
  ✓ docker-makefiles/anylog-operator/node_configs.env
  ✓ docker-makefiles/anylog-query/node_configs.env

Service definitions:
  ✓ service.definition.json
  ✓ service.deployment.json

Ready to publish/register/start the service!
```

## Implementation Notes

### Semantic Version Validation Regex
```bash
# Matches: 1, 1.0, 1.0.0, 1.25.03, etc.
^[0-9]+(\.[0-9]+){0,2}$
```

### Environment File Parsing
```bash
# Source environment file and check variables
source "$ENV_FILE"
if [[ -z "$SERVICE_VERSION" ]]; then
    echo "❌ ERROR: SERVICE_VERSION not defined in $ENV_FILE"
fi
```

### License Key Validation
```bash
# Check for placeholder values
PLACEHOLDER_PATTERNS=("<placeholder>" "CHANGEME" "your-key-here" "TODO")
for pattern in "${PLACEHOLDER_PATTERNS[@]}"; do
    if [[ "$LICENSE_KEY" == "$pattern" ]]; then
        echo "❌ ERROR: LICENSE_KEY is a placeholder"
        exit 1
    fi
done
```

## Exit Codes
- `0`: All validations passed
- `1`: SERVICE_VERSION validation failed
- `2`: LICENSE_KEY validation failed
- `3`: Environment file validation failed
- `4`: Service definition validation failed

## Integration with Makefile

Add to Makefile targets:
```makefile
.PHONY: validate-config
validate-config:
	@bob test-anylog-service || (echo "❌ Configuration validation failed. Fix errors before proceeding." && exit 1)

publish: validate-config
	# ... existing publish logic

register: validate-config
	# ... existing register logic

start: validate-config
	# ... existing start logic
```

## Related Documentation
- [SERVICE_VERSION Documentation](../../README.md#service_version)
- [LICENSE_KEY Documentation](../../README.md#license_key)
- [Environment Configuration Guide](../../README.md#environment-configuration)
