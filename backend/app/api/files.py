"""文件下载 API。"""

from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import FileResponse

router = APIRouter()

# 禁止下载的敏感文件后缀/名称
_BLOCKED_NAMES = {".env", "secrets", "credentials", "password", ".key", ".pem"}
_BLOCKED_SUFFIXES = {".env", ".key", ".pem", ".p12", ".pfx"}


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


def _is_sensitive(path: Path) -> bool:
    """检查是否为敏感文件（配置/密钥/凭证）。"""
    name_lower = path.name.lower()
    if name_lower in _BLOCKED_NAMES:
        return True
    if path.suffix.lower() in _BLOCKED_SUFFIXES:
        return True
    # 阻止 session/config 目录下的文件
    parts_lower = {p.lower() for p in path.parts}
    if "sessions" in parts_lower and path.suffix.lower() in {".json", ".jsonl"}:
        return True
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

    if _is_sensitive(resolved):
        raise HTTPException(status_code=403, detail="access to sensitive files is denied")

    return FileResponse(path=str(resolved), filename=resolved.name, media_type="application/octet-stream")
