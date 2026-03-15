"""文件下载 API。"""

from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import FileResponse

router = APIRouter()


def _allowed_roots() -> list[Path]:
    roots = [
        Path("/app/data"),
        Path("/root/.openclaw"),
    ]
    return [p.resolve() for p in roots if p.exists()]


def _is_within(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
        return True
    except ValueError:
        return False


@router.get("/download")
async def download_file(path: str = Query(..., description="绝对文件路径")):
    p = Path(path)
    if not p.is_absolute():
        raise HTTPException(status_code=400, detail="path must be absolute")

    try:
        resolved = p.resolve(strict=True)
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="file not found")

    if not resolved.is_file():
        raise HTTPException(status_code=400, detail="path is not a file")

    allowed = _allowed_roots()
    if not any(_is_within(resolved, root) for root in allowed):
        raise HTTPException(status_code=403, detail="path not allowed")

    return FileResponse(path=str(resolved), filename=resolved.name, media_type="application/octet-stream")
