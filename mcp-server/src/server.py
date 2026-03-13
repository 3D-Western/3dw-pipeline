from fastmcp import FastMCP

mcp = FastMCP("windpipe-mcp-server")


@mcp.tool()
def health() -> dict[str, bool | str]:
    return {"ok": True, "service": "mcp-server"}


if __name__ == "__main__":
    mcp.run(transport="stdio")
