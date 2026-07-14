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

**Important — verify `DOCKER_IMAGE_BASE`.** This is read from `docker-makefiles/.env` (gitignored).
Check that the `IMAGE=` line is set to the correct registry path:

```shell
cat docker-makefiles/.env | grep '^IMAGE'
```

If it shows the wrong image or is missing, ask the user for the correct value and update it:

```shell
sed -i '' 's|IMAGE=.*|IMAGE=<correct-image>|' docker-makefiles/.env
# On Linux omit the '' after -i
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

**Do not use `make publish-service`** — the Makefile suppresses all stderr with `@`, so failures
produce no useful output. Run the underlying `hzn` command directly with all required env vars
explicitly exported in the same shell invocation:

```shell
export SERVICE_NAME=service-edgelake-<NODE_TYPE> && \
export SERVICE_VERSION=2.0.2606 && \
export ARCH=$(hzn architecture) && \
export DOCKER_IMAGE_VERSION=2.0.2606 && \
export DOCKER_IMAGE_BASE=$(grep '^IMAGE' docker-makefiles/.env | awk -F '=' '{print $2}') && \
hzn exchange service publish \
  --org="$ORG" \
  --user-pw="${HZN_EXCHANGE_USER_AUTH}" \
  -O -P --json-file=service.definition.json 2>&1
```

After the command completes, verify:
```shell
hzn exchange service list
```
Confirm that `service-edgelake-<NODE_TYPE>_<version>_<arch>` appears in the list.

---

## Step 6 — Publish the service policy

**Do not use `make publish-service-policy`** — same stderr-suppression issue. Run directly:

```shell
hzn exchange service addpolicy \
  --org="$ORG" \
  --user-pw="${HZN_EXCHANGE_USER_AUTH}" \
  -f service.policy.json \
  "${ORG}/service-edgelake-<NODE_TYPE>_<version>_$(hzn architecture)" 2>&1
```

This attaches the constraint `purpose == edgelake AND openhorizon.allowPrivileged == true` to the
published service.

---

## Step 7 — Publish the deployment policy

**Do not use `make publish-deployment-policy`** — same stderr-suppression issue. Export the
required vars and run directly:

```shell
export SERVICE_NAME=service-edgelake-<NODE_TYPE> && \
export SERVICE_VERSION=2.0.2606 && \
export HZN_ORG_ID=$ORG && \
hzn exchange deployment addpolicy \
  --org="$ORG" \
  --user-pw="${HZN_EXCHANGE_USER_AUTH}" \
  -f service.deployment.json \
  "${ORG}/policy-service-edgelake-<NODE_TYPE>_<version>" 2>&1
```

Verify:
```shell
hzn exchange deployment listpolicy 2>&1 | grep edgelake
```
Confirm that `policy-service-edgelake-<NODE_TYPE>_<version>` appears in the output.

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
