# Deploying AnyLog via Open Horizon

This guide walks through deploying an AnyLog node onto a device managed by Open Horizon.
Each step maps to a single `make` target, so the entire process can be driven from the command line.

> **⚠️ Temporary:** AnyLog does not yet publish releases in the version format required by Open Horizon (`#.#.####`).
> Step 2 includes a temporary `prep-build` target that pulls your chosen image and retags it to a compatible format automatically.
> This step will be removed once compliant releases are available.

---

## Prerequisites

| Requirement | Details |
|---|---|
| Open Horizon | Agent installed and `hzn` CLI authenticated (`HZN_ORG_ID` + `HZN_EXCHANGE_USER_AUTH` set) |
| Docker / Podman | Running and authenticated to Docker Hub (`docker login`) |
| `jq` | Required by `env2json.sh` for JSON manipulation |
| `git` | Required by the container at first boot to clone deployment-scripts |
| `make` | Used to drive all commands in this guide |

---

## Step 1 — Clone the repository

```bash
git clone https://github.com/AnyLog-co/service-anylog.git
cd service-anylog
```

---

## Step 2 — Configure your node

Each node type has a configuration file under `docker-makefiles/<ANYLOG_TYPE>/node_configs.env`.
Open the file for your chosen type and set the values relevant to your environment:

```bash
vi docker-makefiles/anylog-generic/node_configs.env
```

Key variables to review:

- **`NODE_NAME`** — unique name for this node on the network
- **`ANYLOG_SERVER_PORT` / `ANYLOG_REST_PORT`** — TCP and REST ports
- **`LEDGER_CONN`** — IP:port of the master node (operator/query nodes only)
- **`COMPANY_NAME`** — owner of this node

Available node types:

| `ANYLOG_TYPE` | Role |
|---|---|
| `anylog-generic` | General-purpose node (good starting point) |
| `anylog-master` | Maintains the blockchain ledger |
| `anylog-operator` | Stores and serves data |
| `anylog-query` | Handles queries across the network |
| `anylog-publisher` | Publishes data into the network |
| `anylog-standalone-publisher` | Combined publisher with local storage |

---

## Step 3 — Pull and retag the image *(temporary)*

Because AnyLog releases do not yet use the `#.#.####` version format required by Open Horizon,
run `prep-build` first. This pulls the image under the original tag and pushes a retagged copy in the correct format.

```bash
make prep-build ANYLOG_TYPE=anylog-generic TAG=pre-develop
```

At the end of the command you will see the exact follow-up command to use, for example:

```
  make full-deploy ANYLOG_TYPE=anylog-generic TAG=1.0.20240601
```

> **Note:** Copy that printed `TAG` value — you will need it in Step 4.

> **Note:** Remove this step and the `prep-build` Makefile target once AnyLog publishes `#.#.####` releases.

---

## Step 4 — Deploy via Open Horizon

Run `full-deploy` with the retagged version from Step 3. This publishes the service, service policy,
and deployment policy to the Open Horizon exchange, then registers the agent.

```bash
make full-deploy ANYLOG_TYPE=anylog-generic TAG=<OH_VERSION>
```

What this does internally:

- **`publish-service`** — uploads the service definition to the exchange
- **`publish-service-policy`** — attaches the service policy
- **`publish-deployment-policy`** — generates and uploads node-specific JSON configs, then publishes the deployment policy
- **`agent-run`** — registers the local agent with its node policy and watches for agreement

> **Note:** The terminal will enter a watch loop (`hzn agreement list`) once registration is submitted. Press `Ctrl-C` once an agreement appears.

---

## Step 5 — Verify the deployment

Check that the agreement is established and the container is running:

```bash
make hzn-agreement-list ANYLOG_TYPE=anylog-generic
make hzn-logs ANYLOG_TYPE=anylog-generic CONTAINER_ID=<container-id>
```

You can also attach directly to the running container via Docker since Open Horizon manages
standard containers under the hood:

```bash
docker exec -it <container-id> /bin/bash
docker attach --detach-keys=ctrl-d <container-id>
```

Or verify via the AnyLog REST interface:

```bash
curl -X GET http://<NODE_IP>:<REST_PORT> -H "command: test node" -H "User-Agent: AnyLog/1.23"
```

---

## Step 6 — Tear down

To unregister the agent and remove the node from Open Horizon:

```bash
make hzn-clean ANYLOG_TYPE=anylog-generic
```

> **Note:** This only unregisters the agent. To remove published policies from the exchange, use the `hzn` CLI directly.

---

## Quick Reference

All commands assume `ANYLOG_TYPE=anylog-generic`. Substitute your chosen type as needed.

| Command | Purpose |
|---|---|
| `make prep-build ... TAG=XXX` | Pull + retag image to OH-compatible version *(temporary)* |
| `make full-deploy ... TAG=<OH>` | Publish service, policies, register agent |
| `make deploy ...` | Publish deployment policy + register agent (skips service publish) |
| `make publish ...` | Publish service + policies only (no agent registration) |
| `make hzn-agreement-list ...` | Show current Open Horizon agreements |
| `make deploy-check ...` | Validate policies before publishing |
| `make hzn-clean ...` | Unregister agent |
| `make check-vars ...` | Print all resolved variable values |