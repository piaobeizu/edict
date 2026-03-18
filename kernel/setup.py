from setuptools import setup


setup(
    name="kernel",
    version="0.1.0",
    description="Framework-agnostic workflow engine kernel",
    package_dir={
        "kernel": "src",
        "kernel.adapters": "src/adapters",
    },
    packages=["kernel", "kernel.adapters"],
    python_requires=">=3.11",
    install_requires=[],
    extras_require={
        "postgres": ["sqlalchemy[asyncio]>=2.0", "asyncpg"],
        "redis": ["redis[hiredis]>=5.0"],
        "all": ["sqlalchemy[asyncio]>=2.0", "asyncpg", "redis[hiredis]>=5.0"],
        "dev": ["pytest>=8.0", "pytest-asyncio>=0.23"],
    },
)
