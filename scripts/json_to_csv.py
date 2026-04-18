#!/usr/bin/env python3
"""Convert usage JSON shaped like {"sessions": [...], "totals": {...}} into CSV."""

from __future__ import annotations

import csv
import json
import sys
from pathlib import Path
from typing import Any


def to_number(value: Any) -> int | float:
    return value if isinstance(value, (int, float)) else 0


def parse_args(argv: list[str]) -> tuple[Path, Path]:
    if len(argv) < 2:
        print("Usage: uv run scripts/json_to_csv.py <input.json> [output.csv]")
        raise SystemExit(1)

    input_path = Path(argv[1])
    output_path = Path(argv[2]) if len(argv) > 2 else input_path.with_suffix(".csv")
    return input_path, output_path


def main(argv: list[str]) -> int:
    input_path, output_path = parse_args(argv)

    with input_path.open("r", encoding="utf-8") as file:
        data = json.load(file)

    if not isinstance(data, dict):
        raise ValueError('Expected a top-level object: {"sessions": [...], "totals": {...}}')

    sessions = data.get("sessions", [])
    if not isinstance(sessions, list):
        raise ValueError('Expected "sessions" to be a list')

    fieldnames = [
        "sessionId",
        "inputTokens",
        "outputTokens",
        "cacheCreationTokens",
        "cacheReadTokens",
        "totalTokens",
        "totalCost",
        "lastActivity",
        "projectPath",
        "modelsUsed",
        "modelBreakdowns",
    ]

    with output_path.open("w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(file, fieldnames=fieldnames)
        writer.writeheader()

        for session in sessions:
            if not isinstance(session, dict):
                continue

            models_used = session.get("modelsUsed", [])
            model_breakdowns = session.get("modelBreakdowns", [])

            writer.writerow(
                {
                    "sessionId": session.get("sessionId", ""),
                    "inputTokens": to_number(session.get("inputTokens")),
                    "outputTokens": to_number(session.get("outputTokens")),
                    "cacheCreationTokens": to_number(session.get("cacheCreationTokens")),
                    "cacheReadTokens": to_number(session.get("cacheReadTokens")),
                    "totalTokens": to_number(session.get("totalTokens")),
                    "totalCost": to_number(session.get("totalCost")),
                    "lastActivity": session.get("lastActivity", ""),
                    "projectPath": session.get("projectPath", ""),
                    "modelsUsed": "|".join(models_used) if isinstance(models_used, list) else str(models_used),
                    "modelBreakdowns": json.dumps(
                        model_breakdowns, ensure_ascii=False, separators=(",", ":")
                    ),
                }
            )

    print(f"Wrote {len(sessions)} rows to {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
