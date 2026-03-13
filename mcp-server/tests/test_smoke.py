from server import health


def test_health() -> None:
    assert health()["ok"] is True
