from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from typing import cast

from currency_policy import CANONICAL_ORDER, normalize_prices
from providers.alanchand import parse
from providers.base import PriceRow

ROOT = Path(__file__).resolve().parent.parent


def price_row(code: str, name: str) -> PriceRow:
    return {
        "code": code,
        "name": name,
        "buy": None,
        "sell": None,
        "direction": "flat",
    }


class AlanChandProviderTests(unittest.TestCase):
    def test_parses_currency_table_and_excludes_crypto(self) -> None:
        html = (ROOT / "tests/fixtures/alanchand.html").read_text(encoding="utf-8")
        result = parse(html)

        self.assertEqual([row["code"] for row in result["prices"]], ["USD", "USD-IST", "EUR"])
        self.assertEqual(result["prices"][0]["sell"], 234500)
        self.assertEqual(result["prices"][0]["direction"], "up")
        self.assertEqual(result["prices"][2]["direction"], "down")
        self.assertNotIn("Bitcoin", json.dumps(result, ensure_ascii=False))
        self.assertEqual(result["unit"], "toman")


class CurrencyPolicyTests(unittest.TestCase):
    def test_canonical_order_matches_the_product_order(self) -> None:
        rows = [price_row(code, code) for code in reversed(CANONICAL_ORDER)]

        normalized = normalize_prices(rows)

        self.assertEqual([row["code"] for row in normalized], list(CANONICAL_ORDER))

    def test_filters_istanbul_dollar_and_applies_shared_order(self) -> None:
        rows = [
            price_row("ZZZ", "Unknown first"),
            price_row("AED", "درهم"),
            price_row("USD-IST", "دلار استانبول"),
            price_row("USD", "دلار آمریکا"),
            price_row("EUR", "یورو"),
            price_row("YYY", "Unknown second"),
        ]

        normalized = normalize_prices(rows)

        self.assertEqual(
            [row["code"] for row in normalized],
            ["USD", "EUR", "AED", "ZZZ", "YYY"],
        )


class StateTests(unittest.TestCase):
    def run_cli(self, state: Path, *args: str) -> dict[str, object]:
        completed = subprocess.run(
            [str(ROOT / "bin/arzdoon"), "--state-file", str(state), *args],
            check=True,
            capture_output=True,
            text=True,
        )
        result: object = json.loads(completed.stdout)
        if not isinstance(result, dict):
            self.fail("CLI response must be a JSON object")
        return cast(dict[str, object], result)

    def test_pins_toggle_per_provider(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "state.json"
            pinned = self.run_cli(state, "pin", "eur", "--provider", "alanchand")
            removed = self.run_cli(state, "pin", "EUR", "--provider", "alanchand")

            self.assertEqual(pinned["pins"], ["EUR"])
            self.assertEqual(pinned["selectedProvider"], "alanchand")
            self.assertEqual(removed["pins"], [])
            self.assertNotIn("favorites", removed)


if __name__ == "__main__":
    unittest.main()
