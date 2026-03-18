"""SQLAlchemy async 引擎与 session 管理。"""

from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase

from .config import get_settings

settings = get_settings()

_engine_kwargs: dict = {
    "echo": settings.debug,
}
# pool 参数仅适用于支持连接池的后端（PostgreSQL），SQLite 不支持
if settings.database_url.startswith("postgresql"):
    _engine_kwargs.update({
        "pool_size": 10,
        "max_overflow": 20,
        "pool_pre_ping": True,
    })

engine = create_async_engine(settings.database_url, **_engine_kwargs)

async_session = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)


class Base(DeclarativeBase):
    """所有 ORM 模型的基类。"""
    pass


async def get_db() -> AsyncSession:
    """FastAPI 依赖注入 — 获取异步数据库 session。"""
    async with async_session() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise


async def init_db():
    """开发用 — 创建所有表（生产用 Alembic）。"""
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
