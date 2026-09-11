## Context

The AnyLog service repository currently lacks explicit version tracking in its service definitions and deployment configurations. While the service has versioning through git tags and releases, there's no standardized environment variable to specify which version is being deployed. This creates challenges for:

- Debugging production issues (unclear which version is running)
- Version compatibility validation between service definitions and deployments
- Rollback scenarios (no explicit version reference in running services)
- Multi-environment deployments (dev/staging/prod version tracking)

The current state includes:
- `service.definition.json` - Defines service metadata but no version variable

Additionally, the service lacks a licensing mechanism to control access to publish, register, and start operations. A required `LICENSE_KEY` environment variable will provide access control while ensuring proper authorization for critical deployment operations.

- `service.deployment.json` - Deployment configuration without version tracking
- `docker-makefiles/*.env` - Environment files for different node types
- `Makefile` - Build and deployment automation
- `deploy.sh` - Deployment script

## Goals / Non-Goals

**Goals:**
- Add `SERVICE_VERSION` as a required environment variable across all configuration files using semantic versioning
- Add `LICENSE_KEY` as a required environment variable for publish, register, and start operations
- Implement default value logic ("1.0.0") for SERVICE_VERSION backward compatibility
- Implement Makefile validation to check LICENSE_KEY before publish, register, and start targets
- Update documentation to explain usage and defaults for both variables
- Ensure deployment scripts validate and use both SERVICE_VERSION and LICENSE_KEY
- Maintain zero breaking changes for existing deployments

**Non-Goals:**
- Automatic version detection from git tags (users must explicitly set or accept default)
- Version validation against available releases (out of scope for this change)
- Changing the service's internal versioning scheme
- Modifying Docker image tagging strategy

## Decisions

### Decision 1: Default Value Strategy
**Choice:** Use "1.0.0" as the default semantic version when SERVICE_VERSION is not set or is empty.

**Rationale:**
- Follows semantic versioning standard (MAJOR.MINOR.PATCH format)
- Provides clear, unambiguous version identifier
- Distinguishes SERVICE_VERSION from Docker TAG (which can use "latest")
- Allows existing deployments to continue without modification
- Establishes baseline version for services without explicit versioning

**Alternatives Considered:**
- Use "latest": Rejected - not a semantic version, conflicts with TAG usage
- Use git commit SHA as default: Rejected - requires git context and complicates non-git deployments
- Fail if not set: Rejected - breaks backward compatibility
- Use "0.0.0" or "dev": Rejected - "1.0.0" better represents a stable default

### Decision 2: Implementation Location
**Choice:** Add SERVICE_VERSION to environment files first, then reference in service definitions.

**Rationale:**
- Environment files are the source of truth for configuration
- Service definitions reference environment variables
- Follows existing pattern in the repository
- Easier to override per deployment


### Decision 5: LICENSE_KEY Validation Strategy
**Choice:** Implement LICENSE_KEY validation in Makefile targets (publish, register, start) with strict enforcement.

**Rationale:**
- Makefile is the entry point for these critical operations
- Strict validation ensures proper authorization before deployment
- Clear error messages guide users to set LICENSE_KEY
- Prevents accidental unauthorized deployments
- Consistent with security best practices

**Alternatives Considered:**
- Validate in deploy.sh only: Rejected - Makefile targets can be called directly
- Optional LICENSE_KEY: Rejected - licensing should be mandatory for controlled operations
- Validate all Makefile targets: Rejected - only publish, register, and start need licensing control


**Alternatives Considered:**
- Hardcode in service definitions: Rejected - reduces flexibility
- Add to Makefile only: Rejected - doesn't persist in deployed configurations

### Decision 3: Validation Approach
**Choice:** Implement validation in deploy.sh with default fallback, not strict enforcement.

**Rationale:**
- Soft validation maintains backward compatibility
- Script can inject default if missing
- Users get clear feedback about default usage
- No deployment failures for legacy configurations



### Risk: Users may not have LICENSE_KEY configured
**Mitigation:**
- Clear error messages in Makefile when LICENSE_KEY is missing
- Documentation prominently explains LICENSE_KEY requirement
- Example environment files include LICENSE_KEY placeholder
- Error messages direct users to documentation for obtaining license keys

**Alternatives Considered:**
- Strict validation (fail if not set): Rejected - breaks existing deployments
- No validation: Rejected - users won't know default is being used
- Validation in Makefile: Rejected - deploy.sh is the deployment entry point

### Decision 4: Documentation Strategy
**Choice:** Add SERVICE_VERSION section to README.md with examples for each node type.

**Rationale:**
- README is the primary documentation entry point
- Examples show concrete usage patterns
- Covers all node types (master, operator, query, etc.)
- Explains both explicit setting and default behavior

**Alternatives Considered:**
- Separate CONFIGURATION.md: Rejected - adds documentation fragmentation
- Only update deploy.sh comments: Rejected - insufficient visibility

## Risks / Trade-offs

### Risk: Users may not notice the default value is being used
**Mitigation:** 
- Add clear logging in deploy.sh when default "1.0.0" is applied
- Document the default prominently in README
- Include SERVICE_VERSION in example environment files

### Risk: Users may provide non-semantic version values
**Mitigation:**
- Implement validation in deploy.sh to check semantic version format
- Provide clear error messages explaining required format (e.g., "1", "1.0", "1.25.03")
- Document semantic versioning requirement prominently
- Reject invalid values like "latest", "dev", or "main"

### Risk: Existing deployments may have implicit version assumptions
**Mitigation:**
- Default value maintains current behavior
- No changes to actual service functionality
- Migration is opt-in (users can continue without setting SERVICE_VERSION)

### Trade-off: Default value vs. explicit requirement
**Decision:** Use default value for backward compatibility
**Impact:** 
- Pro: Zero breaking changes, smooth migration path
- Con: Users might not realize they should set explicit versions
- Mitigation: Strong documentation and deployment script warnings

## Migration Plan

### Phase 1: Add environment variables to configuration files
1. Update all `docker-makefiles/*.env` files to include `SERVICE_VERSION=1.0.0` and `LICENSE_KEY=<placeholder>`
2. Update `service.definition.json` to reference SERVICE_VERSION and LICENSE_KEY
3. Update `service.deployment.json` to use SERVICE_VERSION and LICENSE_KEY

### Phase 2: Update Makefile with LICENSE_KEY validation
1. Add LICENSE_KEY validation to publish target
2. Add LICENSE_KEY validation to register target
3. Add LICENSE_KEY validation to start target
4. Implement clear error messages for missing LICENSE_KEY

### Phase 3: Update deployment tooling
1. Modify `deploy.sh` to check for SERVICE_VERSION and LICENSE_KEY
2. Add semantic version validation (reject non-semantic versions like "latest", "dev")
3. Add default value injection (SERVICE_VERSION=1.0.0) if not present
4. Add logging to show which SERVICE_VERSION is being used

### Phase 4: Update documentation
1. Add SERVICE_VERSION section to README.md
2. Add LICENSE_KEY section to README.md
3. Include examples for each node type
4. Document default behavior and best practices for both variables

### Phase 5: Validation
1. Test deployment with SERVICE_VERSION set to valid semantic versions
2. Test deployment without SERVICE_VERSION (verify default "1.0.0")
3. Test deployment with empty SERVICE_VERSION (verify default)
4. Test publish/register/start targets with LICENSE_KEY set (verify success)
5. Test publish/register/start targets without LICENSE_KEY (verify failure with clear error)

### Rollback Strategy
If issues arise:
1. Remove SERVICE_VERSION references from service definitions
2. Revert environment file changes
3. Restore original deploy.sh
4. No data loss or service disruption (configuration-only change)

## Open Questions

None - the design is straightforward and all decisions have been made.
