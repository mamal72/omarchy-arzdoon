from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from typing import cast

from currency_policy import CANONICAL_ORDER, normalize_prices
from providers.alanchand import numeric_value, parse
from providers.base import MAX_PRICE_ROWS, PriceRow

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


    def test_caps_rows_and_rejects_unsafe_codes(self) -> None:
        def row(code: str) -> str:
            return (
                f"<tr onclick=\"window.location='/en/{code}'\">"
                "<td class='currName'>N</td><td class='buyPrice'>1</td>"
                "<td class='sellPrice'>2</td></tr>"
            )

        rows = "".join(row(f"C{index}") for index in range(MAX_PRICE_ROWS + 50))
        result = parse(f"<table class='CurrencyTbl'>{rows}{row('bad<code>')}</table>")

        self.assertEqual(len(result["prices"]), MAX_PRICE_ROWS)
        self.assertTrue(all("<" not in price["code"] for price in result["prices"]))

    def test_rejects_non_finite_and_oversized_numbers(self) -> None:
        self.assertIsNone(numeric_value("nan"))
        self.assertIsNone(numeric_value("1e999"))
        self.assertIsNone(numeric_value("9" * 30))
        self.assertEqual(numeric_value("1,234"), 1234)


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

    def test_rejects_invalid_pin_codes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "state.json"
            completed = subprocess.run(
                [str(ROOT / "bin/arzdoon"), "--state-file", str(state), "pin", "bad;code"],
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(completed.returncode, 0)
            self.assertFalse(state.exists())


if __name__ == "__main__":
    unittest.main()
