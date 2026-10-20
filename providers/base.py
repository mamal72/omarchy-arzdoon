"""Provider contract shared by Arzdoon's currency sources."""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import NotRequired, Protocol, TypedDict

type NumericValue = int | float

MAX_RESPONSE_BYTES = 2 * 1024 * 1024
MAX_PRICE_ROWS = 200
MAX_NAME_LENGTH = 64
MAX_PRICE_VALUE = 1e12
CODE_PATTERN = re.compile(r"[A-Z0-9][A-Z0-9-]{0,11}")


def valid_code(code: str) -> bool:
    """Currency codes are short ASCII identifiers; anything else is rejected."""
    return CODE_PATTERN.fullmatch(code) is not None


class ProviderMetadata(TypedDict):
    id: str
    name: str
    url: str


class PriceRow(TypedDict):
    code: str
    name: str
    buy: NumericValue | None
    sell: NumericValue | None
    direction: str


class ProviderSnapshot(TypedDict):
    schemaVersion: int
    provider: ProviderMetadata
    unit: str
    prices: list[PriceRow]


class CachedSnapshot(ProviderSnapshot):
    localUpdatedAt: str
    stale: bool


class RuntimeSnapshot(CachedSnapshot):
    selectedProvider: str
    pins: list[str]
    providers: list[ProviderMetadata]
    error: NotRequired[str]
    cacheReadAt: NotRequired[str]


@dataclass(frozen=True)
class ProviderInfo:
    id: str
    name: str
    url: str


class CurrencyProvider(Protocol):
    INFO: ProviderInfo

    def fetch(self, timeout: float) -> ProviderSnapshot: ...
