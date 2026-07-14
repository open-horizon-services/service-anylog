# Plan: Publishing AnyLog Service Definition and Deployment Policies

## Top-Level Overview

**Goal**: Produce two artifacts:
1. **Human-readable step-by-step instructions** embedded in the existing [`deploy_anylog_service.md`](deploy_anylog_service.md) — covering prerequisites, configuration, and publishing for Master, Query, and Operator nodes on both single-machine and multi-machine setups.
2. **Two Bob skills** (SKILL.md files in `.bob/skills/`) that automate and guide the Open Horizon publishing workflow from the command line.

**Scope**:
- Covers all three node types: **Master**, **Query**, **Operator**
- Covers both **single-machine testing** (all nodes on one host) and **multi-machine production** deployments
- Includes explicit instructions for updating `LEDGER_CONN` to the real Master IP before publishing

**Files touched**:
- [`deploy_anylog_service.md`](deploy_anylog_service.md) — extended with a new "Publishing to Open Horizon" section
- [`.bob/skills/publish-anylog-service/SKILL.md`](.bob/skills/publish-anylog-service/SKILL.md) — new skill (workspace-scoped): validates environment and publishes service + policies for a single node type
- [`.bob/skills/deploy-anylog-network/SKILL.md`](.bob/skills/deploy-anylog-network/SKILL.md) — new skill (workspace-scoped): walks through full network deployment in order (Master → Query → Operator)

**Decisions**:
- Both SKILL.md files are workspace-scoped (inside this repo at `.bob/skills/`)
- `make agent-run` is treated as **always optional** — the user is assumed to be on any machine (management hub or otherwise); the skill will provide the command to run but will not block or automate it

**Publishing sequence** (same for all node types):
```
configure dotenv → publish-service → publish-service-policy → publish-deployment-policy → agent-run
```
Master must be fully running before Query or Operator are registered, because both require a valid `LEDGER_CONN`.

---

## Sub-Task 1 — Extend deploy_anylog_service.md with Open Horizon Publishing Instructions

**Status**: `[x] done`

### Intent
The existing [`deploy_anylog_service.md`](deploy_anylog_service.md) covers Docker deployment well but only briefly describes Open Horizon publishing with minimal detail. This sub-task extends it with a dedicated "Publishing to Open Horizon" section that is thorough enough for a new operator to follow without prior knowledge.

### Expected Outcomes
- [`deploy_anylog_service.md`](deploy_anylog_service.md) has a new "## Publishing to Open Horizon" section added after the existing "### Steps Deployment" section
- Section covers:
  - Prerequisites (hzn CLI, env vars, Docker image access)
  - How to configure each node's dotenv file (what fields to change per node type, and why)
  - The `LEDGER_CONN` IP caveat for multi-machine vs single-machine
  - The full publishing sequence for each node type with explicit `make` commands
  - The correct order to deploy a full 3-node network
  - How to validate each published artifact (`hzn exchange service list`, `hzn agreement list`, etc.)
  - How to unpublish / clean up

### Todo List
1. Add a "## Publishing to Open Horizon" section to [`deploy_anylog_service.md`](deploy_anylog_service.md) after the existing "### Steps Deployment" subsection (around line 170).
2. Under "### Prerequisites", document:
   - Required tools: `hzn` CLI, `python` or `python3`, `make`
   - Required environment variables: `HZN_ORG_ID`, `HZN_EXCHANGE_USER_AUTH`, `HZN_EXCHANGE_URL`, `HZN_FSS_CSSURL`
   - How to verify the exchange connection: `hzn exchange user list`
   - Architecture detection: `hzn architecture` (amd64 vs aarch64/arm64 — the Makefile already handles the image version suffix)
3. Under "### Configure the Node's dotenv File", for each node type, list the fields that **must** be changed before publishing:
   - **All nodes**: `NODE_NAME` (unique per node), `COMPANY_NAME`
   - **Query and Operator**: `LEDGER_CONN` must point to the Master node's real IP:PORT
   - **Single-machine caveat**: when `TCP_BIND=false` (default), `127.0.0.1` works; when `TCP_BIND=true`, use the host's real IP
   - **Multi-machine caveat**: always use the real IP in `LEDGER_CONN`, never `127.0.0.1`
   - Show the canonical port assignments in a table (master: 32048/32049, query: 32348/32349, operator: 32148/32149)
4. Under "### Publishing a Node", show the full `make` command sequence and the equivalent raw `hzn` commands for users who don't use Make:
   - `make publish-service`
   - `make publish-service-policy`
   - `make publish-deployment-policy` (which auto-runs `prep-service` / `create_policy.py` first)
   - `make agent-run`
   - Convenience shortcuts: `make publish`, `make deploy`, `make full-deploy`
5. Under "### Deploying a Full 3-Node Network", show the order (Master first), with a note that publishing steps can be done centrally from the management hub while agent-run is done on each edge node.
6. Under "### Verifying Published Artifacts", include the validation commands:
   - `hzn exchange service list`
   - `hzn exchange deployment listpolicy`
   - `hzn agreement list`
   - `make test-node TEST_CONN=<ip>:<port>`
   - `make test-network TEST_CONN=<ip>:<port>`
7. Under "### Unpublishing / Cleanup", document `make hzn-clean`.

### Relevant Context
- [`deploy_anylog_service.md`](deploy_anylog_service.md): existing file to be extended, not replaced
- [`Makefile`](Makefile) lines 104–146: all OpenHorizon targets and their `hzn` equivalents
- [`create_policy.py`](create_policy.py): called by `prep-service`; reads the dotenv, writes `service.deployment.json`
- [`docker-makefiles/anylog_master.env`](docker-makefiles/anylog_master.env), [`anylog_query.env`](docker-makefiles/anylog_query.env), [`anylog_operator.env`](docker-makefiles/anylog_operator.env): per-node config files with commented fields
- [`sample-deployment-policy/`](sample-deployment-policy/): reference output for each node type

---

## Sub-Task 2 — Create `publish-anylog-service` Skill

**Status**: `[x] done`

### Intent
A focused skill that guides the user (or automates) publishing the service definition, service policy, and deployment policy for a **single node type**. The skill validates the environment first, then runs the correct `make` targets in sequence, surfacing any issues before they become cryptic `hzn` errors.

### Expected Outcomes
- File created: `.bob/skills/publish-anylog-service/SKILL.md`
- Skill activates when user asks to publish an AnyLog service, policy, or deployment for a specific node type
- Skill checks prerequisites (hzn installed, env vars set, dotenv configured) before running any commands
- Skill runs `make publish` then `make agent-run` (or the individual targets) with appropriate `ANYLOG_TYPE` set
- Skill confirms success at each step before proceeding

### Todo List
1. Create the directory `.bob/skills/publish-anylog-service/`.
2. Write `.bob/skills/publish-anylog-service/SKILL.md` with:
   - **Frontmatter**: `name: publish-anylog-service`, description targeting phrases like "publish AnyLog service", "publish deployment policy", "register Open Horizon service for master/query/operator"
   - **Step 1 — Gather node type**: Ask for or confirm `ANYLOG_TYPE` (master, query, or operator)
   - **Step 2 — Validate prerequisites**: Use `execute_command` to check `hzn version`, `hzn exchange user list`, and that required env vars are set (`HZN_ORG_ID`, `HZN_EXCHANGE_USER_AUTH`)
   - **Step 3 — Validate dotenv configuration**: Read the appropriate `docker-makefiles/anylog_<type>.env` file; surface `NODE_NAME`, `COMPANY_NAME`, `LEDGER_CONN`, and port values for the user to confirm; warn if `LEDGER_CONN` is still `127.0.0.1` for query/operator nodes on a multi-machine setup
   - **Step 4 — Run `make prep-service`**: Generate `service.deployment.json` from the dotenv; show the generated file so the user can confirm it looks right
   - **Step 5 — Publish service**: Run `make publish-service ANYLOG_TYPE=<type>`; verify via `hzn exchange service list`
   - **Step 6 — Publish service policy**: Run `make publish-service-policy ANYLOG_TYPE=<type>`
   - **Step 7 — Publish deployment policy**: Run `make publish-deployment-policy ANYLOG_TYPE=<type>`; verify via `hzn exchange deployment listpolicy`
   - **Step 8 — Register agent (optional)**: Provide the `make agent-run ANYLOG_TYPE=<type>` command for the user to run on the appropriate machine (edge node or local if all-in-one); do not block on it
   - **Step 9 — Validate**: Run `make test-node TEST_CONN=<ip>:<rest-port>` and surface the output

### Relevant Context
- [`Makefile`](Makefile): all target names and their hzn equivalents
- [`create_policy.py`](create_policy.py): generates `service.deployment.json`; outputs to repo root
- [`sample-deployment-policy/`](sample-deployment-policy/): reference output for reviewing generated policy
- Skill name regex: `^[a-z0-9]+(-[a-z0-9]+)*$` — `publish-anylog-service` is valid

---

## Sub-Task 3 — Create `deploy-anylog-network` Skill

**Status**: `[x] done`

### Intent
A higher-level skill that walks the user through deploying a complete 3-node AnyLog network (Master + Query + Operator) in the correct order, on either a single machine or multiple machines. This composes the single-node publish workflow three times, enforcing the correct sequence and confirming each node is healthy before moving to the next.

### Expected Outcomes
- File created: `.bob/skills/deploy-anylog-network/SKILL.md`
- Skill activates when user asks to deploy an AnyLog network, set up a full AnyLog/AnyLog environment, or deploy master/query/operator together
- Skill collects the deployment topology (single-machine or multi-machine), IP addresses, and company details upfront
- Skill guides through Master → Query → Operator in order, waiting for Master to be healthy before configuring `LEDGER_CONN` for the others
- Skill patches the `LEDGER_CONN` value in the query and operator dotenv files when the real Master IP is provided

### Todo List
1. Create the directory `.bob/skills/deploy-anylog-network/`.
2. Write `.bob/skills/deploy-anylog-network/SKILL.md` with:
   - **Frontmatter**: `name: deploy-anylog-network`, description targeting phrases like "deploy AnyLog network", "set up AnyLog master query operator", "full AnyLog deployment"
   - **Step 1 — Gather topology**:
     - Single-machine or multi-machine?
     - If multi-machine: collect the IP address of the machine hosting the Master node
     - Collect `COMPANY_NAME` (used across all nodes)
     - Collect desired node names (or use defaults: anylog-master, anylog-query, anylog-operator1)
   - **Step 2 — Configure dotenv files**:
     - Patch `NODE_NAME` and `COMPANY_NAME` in all three env files using `search_and_replace`
     - For multi-machine: patch `LEDGER_CONN` in query and operator env files to `<master-ip>:32048`
     - Show a diff summary of what was changed before proceeding
   - **Step 3 — Deploy Master node**: Run the `publish-anylog-service` skill steps for `ANYLOG_TYPE=master`; provide the `agent-run` command for the user to run; before proceeding confirm the user has started the Master node and that `make test-node TEST_CONN=<master-ip>:32049` passes
   - **Step 4 — Deploy Query node**: Invoke the `publish-anylog-service` skill steps for `ANYLOG_TYPE=query`
   - **Step 5 — Deploy Operator node**: Invoke the `publish-anylog-service` skill steps for `ANYLOG_TYPE=operator`
   - **Step 6 — Validate the full network**: Run `make test-network TEST_CONN=<query-ip>:32349` and confirm all three nodes appear in the output table

### Relevant Context
- [`docker-makefiles/anylog_master.env`](docker-makefiles/anylog_master.env), [`anylog_query.env`](docker-makefiles/anylog_query.env), [`anylog_operator.env`](docker-makefiles/anylog_operator.env): files to be patched
- Single-machine note: all three nodes can share the same host; each has distinct ports; `LEDGER_CONN=127.0.0.1:32048` works when `TCP_BIND=false`
- Multi-machine note: the Master IP must be the real network IP, not loopback
- Skill name regex validation: `deploy-anylog-network` is valid

---

## Deployment Order Reference (for both artifacts)

```
Master (publish + register) → Query (publish + register) → Operator (publish + register)
```

### Port Assignments

| Node Type | TCP Port | REST Port | `LEDGER_CONN` default |
|-----------|----------|-----------|----------------------|
| master    | 32048    | 32049     | 127.0.0.1:32048      |
| query     | 32348    | 32349     | 127.0.0.1:32048      |
| operator  | 32148    | 32149     | 127.0.0.1:32048      |

### Key Files per Node Type

| File | Master | Query | Operator |
|------|--------|-------|----------|
| dotenv | [`anylog_master.env`](docker-makefiles/anylog_master.env) | [`anylog_query.env`](docker-makefiles/anylog_query.env) | [`anylog_operator.env`](docker-makefiles/anylog_operator.env) |
| sample deployment policy | [`master.deployment.json`](sample-deployment-policy/master.deployment.json) | [`query.deployment.json`](sample-deployment-policy/query.deployment.json) | [`operator.deployment.json`](sample-deployment-policy/operator.deployment.json) |
