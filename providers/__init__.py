"""Provider registry. Add adapters here without changing the UI contract."""

from . import alanchand
from .base import CurrencyProvider, ProviderMetadata

PROVIDERS: dict[str, CurrencyProvider] = {
    alanchand.INFO.id: alanchand,
}


def metadata() -> list[ProviderMetadata]:
    return [
        {"id": item.INFO.id, "name": item.INFO.name, "url": item.INFO.url}
        for item in PROVIDERS.values()
    ]


def get(provider_id: str) -> CurrencyProvider:
    try:
        return PROVIDERS[provider_id]
    except KeyError as exc:
        raise ValueError(f"unknown provider: {provider_id}") from exc
