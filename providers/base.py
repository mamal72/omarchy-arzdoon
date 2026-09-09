"""Provider contract shared by Arzdoon's currency sources."""

from __future__ import annotations

from dataclasses import dataclass
from typing import NotRequired, Protocol, TypedDict

type NumericValue = int | float


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
