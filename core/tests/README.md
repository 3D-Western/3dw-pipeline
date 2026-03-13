# Core Test Layout

- `unit/`: deterministic tests for domain logic

Guidelines:

- Keep unit tests fast and side-effect free.
- Avoid API contract/schema concerns in `core/`; keep those in `windmill/tests/`.
