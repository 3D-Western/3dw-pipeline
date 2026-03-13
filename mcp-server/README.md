# WindPipe MCP Server

The MCP server for integrating AI agents into automated slicing workflows.

## Initialize project with uv

From repo root:

```bash
cd mcp-server
uv init --python 3.12
uv venv
uv add fastmcp fastapi
uv add --dev pytest ruff mypy
uv sync
```

## Developer workflow

From `mcp-server/`:

```bash
# Sync environment after pulling changes
uv sync

# Run tests and checks
uv run pytest
uv run ruff check .
uv run mypy src
```

## Run FastMCP server (stdio)

Use this for local MCP client integrations that launch the server process directly:

```bash
cd mcp-server
uv run fastmcp run src/server.py:mcp -t stdio
```

## Run FastMCP server for network clients

FastMCP in this setup exposes `stdio`, `http`, `sse`, and `streamable-http` transports.
There is no direct gRPC transport flag in `fastmcp run` here, so use HTTP transport and place a gRPC proxy/gateway in front if gRPC is required.

```bash
cd mcp-server
uv run fastmcp run src/server.py:mcp -t http --host 0.0.0.0 --port 8000 --path /mcp/
```

With auto-reload:

```bash
uv run fastmcp run src/server.py:mcp -t http --host 0.0.0.0 --port 8000 --path /mcp/ --reload
```

## Project layout

- `src/server.py`: FastMCP server instance (`mcp`) and tool registration
- `tests/`: unit and smoke tests
- `pyproject.toml`: dependencies and project metadata
- `uv.lock`: locked dependency graph
