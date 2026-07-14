---
name: publish-anylog-service
description: >
  Publish an AnyLog Open Horizon service definition, service policy, and deployment policy for a
  single node type (master, query, or operator). Use when the user says "publish AnyLog service",
  "publish deployment policy", "register Open Horizon service for master / query / operator",
  "prep-service", or asks to push AnyLog to the OH exchange for a specific node type.
---

# Publish AnyLog Service to Open Horizon

Follow these steps in order. Run all shell commands from the repo root using `execute_command`.
Do not skip validation steps — they catch the most common failure modes before `hzn` surfaces a
cryptic error.

---

## Step 1 — Confirm the node type

Ask (or confirm from context) which node type the user wants to publish. Valid short-form values
(the Makefile expands these to their full `anylog-<type>` prefix automatically):

- `master`
- `query`
- `operator`

Set `NODE_TYPE` to that value and use it throughout the remaining steps. The full `ANYLOG_TYPE`
value passed to `make` will be `anylog-<NODE_TYPE>` (e.g. `anylog-master`).

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

Also check that `make` is available:
```shell
make --version
```

**Important — resolve ORG for later steps.** `HZN_ORG_ID` is stored in `hzn`'s own config and is
**not** exported into shell subshells. Parse it once from `hzn exchange user list` and carry it
forward as a shell variable throughout Steps 5–7:

```shell
ORG=$(hzn exchange user list 2>/dev/null | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(list(d.keys())[0].split('/')[0])")
echo "ORG=$ORG"
```

**Important — verify container registry credentials.** `hzn exchange service publish` pulls the
image to sign it. Ensure the container runtime is authenticated before Step 5. Detect which runtime
is available and use it:

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

After installation, re-run the login check before proceeding to Step 5.
If credentials are not cached the user will need to supply them. Do not proceed to Step 5 until
login succeeds.

---

## Step 3 — Validate the node_configs.env configuration

Config files are stored per node type inside `docker-makefiles/`:

| Node type | Config file |
|-----------|-------------|
| `master`  | `docker-makefiles/anylog-master/node_configs.env` |
| `query`   | `docker-makefiles/anylog-query/node_configs.env` |
| `operator`| `docker-makefiles/anylog-operator/node_configs.env` |

Use `read_file` to read the file, then surface the following values to the user for confirmation:

| Field | What to check |
|-------|--------------|
| `NODE_NAME` | Should be unique and meaningful (not empty) — this becomes `SERVICE_NAME` |
| `COMPANY_NAME` | Should reflect the user's organisation (not the default `My Company`) |
| `ANYLOG_SERVER_PORT` | Expected defaults: master=32048, query=32348, operator=32148 |
| `ANYLOG_REST_PORT` | Expected defaults: master=32049, query=32349, operator=32149 |
| `LEDGER_CONN` | **Query and Operator only**: warn if still set to `127.0.0.1:32048` and ask whether this is a single-machine or multi-machine deployment. For multi-machine, the user must update this to the Master node's real IP before proceeding. |

If the user needs to update any field, use `search_and_replace` on the appropriate `node_configs.env`
file, then re-read it to confirm the change landed correctly.

---

## Step 4 — Run license-check and generate policy files

```shell
make prep-service ANYLOG_TYPE=anylog-<NODE_TYPE>
```

This runs `license-check` (resolves/prompts for `LICENSE_KEY` and writes it into `node_configs.env`)
followed by `docker-makefiles/env2json.sh`, which reads the config and writes four policy files
into `docker-makefiles/anylog-<NODE_TYPE>/`:

- `service.definition.json`
- `service.policy.json`
- `service.deployment.json`
- `node.policy.json`

After it completes, read `service.deployment.json` and show the user:
- The `NODE_TYPE` value in the `inputs` array
- The `LEDGER_CONN` value
- The service version (`TAG`)

Remind the user that Nebula and Remote-GUI variables are **intentionally absent** from the
generated file — they are excluded by design. Reference outputs for each node type live in
`sample-deployment-policy/`.

---

## Step 5 — Publish the service definition

**Do not use `make publish-service`** — the Makefile suppresses all stderr with `@`, so failures
produce no useful output. Resolve `SERVICE_NAME` from the config and run the underlying `hzn`
command directly:

```shell
export TAG=2.0.2606
export SERVICE_NAME=$(grep -m1 '^NODE_NAME=' docker-makefiles/anylog-<NODE_TYPE>/node_configs.env | cut -d= -f2- | tr -d '"')
export ARCH=$(hzn architecture)
hzn exchange service publish \
  --org="$ORG" \
  --user-pw="${HZN_EXCHANGE_USER_AUTH}" \
  -O -P --json-file=docker-makefiles/anylog-<NODE_TYPE>/service.definition.json 2>&1
```

After the command completes, verify:
```shell
hzn exchange service list
```
Confirm that `${SERVICE_NAME}_${TAG}_${ARCH}` appears in the list.

---

## Step 6 — Publish the service policy

**Do not use `make publish-service-policy`** — same stderr-suppression issue. Run directly:

```shell
hzn exchange service addpolicy \
  --org="$ORG" \
  --user-pw="${HZN_EXCHANGE_USER_AUTH}" \
  -f docker-makefiles/anylog-<NODE_TYPE>/service.policy.json \
  "${ORG}/${SERVICE_NAME}_${TAG}_$(hzn architecture)" 2>&1
```

This attaches the constraint `purpose == edgelake AND openhorizon.allowPrivileged == true` to the
published service.

---

## Step 7 — Publish the deployment policy

**Do not use `make publish-deployment-policy`** — same stderr-suppression issue. Run directly:

```shell
hzn exchange deployment addpolicy \
  --org="$ORG" \
  --user-pw="${HZN_EXCHANGE_USER_AUTH}" \
  -f docker-makefiles/anylog-<NODE_TYPE>/service.deployment.json \
  "${ORG}/policy-${SERVICE_NAME}_${TAG}" 2>&1
```

Verify:
```shell
hzn exchange deployment listpolicy 2>&1 | grep "$SERVICE_NAME"
```
Confirm that `policy-${SERVICE_NAME}_${TAG}` appears in the output.

---

## Step 8 — Agent registration (optional — run on the edge node)

`make agent-run` registers the **local machine** as an OH agent. It must be run on the machine
where the AnyLog container will actually execute, not necessarily the machine running this skill.

Provide the user with the command to run on their target machine:

```shell
# Run on the edge / target machine
make agent-run ANYLOG_TYPE=anylog-<NODE_TYPE>

# Then watch for an agreement to form (30-120 seconds)
hzn agreement list

# View container logs once the container starts
make hzn-logs ANYLOG_TYPE=anylog-<NODE_TYPE>
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
make hzn-logs ANYLOG_TYPE=anylog-<NODE_TYPE>
```
