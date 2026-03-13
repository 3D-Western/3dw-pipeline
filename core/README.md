# Core Package

`core/` contains deterministic domain logic used by pipeline orchestration.

## Initialize and sync environment

From repo root:

```bash
cd core
uv sync
```

If this is a brand-new clone without a lock/env yet:

```bash
cd core
uv venv
uv sync
```

## Developer workflow

From `core/`:

```bash
# run tests
uv run pytest

# lint and type-check
uv run ruff check .
uv run mypy .
```

## Test strategy (scaffold)

Keep tests close to behavior risk and deterministic by default.

- `tests/unit/`: pure domain logic tests (no network, no external services)
- `slicing/tests/`: package-local tests specific to slicing modules

Do not place backend JSON/API contract tests in `core/`. Put those in `windmill/tests/` where orchestration/integration boundaries are tested.

Markers configured in `pyproject.toml`:

- `@pytest.mark.unit`

Run only unit tests:

```bash
uv run pytest -m unit
```

## Import usage

As logic grows, expose functions/modules from `slicing/` and import directly, for example:

```python
from slicing import some_domain_function
```
