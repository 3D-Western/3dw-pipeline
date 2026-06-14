# 3dw-pipeline

This project is a durable execution pipeline for processing incoming 3D print requests. The project consists of a Go HTTPS web server that serves webhook(s), a Restate Go SDK to use the Restate server and Docker during development and production.


## Files 

- `cmd/`: Go web server entry point
- `internal/`: Internal deps for the Go app
- `docs/`: documentation regarding pipeline general direction and legacy pipeline information. Do not read the contents of this folder unless prompted, which may consist of stale information
- `skills/`: contains skills and documentation on how to develop with Restate
- `Dockerfile.orcaslicer`
- `docker-compose.yml`
- `go.mod`
- `render_stl.sh`: Bash script that uses OpenSCAD to render images 

## Best practices 

- Do NOT read README.md in project root unless otherwise prompted; it is reserved for human usage.
- When unsure, ask the human about design choices. Make the least number of assumptions in this project because domain expertise and HITL are required for the pipeline design process.
- Treat docs as a second class citizen, because docs are likely to be stale. Always read source code and treat it as a single source of truth.
- Do NOT run `go mod tidy` unless prompted by the user.
