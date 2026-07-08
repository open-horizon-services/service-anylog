---
name: publish-edgelake-service
description: >
  Publish an EdgeLake Open Horizon service definition, service policy, and deployment policy for a
  single node type (master, query, or operator). Use when the user says "publish EdgeLake service",
  "publish deployment policy", "register Open Horizon service for master / query / operator",
  "prep-service", or asks to push EdgeLake to the OH exchange for a specific node type.
---

# Publish EdgeLake Service to Open Horizon

Follow these steps in order. Run all shell commands from the repo root using `execute_command`.
Do not skip validation steps — they catch the most common failure modes before `hzn` surfaces a
cryptic error.

---

## Step 1 — Confirm the node type

Ask (or confirm from context) which node type the user wants to publish:

- `master`
- `query`
- `operator`

Set `NODE_TYPE` to that value and use it throughout the remaining steps.

---

## Step 2 — Validate prerequisites

Run these checks. If any fail, surface the error and stop.

```shell
hzn version
```
If `hzn` is not found: direct the user to install the Open Horizon CLI before continuing.

```shell
hzn exchange user list
```
If this fails: the required environment variables are likely not set. Remind the user to export:

```shell
export HZN_ORG_ID=<your-org>
export HZN_EXCHANGE_USER_AUTH=<user>:<password-or-api-key>
export HZN_EXCHANGE_URL=<exchange-url>      # e.g. http://localhost:3090/v1
export HZN_FSS_CSSURL=<css-url>            # e.g. http://localhost:9443/
```

Also check that `python3` and `make` are available:
```shell
python3 --version && make --version
```

---

## Step 3 — Validate the dotenv configuration

Read the dotenv file for the chosen node type:

| Node type | Dotenv file |
|-----------|-------------|
| `master`  | `docker-makefiles/edgelake_master.env` |
| `query`   | `docker-makefiles/edgelake_query.env` |
| `operator`| `docker-makefiles/edgelake_operator.env` |

Use `read_file` to read the file, then surface the following values to the user for confirmation:

| Field | What to check |
|-------|--------------|
| `NODE_NAME` | Should be unique and meaningful (not the default `edgelake-node`) |
| `COMPANY_NAME` | Should reflect the user's organisation (not the default `New Company`) |
| `ANYLOG_SERVER_PORT` | Expected defaults: master=32048, query=32348, operator=32148 |
| `ANYLOG_REST_PORT` | Expected defaults: master=32049, query=32349, operator=32149 |
| `LEDGER_CONN` | **Query and Operator only**: warn if still set to `127.0.0.1:32048` and ask whether this is a single-machine or multi-machine deployment. For multi-machine, the user must update this to the Master node's real IP before proceeding. |

If the user needs to update any field, use `search_and_replace` on the appropriate env file, then
re-read it to confirm the change landed correctly.

---

## Step 4 — Generate the deployment policy

```shell
make prep-service EDGELAKE_TYPE=<NODE_TYPE>
```

This runs `create_policy.py` which reads the dotenv file and writes `service.deployment.json` at
the repo root. After it completes, read `service.deployment.json` and show the user:
- The `NODE_TYPE` value in the `inputs` array
- The `LEDGER_CONN` value
- The service version

Remind the user that Nebula and Remote-CLI variables are **intentionally absent** from the
generated file — they are excluded by design. Reference outputs for each node type live in
`sample-deployment-policy/`.

---

## Step 5 — Publish the service definition

```shell
make publish-service EDGELAKE_TYPE=<NODE_TYPE>
```

After the command completes, verify:
```shell
hzn exchange service list
```
Confirm that `service-edgelake-<NODE_TYPE>` appears in the list. If publish fails with an auth
error, re-check `HZN_EXCHANGE_USER_AUTH`.

---

## Step 6 — Publish the service policy

```shell
make publish-service-policy EDGELAKE_TYPE=<NODE_TYPE>
```

This attaches the constraint `purpose == edgelake AND openhorizon.allowPrivileged == true` to the
published service. No separate verification command is needed unless the user requests it.

---

## Step 7 — Publish the deployment policy

```shell
make publish-deployment-policy EDGELAKE_TYPE=<NODE_TYPE>
```

Note: this target automatically re-runs `prep-service` (Step 4) — so if the dotenv was updated
after Step 4, the regenerated file will reflect those changes.

Verify:
```shell
hzn exchange deployment listpolicy
```
Confirm that `policy-service-edgelake-<NODE_TYPE>_<version>` appears in the list.

---

## Step 8 — Agent registration (optional — run on the edge node)

`make agent-run` registers the **local machine** as an OH agent. It must be run on the machine
where the EdgeLake container will actually execute, not necessarily the machine running this skill.

Provide the user with the command to run on their target machine:

```shell
# Run on the edge / target machine
make agent-run EDGELAKE_TYPE=<NODE_TYPE>

# Then watch for an agreement to form (30-120 seconds)
hzn agreement list

# View container logs once the container starts
make hzn-logs EDGELAKE_TYPE=<NODE_TYPE>
```

Ask the user whether they want to run `agent-run` now (if they are on the target machine) or
whether they will run it separately. Do not block — proceed to Step 9 either way.

---

## Step 9 — Validate the node

Once the node is running, test it:

```shell
make test-node TEST_CONN=<node-ip>:<rest-port>
```

Default REST ports: master=32049, query=32349, operator=32149.

Surface the output. A healthy node shows all key processes as `Running`:
- `TCP` — Running
- `REST` — Running
- `Blockchain Sync` — Running
- `Scheduler` — Running
- Node-type-specific process (`Operator`, `Query Pool`, etc.) — Running

If any required process is `Not declared` or absent, check the container logs:
```shell
make hzn-logs EDGELAKE_TYPE=<NODE_TYPE>
```
