## Why

The AnyLog service currently lacks a standardized way to specify and track the service version being deployed. This creates challenges for version management, debugging, and ensuring compatibility between service definitions and deployments. A required `SERVICE_VERSION` environment variable will provide explicit version control while maintaining backward compatibility through sensible defaults.

**Reference:** GitHub Issue [#6](https://github.com/open-horizon-services/service-anylog/issues/6)

## What Changes

- Add `SERVICE_VERSION` as a required environment variable in service configuration using semantic versioning format (e.g., "1", "1.0", "1.25.03")
- Add `LICENSE_KEY` as a required environment variable (string value) that must be present before running publish, register, or start Makefile targets
- Implement default value logic to use semantic version "1.0.0" when `SERVICE_VERSION` is not explicitly set
- Implement validation in Makefile to check for `LICENSE_KEY` before executing publish, register, or start targets
- Update documentation to reflect the new required variables and their default behavior
- Update deployment scripts and configuration files to include both `SERVICE_VERSION` and `LICENSE_KEY`
- Ensure all service definition files reference and validate both environment variables

## Capabilities

### New Capabilities
- `service-version-management`: Standardized version tracking for AnyLog service deployments through a required environment variable with default fallback behavior
- `license-key-validation`: Required LICENSE_KEY environment variable validation before executing publish, register, or start operations

### Modified Capabilities
<!-- No existing capabilities are being modified at the requirement level -->

## Impact

**Affected Components:**
- `service.definition.json` - Must include SERVICE_VERSION and LICENSE_KEY variables
- `service.deployment.json` - Must reference SERVICE_VERSION and LICENSE_KEY in configuration
- `docker-makefiles/*.env` - Environment files need SERVICE_VERSION and LICENSE_KEY definitions
- `Makefile` - Build and deployment targets need to validate LICENSE_KEY and handle SERVICE_VERSION
- `README.md` - Documentation must explain SERVICE_VERSION and LICENSE_KEY usage
- `deploy.sh` - Deployment script must validate and use both variables

**Backward Compatibility:**
- Existing deployments without SERVICE_VERSION will use the default value
- No breaking changes to existing service behavior
- Migration path is straightforward: add SERVICE_VERSION to environment files
