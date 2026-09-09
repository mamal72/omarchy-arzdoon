"""Provider-independent filtering and display order for currency snapshots."""

from __future__ import annotations

from providers.base import PriceRow, ProviderSnapshot

CANONICAL_ORDER = (
    "USD",
    "EUR",
    "AED",
    "TRY",
    "GBP",
    "CNY",
    "CAD",
    "AUD",
    "RUB",
    "IQD",
    "MYR",
    "GEL",
    "AZN",
    "AMD",
    "THB",
    "OMR",
    "INR",
    "JPY",
    "AFN",
)

EXCLUDED_CODES = {"USD-IST"}
EXCLUDED_NAMES = {"دلار استانبول", "istanbul dollar"}


def is_excluded(row: PriceRow) -> bool:
    code = str(row.get("code") or "").upper()
    name = str(row.get("name") or "").strip().casefold()
    return code in EXCLUDED_CODES or name in EXCLUDED_NAMES


def normalize_prices(prices: list[PriceRow]) -> list[PriceRow]:
    """Apply the shared product policy while preserving unknown source rows."""
    ranks = {code: index for index, code in enumerate(CANONICAL_ORDER)}
    rows = [row for row in prices if not is_excluded(row)]
    indexed = list(enumerate(rows))
    indexed.sort(
        key=lambda pair: (
            ranks.get(str(pair[1].get("code") or "").upper(), len(ranks)),
            pair[0],
        )
    )
    return [row for _, row in indexed]


def normalize_snapshot(data: ProviderSnapshot) -> ProviderSnapshot:
    normalized = data.copy()
    normalized["prices"] = normalize_prices(data["prices"])
    return normalized
