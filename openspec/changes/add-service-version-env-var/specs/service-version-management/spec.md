## ADDED Requirements

### Requirement: SERVICE_VERSION environment variable must be defined
The service configuration SHALL require a `SERVICE_VERSION` environment variable to track the version of the AnyLog service being deployed using semantic versioning format.

#### Scenario: SERVICE_VERSION is explicitly set with valid semantic version
- **WHEN** a user defines `SERVICE_VERSION` with a valid semantic version (e.g., "1", "1.0", "1.25.03")
- **THEN** the system SHALL use the explicitly provided version value

#### Scenario: SERVICE_VERSION is not set
- **WHEN** `SERVICE_VERSION` is not defined in the environment configuration
- **THEN** the system SHALL use a default value of "1.0.0"

#### Scenario: SERVICE_VERSION is empty string
- **WHEN** `SERVICE_VERSION` is defined but set to an empty string
- **THEN** the system SHALL treat it as not set and use the default value "1.0.0"

#### Scenario: SERVICE_VERSION has invalid format
- **WHEN** `SERVICE_VERSION` is set to a non-semantic version value (e.g., "latest", "dev", "main")
- **THEN** the system SHALL reject the value and fail with a clear error message indicating semantic versioning is required

### Requirement: SERVICE_VERSION must be included in service definitions
The service definition files SHALL reference and validate the `SERVICE_VERSION` environment variable.

#### Scenario: Service definition includes SERVICE_VERSION
- **WHEN** a service definition file is created or updated
- **THEN** the file SHALL include `SERVICE_VERSION` in its environment variable declarations

#### Scenario: Service deployment uses SERVICE_VERSION
- **WHEN** a service is deployed
- **THEN** the deployment configuration SHALL reference `SERVICE_VERSION` for version tracking

### Requirement: Documentation must explain SERVICE_VERSION usage
The service documentation SHALL clearly explain the purpose, usage, and default behavior of `SERVICE_VERSION`.

#### Scenario: User reads documentation about environment variables
- **WHEN** a user consults the service documentation
- **THEN** the documentation SHALL include a section explaining `SERVICE_VERSION` with examples

#### Scenario: User needs to understand default behavior
- **WHEN** a user does not explicitly set `SERVICE_VERSION`
- **THEN** the documentation SHALL clearly state that "1.0.0" is used as the default value

#### Scenario: User reads documentation about LICENSE_KEY
- **WHEN** a user consults the service documentation
- **THEN** the documentation SHALL include a section explaining `LICENSE_KEY` requirement for publish, register, and start operations

### Requirement: Deployment scripts must handle SERVICE_VERSION
Deployment scripts and build processes SHALL validate and utilize the `SERVICE_VERSION` environment variable.

#### Scenario: Deployment script validates SERVICE_VERSION
- **WHEN** a deployment script runs
- **THEN** the script SHALL check for `SERVICE_VERSION` and apply the default if not present


### Requirement: Makefile targets must validate and document environment variables
The Makefile SHALL include validation and documentation for SERVICE_VERSION and LICENSE_KEY in appropriate targets.

#### Scenario: check-vars target validates both variables
- **WHEN** the check-vars Makefile target is executed
- **THEN** the target SHALL validate both SERVICE_VERSION and LICENSE_KEY are properly set

#### Scenario: help target documents both variables
- **WHEN** the help Makefile target is executed
- **THEN** the output SHALL include documentation for SERVICE_VERSION and LICENSE_KEY

#### Scenario: .PHONY includes all targets
- **WHEN** the Makefile is reviewed
- **THEN** the .PHONY declaration SHALL include all Makefile targets to prevent conflicts with files of the same name



#### Scenario: Build process includes SERVICE_VERSION
- **WHEN** the service is built using the Makefile
- **THEN** the build process SHALL incorporate `SERVICE_VERSION` into the build artifacts


### Requirement: LICENSE_KEY environment variable must be defined
The service configuration SHALL require a `LICENSE_KEY` environment variable (string value) that must be validated before executing publish, register, or start operations.

#### Scenario: LICENSE_KEY is set for publish operation
- **WHEN** a user runs a Makefile publish target with `LICENSE_KEY` defined
- **THEN** the system SHALL proceed with the publish operation

#### Scenario: LICENSE_KEY is missing for publish operation
- **WHEN** a user runs a Makefile publish target without `LICENSE_KEY` defined
- **THEN** the system SHALL fail with a clear error message indicating LICENSE_KEY is required

#### Scenario: LICENSE_KEY is set for register operation
- **WHEN** a user runs a Makefile register target with `LICENSE_KEY` defined
- **THEN** the system SHALL proceed with the register operation

#### Scenario: LICENSE_KEY is missing for register operation
- **WHEN** a user runs a Makefile register target without `LICENSE_KEY` defined
- **THEN** the system SHALL fail with a clear error message indicating LICENSE_KEY is required

#### Scenario: LICENSE_KEY is set for start operation
- **WHEN** a user runs a Makefile start target with `LICENSE_KEY` defined
- **THEN** the system SHALL proceed with the start operation

#### Scenario: LICENSE_KEY is missing for start operation
- **WHEN** a user runs a Makefile start target without `LICENSE_KEY` defined
- **THEN** the system SHALL fail with a clear error message indicating LICENSE_KEY is required


### Requirement: Backward compatibility must be maintained
Existing deployments without `SERVICE_VERSION` SHALL continue to function using the default value.

#### Scenario: Legacy deployment without SERVICE_VERSION
- **WHEN** an existing deployment is run without `SERVICE_VERSION` defined
- **THEN** the system SHALL automatically use "1.0.0" as the default and continue normal operation

#### Scenario: Migration to SERVICE_VERSION
- **WHEN** a user updates their deployment to include `SERVICE_VERSION`
- **THEN** the system SHALL accept the new value without requiring other configuration changes
