"""Alanchand adapter: reads only tables whose class includes CurrencyTbl."""

from __future__ import annotations

import re
from html.parser import HTMLParser
from typing import TypedDict
from urllib.request import Request, urlopen

from .base import PriceRow, ProviderInfo, ProviderSnapshot

INFO = ProviderInfo("alanchand", "AlanChand", "https://alanchand.com/")

PERSIAN_DIGITS = str.maketrans("۰۱۲۳۴۵۶۷۸۹", "0123456789")
ARABIC_DIGITS = str.maketrans("٠١٢٣٤٥٦٧٨٩", "0123456789")


class ParsedRow(TypedDict):
    url: str
    name: str
    buyText: str
    sellText: str
    direction: str


def clean_text(value: str) -> str:
    return re.sub(r"\s+", " ", value).strip()


def ascii_number(value: str) -> str:
    return clean_text(value).translate(PERSIAN_DIGITS).translate(ARABIC_DIGITS)


def numeric_value(value: str) -> int | float | None:
    cleaned = ascii_number(value).replace(",", "")
    if not cleaned or cleaned == "-":
        return None
    try:
        return float(cleaned) if "." in cleaned else int(cleaned)
    except ValueError:
        return None


class CurrencyTableParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.table_depth = 0
        self.in_currency_table = False
        self.in_row = False
        self.current_row: ParsedRow | None = None
        self.active_cell = ""
        self.cell_parts: list[str] = []
        self.rows: list[PriceRow] = []

    @staticmethod
    def attrs_dict(attrs: list[tuple[str, str | None]]) -> dict[str, str]:
        return {key: (value or "") for key, value in attrs}

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        data = self.attrs_dict(attrs)
        classes = set(data.get("class", "").split())

        if tag == "table":
            if self.in_currency_table:
                self.table_depth += 1
            elif "CurrencyTbl" in classes:
                self.in_currency_table = True
                self.table_depth = 1

        if not self.in_currency_table:
            return

        if tag == "tr":
            self.in_row = True
            self.current_row = {
                "url": self._row_url(data.get("onclick", "")),
                "name": "",
                "buyText": "",
                "sellText": "",
                "direction": "flat",
            }
        elif self.in_row and self.current_row is not None and tag == "td":
            for candidate in ("currName", "buyPrice", "sellPrice"):
                if candidate in classes:
                    self.active_cell = candidate
                    self.cell_parts = []
                    break
        elif (
            self.in_row
            and self.current_row is not None
            and self.active_cell == "sellPrice"
            and tag == "span"
            and "priceSymbol" in classes
        ):
            if "up" in classes:
                self.current_row["direction"] = "up"
            elif "down" in classes:
                self.current_row["direction"] = "down"

    def handle_endtag(self, tag: str) -> None:
        if not self.in_currency_table:
            return

        if tag == "td" and self.active_cell and self.current_row is not None:
            value = ascii_number("".join(self.cell_parts))
            if self.active_cell == "currName":
                self.current_row["name"] = value
            elif self.active_cell == "buyPrice":
                self.current_row["buyText"] = value
            elif self.active_cell == "sellPrice":
                self.current_row["sellText"] = value
            self.active_cell = ""
            self.cell_parts = []
        elif tag == "tr" and self.in_row and self.current_row is not None:
            self.in_row = False
            if self.current_row.get("name") and self.current_row.get("sellText"):
                url = self.current_row.get("url", "")
                code = url.rstrip("/").rsplit("/", 1)[-1].upper() if url else ""
                if code:
                    self.rows.append(
                        {
                            "code": code,
                            "name": self.current_row["name"],
                            "buy": numeric_value(self.current_row["buyText"]),
                            "sell": numeric_value(self.current_row["sellText"]),
                            "direction": self.current_row["direction"],
                        }
                    )
            self.current_row = None
        elif tag == "table":
            self.table_depth -= 1
            if self.table_depth <= 0:
                self.in_currency_table = False
                self.table_depth = 0

    def handle_data(self, data: str) -> None:
        if self.in_currency_table and self.in_row and self.active_cell:
            self.cell_parts.append(data)

    @staticmethod
    def _row_url(onclick: str) -> str:
        match = re.search(r"window\.location\s*=\s*['\"]([^'\"]+)", onclick)
        return match.group(1) if match else ""


def parse(html: str) -> ProviderSnapshot:
    parser = CurrencyTableParser()
    parser.feed(html)
    parser.close()
    if not parser.rows:
        raise ValueError("no CurrencyTbl currency rows found")
    return {
        "schemaVersion": 1,
        "provider": {"id": INFO.id, "name": INFO.name, "url": INFO.url},
        "unit": "toman",
        "prices": parser.rows,
    }


def fetch(timeout: float = 12) -> ProviderSnapshot:
    request = Request(
        INFO.url,
        headers={
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.9,fa-IR;q=0.8,fa;q=0.7",
            "Cache-Control": "no-cache",
            "User-Agent": (
                "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
                "Chrome/152 Safari/537.36 Arzdoon/1.0"
            ),
        },
    )
    with urlopen(request, timeout=timeout) as response:
        charset = response.headers.get_content_charset() or "utf-8"
        return parse(response.read().decode(charset, errors="replace"))
