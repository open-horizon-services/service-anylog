---
name: deploy-edgelake-network
description: >
  Deploy a complete 3-node AnyLog network (Master, Query, Operator) to Open Horizon in the
  correct order. Use when the user says "deploy AnyLog network", "set up AnyLog master query
  operator", "full AnyLog deployment", "deploy all three nodes", or asks to bring up a complete
  AnyLog environment from scratch.
---

# Deploy a Full AnyLog Network to Open Horizon

This skill walks through publishing and registering all three AnyLog node types — **Master**,
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
  set as `LEDGER_CONN` in the Query and Operator config files.

### 1b — Node names

Ask for (or accept the defaults for) the three node names:

| Node | Config dir | `NODE_NAME` default |
|------|-----------|---------------------|
| Master | `docker-makefiles/anylog-master/` | _(empty — user must set)_ |
| Query | `docker-makefiles/anylog-query/` | _(empty — user must set)_ |
| Operator | `docker-makefiles/anylog-operator/` | _(empty — user must set)_ |

### 1c — Company name

Ask for the company / organisation name (default: `My Company`). This will be applied uniformly
across all three nodes via the `COMPANY_NAME` field in each `node_configs.env`.

### 1d — Prerequisites check

Run the prerequisite checks from the `publish-anylog-service` skill (Step 2):

```shell
hzn version
hzn exchange user list
make --version
```

If any check fails, stop and help the user resolve it before continuing.

**Resolve ORG.** `HZN_ORG_ID` is not exported into shell subshells — parse it once and carry it
forward as `$ORG` throughout all publish steps:

```shell
ORG=$(hzn exchange user list 2>/dev/null | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(list(d.keys())[0].split('/')[0])")
echo "ORG=$ORG"
```

**Verify container registry login.** `hzn` pulls the image to sign it during service publish.
Detect which runtime is available and authenticate:

```shell
if command -v podman &>/dev/null; then
  podman login docker.io
elif command -v docker &>/dev/null; then
  docker login docker.io
else
  echo "ERROR: neither podman nor docker found"
fi
```

If neither is installed, offer to install Docker for the user's platform before proceeding:
- **macOS**: `brew install --cask docker` (requires Homebrew), then open the Docker app to start the daemon
- **Linux (apt)**: `sudo apt-get update && sudo apt-get install -y docker.io && sudo systemctl enable --now docker`
- **Linux (dnf/yum)**: `sudo dnf install -y docker && sudo systemctl enable --now docker`

After installation, re-run the login check before proceeding.

---

## Step 2 — Configure all three node_configs.env files

Use `search_and_replace` to apply the values collected in Step 1 to each config file. After each
edit, use `read_file` to confirm the change is correct.

### Files to edit

| Node | Config file |
|------|-------------|
| Master | `docker-makefiles/anylog-master/node_configs.env` |
| Query | `docker-makefiles/anylog-query/node_configs.env` |
| Operator | `docker-makefiles/anylog-operator/node_configs.env` |

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
| `anylog-master/node_configs.env` | `NODE_NAME` | ... | ... |
| `anylog-master/node_configs.env` | `COMPANY_NAME` | ... | ... |
| `anylog-query/node_configs.env` | `NODE_NAME` | ... | ... |
| `anylog-query/node_configs.env` | `COMPANY_NAME` | ... | ... |
| `anylog-query/node_configs.env` | `LEDGER_CONN` | ... | ... |
| `anylog-operator/node_configs.env` | `NODE_NAME` | ... | ... |
| `anylog-operator/node_configs.env` | `COMPANY_NAME` | ... | ... |
| `anylog-operator/node_configs.env` | `LEDGER_CONN` | ... | ... |

Ask the user to confirm before proceeding to Step 3.

---

## Step 3 — Deploy the Master node

Follow all steps from the `publish-anylog-service` skill for `ANYLOG_TYPE=master`:

1. Run license-check and generate the deployment policy files:
   ```shell
   make prep-service ANYLOG_TYPE=master
   ```
   This runs `docker-makefiles/env2json.sh` and writes policy files into
   `docker-makefiles/anylog-master/`.

2. Read `SERVICE_NAME` — it is derived from `NODE_NAME` in the config:
   ```shell
   grep '^NODE_NAME=' docker-makefiles/anylog-master/node_configs.env
   ```

3. Publish service definition — run `hzn` directly (the Makefile suppresses all stderr with `@`,
   so failures produce no useful output; see `publish-anylog-service` skill Steps 5–7 for full
   commands):
   ```shell
   export TAG=2.0.2606
   export SERVICE_NAME=$(grep -m1 '^NODE_NAME=' docker-makefiles/anylog-master/node_configs.env | cut -d= -f2- | tr -d '"')
   export ARCH=$(hzn architecture)
   hzn exchange service publish --org="$ORG" --user-pw="${HZN_EXCHANGE_USER_AUTH}" -O -P \
     --json-file=docker-makefiles/anylog-master/service.definition.json 2>&1
   hzn exchange service addpolicy --org="$ORG" --user-pw="${HZN_EXCHANGE_USER_AUTH}" \
     -f docker-makefiles/anylog-master/service.policy.json \
     "${ORG}/${SERVICE_NAME}_${TAG}_${ARCH}" 2>&1
   hzn exchange deployment addpolicy --org="$ORG" --user-pw="${HZN_EXCHANGE_USER_AUTH}" \
     -f docker-makefiles/anylog-master/service.deployment.json \
     "${ORG}/policy-${SERVICE_NAME}_${TAG}" 2>&1
   ```

4. Verify the deployment policy appeared:
   ```shell
   hzn exchange deployment listpolicy 2>&1 | grep "$SERVICE_NAME"
   ```

5. Provide the agent-run command for the user to run on the Master machine:
   ```shell
   # Run on the master node machine
   make agent-run ANYLOG_TYPE=master
   ```

6. Ask the user to confirm the Master node is running before proceeding.
   Once they confirm, validate it:
   ```shell
   make test-node TEST_CONN=<master-ip>:32049
   ```
   The Master is healthy when `TCP`, `REST`, and `Blockchain Sync` all show `Running`.

Do **not** proceed to Step 4 until the Master passes `test-node`.

---

## Step 4 — Deploy the Query node

Follow all steps from the `publish-anylog-service` skill for `ANYLOG_TYPE=query`:

1. Generate the deployment policy:
   ```shell
   make prep-service ANYLOG_TYPE=query
   ```

2. Read `service.deployment.json` and confirm `LEDGER_CONN` is the correct Master IP:
   ```shell
   grep LEDGER_CONN docker-makefiles/anylog-query/service.deployment.json
   ```

3. Publish (run `hzn` directly — same reason as Step 3):
   ```shell
   export TAG=2.0.2606
   export SERVICE_NAME=$(grep -m1 '^NODE_NAME=' docker-makefiles/anylog-query/node_configs.env | cut -d= -f2- | tr -d '"')
   export ARCH=$(hzn architecture)
   hzn exchange service publish --org="$ORG" --user-pw="${HZN_EXCHANGE_USER_AUTH}" -O -P \
     --json-file=docker-makefiles/anylog-query/service.definition.json 2>&1
   hzn exchange service addpolicy --org="$ORG" --user-pw="${HZN_EXCHANGE_USER_AUTH}" \
     -f docker-makefiles/anylog-query/service.policy.json \
     "${ORG}/${SERVICE_NAME}_${TAG}_${ARCH}" 2>&1
   hzn exchange deployment addpolicy --org="$ORG" --user-pw="${HZN_EXCHANGE_USER_AUTH}" \
     -f docker-makefiles/anylog-query/service.deployment.json \
     "${ORG}/policy-${SERVICE_NAME}_${TAG}" 2>&1
   ```

4. Provide the agent-run command:
   ```shell
   # Run on the query node machine
   make agent-run ANYLOG_TYPE=query
   ```

5. Once the user confirms the Query node is running, validate:
   ```shell
   make test-node TEST_CONN=<query-ip>:32349
   ```
   The Query node is healthy when `TCP`, `REST`, `Blockchain Sync`, and `Query Pool` all show
   `Running`.

---

## Step 5 — Deploy the Operator node

Follow all steps from the `publish-anylog-service` skill for `ANYLOG_TYPE=operator`:

1. Generate the deployment policy:
   ```shell
   make prep-service ANYLOG_TYPE=operator
   ```

2. Read `service.deployment.json` and confirm `LEDGER_CONN` is the correct Master IP:
   ```shell
   grep LEDGER_CONN docker-makefiles/anylog-operator/service.deployment.json
   ```

3. Publish (run `hzn` directly — same reason as Step 3):
   ```shell
   export TAG=2.0.2606
   export SERVICE_NAME=$(grep -m1 '^NODE_NAME=' docker-makefiles/anylog-operator/node_configs.env | cut -d= -f2- | tr -d '"')
   export ARCH=$(hzn architecture)
   hzn exchange service publish --org="$ORG" --user-pw="${HZN_EXCHANGE_USER_AUTH}" -O -P \
     --json-file=docker-makefiles/anylog-operator/service.definition.json 2>&1
   hzn exchange service addpolicy --org="$ORG" --user-pw="${HZN_EXCHANGE_USER_AUTH}" \
     -f docker-makefiles/anylog-operator/service.policy.json \
     "${ORG}/${SERVICE_NAME}_${TAG}_${ARCH}" 2>&1
   hzn exchange deployment addpolicy --org="$ORG" --user-pw="${HZN_EXCHANGE_USER_AUTH}" \
     -f docker-makefiles/anylog-operator/service.deployment.json \
     "${ORG}/policy-${SERVICE_NAME}_${TAG}" 2>&1
   ```

4. Provide the agent-run command:
   ```shell
   # Run on the operator node machine
   make agent-run ANYLOG_TYPE=operator
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
Address               Node Type Node Name      Status
---------------------|---------|--------------|------|
<master-ip>:32048    |master   |<master-name> |  +   |
<query-ip>:32348     |query    |<query-name>  |  +   |
<operator-ip>:32148  |operator |<op-name>     |  +   |
```

If any node shows `-` or is missing from the list, check its logs:
```shell
make hzn-logs ANYLOG_TYPE=<node-type>
```

---

## Cleanup reference

To unregister any node's agent:
```shell
make hzn-clean-all ANYLOG_TYPE=<node-type>   # run on the respective node machine
```

To remove published artifacts from the exchange:
```shell
hzn exchange deployment removepolicy ${HZN_ORG_ID}/policy-${SERVICE_NAME}_${TAG}
hzn exchange service removepolicy ${HZN_ORG_ID}/${SERVICE_NAME}_${TAG}_$(hzn architecture)
hzn exchange service remove ${HZN_ORG_ID}/${SERVICE_NAME}_${TAG}_$(hzn architecture)
```
