 # 3DWindPipe Automated Pipeline 

This is the repo for the automated slicing pipeline and AI integrations defined for the 3DW automated print farm.

## TODO before migration

- Reproduce pipeline stages exactly:
  - ingest webhook/job request
  - retrieve model from storage
  - image extraction
  - NSFW classification gate
  - slicer profile mapping
  - auto-orient
  - slicing
  - printer handoff + backend callback
- Preserve queue semantics:
  - FIFO behavior where required
  - explicit concurrency limits per heavy slicing step
- Make steps idempotent:
  - `jobId` as correlation and idempotency key
  - safe retries for non-terminal failures
- Keep backend callback contract stable:
  - do not break existing status payload expectations
- Define per-step failure policy:
  - retryable errors
  - terminal errors
  - manual review outcomes (for `grey_area` / unknown)

## Repo layout

```text
windpipe/
├── README.md
├── docs/
├── core/ # importable packages 
│   ├── slicing/ # script files for functionality 
│   │   ├── model_render/
│   │   └── tests/
├── mcp-server/
│   ├── src/
│   └── tests/
├── windmill/
│   ├── f/ # primary workflows run inside f 
│   │   └── pipeline/
│   │       ├── ingest_job.py
│   │       ├── extract_images.py
│   │       ├── classify_nsfw.py
│   │       ├── map_slicer_profile.py
│   │       ├── auto_orient.py
│   │       ├── slice_model.py
│   │       ├── send_to_3dque.py
│   │       └── callback_backend.py
│   └── u/ # for dev use and experiments
│   └── legacy/ # deprecated and unused pipeline workflows 
└── infra/
    └── windmill/
        ├── docker-compose.yml
        ├── docker-compose.local.yml
        ├── docker-compose.production.yml
        ├── Caddyfile
        ├── .env.example
        └── bootstrap/ # for first time setup and test assets
            └── test_assets/
```

### Windmill sync structure (`windmill/`)

- `windmill/f/`: workspace shared folder content (team-owned scripts and flows). This is where production pipeline definitions should live.
- `windmill/u/`: user-scoped content (personal experiments, scratch scripts, temporary drafts). Keep critical pipeline logic out of this path.
- `windmill/f/pipeline/*.py`: one script per pipeline stage. These should stay thin and orchestrate calls into `core/*` or service clients.

In practice: treat `f/` as source-of-truth for shared automation, and treat `u/` as non-critical developer space.

### Purpose of each top-level folder

- `docs/`: architecture notes, runbooks, migration decisions, and operational procedures.
- `core/`: deterministic domain logic for slicing and preprocessing; no orchestration concerns.
- `mcp-server/`: AI/agent-facing tool API that wraps `core/` in a stable interface.
- `windmill/`: exported Windmill scripts and flows only.
- `infra/windmill/`: Windmill runtime deployment and bootstrap artifacts.

### Purpose of Windmill pipeline scripts

- `windmill/f/pipeline/ingest_job.py`: validate incoming payload and normalize job context.
- `windmill/f/pipeline/extract_images.py`: generate preview/renders used by moderation and QA.
- `windmill/f/pipeline/classify_nsfw.py`: run moderation gate and return allow/review/block outcome.
- `windmill/f/pipeline/map_slicer_profile.py`: resolve slicer profile from printer/material/job metadata.
- `windmill/f/pipeline/auto_orient.py`: compute best orientation before slicing.
- `windmill/f/pipeline/slice_model.py`: execute slicing and produce machine-ready artifacts.
- `windmill/f/pipeline/send_to_3dque.py`: enqueue prepared print job to printer scheduler.
- `windmill/f/pipeline/callback_backend.py`: send final status/progress payload to backend.

### Purpose of Windmill infra files

- `infra/windmill/docker-compose*.yml`: environment-specific Windmill service definitions.
- `infra/windmill/Caddyfile`: reverse proxy and routing for Windmill services.
- `infra/windmill/.env.example`: safe template for required runtime env vars.
- `infra/windmill/bootstrap/test_assets/`: representative payloads/models for local flow validation.

## Layer responsibilities

- `core/*`: lower-level slicing and preprocessing logic (pure code, unit tested)
- `mcp-server/*`: standardized AI-agent tool interface over core packages
- `windmill/*`: orchestration scripts/flows only (thin glue, retries, state transitions)
- `infra/windmill/*`: self-host and environment bootstrap for local/prod Windmill runtime

## Local Windmill instance setup (container)

Use an isolated directory for local Windmill runtime files:

```bash
mkdir -p infra/windmill
cd infra/windmill

curl https://raw.githubusercontent.com/windmill-labs/windmill/main/docker-compose.yml -o docker-compose.yml
curl https://raw.githubusercontent.com/windmill-labs/windmill/main/Caddyfile -o Caddyfile
curl https://raw.githubusercontent.com/windmill-labs/windmill/main/.env -o .env

docker compose up -d
```

If port 80 conflicts with your existing stack, run Windmill on a dedicated host/domain or adjust compose/proxy config before `up -d`.

## First-time Windmill bootstrap

1. Open `http://localhost`
2. Login with default credentials (`admin@windmill.dev` / `changeme`)
3. Replace superadmin with a proper account
4. Create workspace, for example: `local-dev`
5. Configure base URL and instance settings

## Developer setup with `wmill` CLI

From repo root:

```bash
# install/update CLI (example package manager invocation may vary)
# see Windmill CLI docs for your OS

mkdir -p windmill
cd windmill

# Add workspace mapping (replace placeholders)
wmill workspace add local-dev <workspace_id> <remote_url>

# Initial pull without secrets/resources to keep git clean
wmill sync pull --skip-variables --skip-secrets --skip-resources
```

## Day-to-day developer workflow

```bash
# from windmill

# 1) edit scripts/flows in IDE under f/ and u/

# 2) regenerate metadata/lockfile after changing deps or main signature
wmill script generate-metadata

# 3) push updated scripts/flows back to local workspace
wmill sync push
```

Optional helpers:

```bash
# bootstrap a new script
wmill script bootstrap f/pipeline/new_step python3

# bootstrap a new flow
wmill flow bootstrap f/pipeline/vetting_pipeline

# regenerate metadata for one script
wmill script generate-metadata f/pipeline/slice_model.py
```

## Testing sequence (local)

1. Unit test `core/*`
2. Test MCP tool wrappers in `mcp-server/*`
3. Run Windmill script tests with representative job payloads
4. Run full flow with `infra/windmill/bootstrap/test_assets/*`
5. Validate backend callback payloads and status transitions

---

## GitHub workflow now (no production workspace yet)

- Keep GitHub as source of truth for pipeline code and Windmill definitions.
- Use branch-per-unit changes:
  - `feat/wm-ingest`
  - `feat/wm-nsfw-gate`
  - `feat/wm-slice-handoff`
- PRs should include:
  - core package changes
  - Windmill script/flow changes
  - tests and sample payload updates

Recommended local git sequence:

```bash
git checkout -b feat/wm-nsfw-gate
git add core mcp-server windmill README.md
git commit -m "feat(pipeline): add windmill nsfw gate flow and tool wrappers"
git push -u origin feat/wm-nsfw-gate
```

## For prod

When production workspace is introduced:

- Create Windmill workspaces: `staging` and `prod`
- Promote via GitHub-based flow:
  - merge to `main` -> sync/deploy to `staging`
  - run smoke tests
  - approval gate
  - sync/deploy to `prod`

The following must be done:
1. CLI sync in GitHub Actions (works with OSS/self-host)
2. Windmill Git Sync/workspace forks if enterprise features are enabled

## Server docker-compose setup

1. Clone this repository
2. Use `infra/windmill/` compose stack for Windmill services
3. Provide env/secrets through server-managed `.env` or secrets manager
4. Attach Windmill to existing reverse proxy/domain strategy
5. Keep Windmill Postgres persistent and backed up
6. Expose only intended public routes, keep workers internal
