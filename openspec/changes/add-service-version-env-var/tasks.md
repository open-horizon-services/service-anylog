## 1. Update Environment Configuration Files

- [x] 1.1 Add SERVICE_VERSION=1.0.0 and LICENSE_KEY=<placeholder> to docker-makefiles/.env
- [x] 1.2 Add SERVICE_VERSION=1.0.0 and LICENSE_KEY=<placeholder> to docker-makefiles/anylog_master.env
- [x] 1.3 Add SERVICE_VERSION=1.0.0 and LICENSE_KEY=<placeholder> to docker-makefiles/anylog_operator.env
- [x] 1.4 Add SERVICE_VERSION=1.0.0 and LICENSE_KEY=<placeholder> to docker-makefiles/anylog_query.env
- [x] 1.5 Check and add LICENSE_KEY=<placeholder> to all node_configs.env files if not already present
- [x] 1.6 Add SERVICE_VERSION=1.0.0 to all node_configs.env files in docker-makefiles subdirectories

## 2. Update Service Definition Files

- [x] 2.1 Add SERVICE_VERSION and LICENSE_KEY to service.definition.json userInput section
- [x] 2.2 Add SERVICE_VERSION and LICENSE_KEY to service.deployment.json services configuration
- [x] 2.3 Verify both variables are properly referenced in deployment configuration

## 3. Update Deployment Scripts

- [x] 3.1 Add semantic version validation logic to deploy.sh (reject non-semantic versions)
- [x] 3.2 Implement default value injection (SERVICE_VERSION=1.0.0) if not set
- [x] 3.3 Add LICENSE_KEY validation to deploy.sh
- [x] 3.4 Add logging to display which SERVICE_VERSION is being used during deployment
- [x] 3.5 Add error handling for invalid SERVICE_VERSION formats with clear error messages
- [x] 3.6 Add error handling for missing LICENSE_KEY with clear error messages

## 4. Update Build Automation

- [x] 4.1 Add LICENSE_KEY validation to Makefile publish target
- [x] 4.2 Add LICENSE_KEY validation to Makefile register target
- [x] 4.3 Add LICENSE_KEY validation to Makefile start target
- [x] 4.4 Update Makefile check-vars target to validate SERVICE_VERSION and LICENSE_KEY
- [x] 4.5 Update Makefile help target to document SERVICE_VERSION and LICENSE_KEY
- [x] 4.6 Verify .PHONY declaration includes all Makefile targets
- [x] 4.7 Update Makefile to reference SERVICE_VERSION in build targets
- [x] 4.8 Ensure SERVICE_VERSION is passed through to docker-compose commands
- [x] 4.9 Add SERVICE_VERSION to any build-related environment variable exports

## 5. Update Documentation

- [x] 5.1 Add SERVICE_VERSION section to README.md explaining purpose and usage
- [x] 5.2 Add LICENSE_KEY section to README.md explaining requirement for publish/register/start
- [x] 5.3 Document the default value behavior ("1.0.0" when SERVICE_VERSION not set)
- [x] 5.4 Add examples showing how to set both variables for each node type
- [x] 5.5 Document best practices (explicit versions for production, secure LICENSE_KEY handling)
- [x] 5.6 Add both variables to environment variable reference table
- [x] 5.7 Update .bob/AGENTS.md with SERVICE_VERSION and LICENSE_KEY information
- [x] 5.8 Update .claude/CLAUDE.md with SERVICE_VERSION and LICENSE_KEY information (if exists)
- [x] 5.9 Update relevant SKILL.md files to reference new validation requirements

## 6. Testing and Validation

- [ ] 6.1 Test deployment with SERVICE_VERSION set to valid semantic versions (e.g., "1", "1.0", "1.25.03")
- [ ] 6.2 Test deployment without SERVICE_VERSION defined (verify default "1.0.0" is used)
- [ ] 6.3 Test deployment with SERVICE_VERSION set to empty string (verify default "1.0.0" is applied)
- [ ] 6.4 Test deployment with invalid SERVICE_VERSION values (e.g., "latest", "dev") and verify rejection
- [ ] 6.5 Test Makefile publish target with LICENSE_KEY set (verify success)
- [ ] 6.6 Test Makefile publish target without LICENSE_KEY (verify failure with clear error)
- [x] 5.10 Add testing documentation section to README.md explaining how to validate configuration

- [ ] 6.7 Test Makefile register target with LICENSE_KEY set (verify success)
- [ ] 6.8 Test Makefile register target without LICENSE_KEY (verify failure with clear error)
- [ ] 6.9 Test Makefile start target with LICENSE_KEY set (verify success)
- [ ] 6.10 Test Makefile start target without LICENSE_KEY (verify failure with clear error)
- [ ] 6.11 Verify logging shows correct SERVICE_VERSION value during deployment
- [ ] 6.12 Test all node types (master, operator, query) with both variables

## 7. Create Service Validation Skill

- [x] 7.1 Create .bob/skills/test-anylog-service/SKILL.md
- [x] 7.2 Implement validation checks for SERVICE_VERSION (semantic version format)
- [x] 7.3 Implement validation checks for LICENSE_KEY (presence)
- [x] 7.4 Add checks for sane defaults in environment files
- [x] 7.5 Provide clear error messages and correction guidance
- [ ] 7.6 Test skill with valid and invalid configurations