#!/usr/bin/env python3
"""Pull recent ING transactions over FinTS and POST them to Sure's import API."""

import csv
import datetime
import io
import json
import os
import pathlib
import sys

import requests
from fints.client import FinTS3PinTanClient

STATE = pathlib.Path(os.environ.get("STATE_DIRECTORY", "/var/lib/ing-sync"))
CLIENT_DATA = STATE / "fints-client.data"
DAYS = int(os.environ.get("SYNC_DAYS", "14"))


def load_client():
    # Persisting client data keeps the registered system_id across runs.
    # Without it, every run re-registers with the bank.
    data = CLIENT_DATA.read_bytes() if CLIENT_DATA.exists() else None
    kwargs = {}
    if pid := os.environ.get("FINTS_PRODUCT_ID"):
        kwargs["product_id"] = pid
    return FinTS3PinTanClient(
        os.environ["FINTS_BLZ"],
        os.environ["FINTS_USER"],
        os.environ["FINTS_PIN"],
        os.environ["FINTS_ENDPOINT"],
        from_data=data,
        **kwargs,
    )


def main():
    client = load_client()
    end = datetime.date.today()
    start = end - datetime.timedelta(days=DAYS)

    with client:
        if client.init_tan_response:
            print(
                "TAN challenge required — aborting. Log in to ING web banking "
                "(required every 90 days), then retry.",
                file=sys.stderr,
            )
            return 1

        accounts = client.get_sepa_accounts()
        want = os.environ.get("FINTS_IBAN")
        if want:
            accounts = [a for a in accounts if a.iban == want]
        if not accounts:
            print("no matching accounts", file=sys.stderr)
            return 1

        rows = []
        for acct in accounts:
            for t in client.get_transactions(acct, start, end):
                d = t.data
                rows.append(
                    {
                        "date": d["date"].isoformat(),
                        "amount": str(d["amount"].amount),
                        "currency": str(d["amount"].currency),
                        "name": (
                            d.get("applicant_name") or d.get("posting_text") or ""
                        )[:255],
                        "notes": " ".join(
                            filter(
                                None, [d.get("purpose"), d.get("additional_purpose")]
                            )
                        ).replace("\n", " ")[:255],
                    }
                )

    CLIENT_DATA.parent.mkdir(parents=True, exist_ok=True)
    CLIENT_DATA.write_bytes(client.deconstruct(including_private=True))
    CLIENT_DATA.chmod(0o600)

    if not rows:
        print("no transactions in window")
        return 0

    buf = io.StringIO()
    w = csv.DictWriter(buf, fieldnames=["date", "amount", "currency", "name", "notes"])
    w.writeheader()
    w.writerows(rows)
    payload = buf.getvalue()

    base = os.environ["SURE_URL"].rstrip("/")
    headers = {
        "X-Api-Key": os.environ["SURE_API_KEY"],
        "Content-Type": "application/json",
    }
    body = {
        "type": "TransactionImport",
        "account_id": os.environ["SURE_ACCOUNT_ID"],
        "raw_file_content": payload,
        "date_col_label": "date",
        "amount_col_label": "amount",
        "currency_col_label": "currency",
        "name_col_label": "name",
        "notes_col_label": "notes",
        "date_format": "%Y-%m-%d",
        "number_format": "1,234.56",
        "signage_convention": "inflows_positive",
        "publish": "true",
    }
    r = requests.post(
        f"{base}/api/v1/imports", headers=headers, data=json.dumps(body), timeout=120
    )
    if not r.ok:
        print(f"import failed {r.status_code}: {r.text[:500]}", file=sys.stderr)
        return 1
    print(f"imported {len(rows)} rows")
    return 0


if __name__ == "__main__":
    sys.exit(main())
