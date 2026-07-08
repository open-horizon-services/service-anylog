---
name: deploy-edgelake-network
description: >
  Deploy a complete 3-node EdgeLake network (Master, Query, Operator) to Open Horizon in the
  correct order. Use when the user says "deploy EdgeLake network", "set up AnyLog master query
  operator", "full EdgeLake deployment", "deploy all three nodes", or asks to bring up a complete
  EdgeLake environment from scratch.
---

# Deploy a Full EdgeLake Network to Open Horizon

This skill walks through publishing and registering all three EdgeLake node types — **Master**,
**Query**, and **Operator** — in the correct order. Master must be running before Query or Operator
can connect, because both depend on a valid `LEDGER_CONN` pointing at the Master.

Run all shell commands from the repo root using `execute_command`. Use `read_file` and
`search_and_replace` for file inspection and edits.

---

## Step 1 — Gather topology and configuration

Ask the user the following questions before touching any files. Collect all answers first.

### 1a — Deployment topology

> Is this a **single-machine** deployment (all three nodes on one host, e.g. for testing) or a
> **multi-machine** deployment (each node on a separate host)?

- **Single-machine**: `LEDGER_CONN=127.0.0.1:32048` works as-is (when `TCP_BIND=false`).
- **Multi-machine**: collect the Master node's real network IP (e.g. `192.168.1.10`). This will be
  set as `LEDGER_CONN` in the Query and Operator env files.

### 1b — Node names

Ask for (or accept the defaults for) the three node names:

| Node | Default |
|------|---------|
| Master | `edgelake-master` |
| Query | `edgelake-query` |
| Operator | `edgelake-operator1` |

### 1c — Company name

Ask for the company / organisation name (default: `New Company`). This will be applied uniformly
across all three nodes.

### 1d — Prerequisites check

Run the prerequisite checks from the `publish-edgelake-service` skill (Steps 2):

```shell
hzn version
hzn exchange user list
python3 --version && make --version
```

If any check fails, stop and help the user resolve it before continuing.

---

## Step 2 — Configure all three dotenv files

Use `search_and_replace` to apply the values collected in Step 1 to each env file. After each
edit, use `read_file` to confirm the change is correct.

### Files to edit

| Node | File |
|------|------|
| Master | `docker-makefiles/edgelake_master.env` |
| Query | `docker-makefiles/edgelake_query.env` |
| Operator | `docker-makefiles/edgelake_operator.env` |

### Changes to apply

**All three files** — update `NODE_NAME` and `COMPANY_NAME`:
```
NODE_NAME=<collected-name>
COMPANY_NAME=<collected-company>
```

**Query and Operator only** — update `LEDGER_CONN`:
- Single-machine: leave `LEDGER_CONN=127.0.0.1:32048` unchanged.
- Multi-machine: set to `LEDGER_CONN=<master-ip>:32048`.

### Summary

After all edits, show the user a brief summary table of what was changed:

| File | Field | Old value | New value |
|------|-------|-----------|-----------|
| `edgelake_master.env` | `NODE_NAME` | ... | ... |
| `edgelake_master.env` | `COMPANY_NAME` | ... | ... |
| `edgelake_query.env` | `NODE_NAME` | ... | ... |
| `edgelake_query.env` | `COMPANY_NAME` | ... | ... |
| `edgelake_query.env` | `LEDGER_CONN` | ... | ... |
| `edgelake_operator.env` | `NODE_NAME` | ... | ... |
| `edgelake_operator.env` | `COMPANY_NAME` | ... | ... |
| `edgelake_operator.env` | `LEDGER_CONN` | ... | ... |

Ask the user to confirm before proceeding to Step 3.

---

## Step 3 — Deploy the Master node

Follow all steps from the `publish-edgelake-service` skill for `EDGELAKE_TYPE=master`:

1. Generate the deployment policy:
   ```shell
   make prep-service EDGELAKE_TYPE=master
   ```
2. Publish service definition, service policy, and deployment policy:
   ```shell
   make publish EDGELAKE_TYPE=master
   ```
3. Verify the deployment policy appeared:
   ```shell
   hzn exchange deployment listpolicy
   ```
4. Provide the agent-run command for the user to run on the Master machine:
   ```shell
   # Run on the master node machine
   make agent-run EDGELAKE_TYPE=master
   ```
5. Ask the user to confirm the Master node is running before proceeding.
   Once they confirm, validate it:
   ```shell
   make test-node TEST_CONN=<master-ip>:32049
   ```
   The Master is healthy when `TCP`, `REST`, and `Blockchain Sync` all show `Running`.

Do **not** proceed to Step 4 until the Master passes `test-node`.

---

## Step 4 — Deploy the Query node

Follow all steps from the `publish-edgelake-service` skill for `EDGELAKE_TYPE=query`:

1. Generate the deployment policy:
   ```shell
   make prep-service EDGELAKE_TYPE=query
   ```
2. Read `service.deployment.json` and confirm `LEDGER_CONN` is the correct Master IP.
3. Publish:
   ```shell
   make publish EDGELAKE_TYPE=query
   ```
4. Provide the agent-run command:
   ```shell
   # Run on the query node machine
   make agent-run EDGELAKE_TYPE=query
   ```
5. Once the user confirms the Query node is running, validate:
   ```shell
   make test-node TEST_CONN=<query-ip>:32349
   ```
   The Query node is healthy when `TCP`, `REST`, `Blockchain Sync`, and `Query Pool` all show
   `Running`.

---

## Step 5 — Deploy the Operator node

Follow all steps from the `publish-edgelake-service` skill for `EDGELAKE_TYPE=operator`:

1. Generate the deployment policy:
   ```shell
   make prep-service EDGELAKE_TYPE=operator
   ```
2. Read `service.deployment.json` and confirm `LEDGER_CONN` is the correct Master IP.
3. Publish:
   ```shell
   make publish EDGELAKE_TYPE=operator
   ```
4. Provide the agent-run command:
   ```shell
   # Run on the operator node machine
   make agent-run EDGELAKE_TYPE=operator
   ```
5. Once the user confirms the Operator node is running, validate:
   ```shell
   make test-node TEST_CONN=<operator-ip>:32149
   ```
   The Operator node is healthy when `TCP`, `REST`, `Blockchain Sync`, `Operator`, and `Streamer`
   all show `Running`.

---

## Step 6 — Validate the full network

Run `test-network` from any node's REST port (the Query node is the natural choice):

```shell
make test-network TEST_CONN=<query-ip>:32349
```

Surface the output to the user. A healthy 3-node network shows all three nodes with status `+`:

```
Address               Node Type Node Name          Status
---------------------|---------|------------------|------|
<master-ip>:32048    |master   |edgelake-master   |  +   |
<query-ip>:32348     |query    |edgelake-query    |  +   |
<operator-ip>:32148  |operator |edgelake-operator1|  +   |
```

If any node shows `-` or is missing from the list, check its logs:
```shell
make hzn-logs EDGELAKE_TYPE=<node-type>
```

---

## Cleanup reference

To unregister any node's agent:
```shell
make hzn-clean   # run on the respective node machine
```

To remove published artifacts from the exchange:
```shell
hzn exchange deployment removepolicy ${HZN_ORG_ID}/policy-service-edgelake-<type>_${SERVICE_VERSION}
hzn exchange service removepolicy ${HZN_ORG_ID}/service-edgelake-<type>_${SERVICE_VERSION}_$(hzn architecture)
hzn exchange service remove ${HZN_ORG_ID}/service-edgelake-<type>_${SERVICE_VERSION}_$(hzn architecture)
```
