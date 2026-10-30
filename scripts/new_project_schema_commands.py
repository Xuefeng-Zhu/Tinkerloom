#!/usr/bin/env python3
"""Prepare private TablesDB Console CLI commands, entirely offline.

The browser Console terminal supplies the authenticated project context. This
script never logs in, executes commands, contacts Cloud, or reads credentials.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shlex


COLUMN_TYPES = {"varchar", "integer", "mediumtext", "boolean", "datetime", "double"}
COLUMN_KEYS = {"key", "type", "size", "required", "default", "min", "max", "array"}
INDEX_TYPES = {"key", "unique", "fulltext"}


def compact(value: object) -> str:
    return json.dumps(value, ensure_ascii=False, allow_nan=False, separators=(",", ":"))


def prepare(schema: dict) -> list[dict]:
    database = schema["databaseId"]
    results = []
    seen_tables = set()
    for table in schema["tables"]:
        table_id = table["tableId"]
        if table_id in seen_tables:
            raise ValueError(f"Duplicate table: {table_id}")
        seen_tables.add(table_id)
        if table.get("permissions") != [] or table.get("rowSecurity") is not True:
            raise ValueError(f"Refusing a non-private table: {table_id}")
        columns = table["columns"]
        column_ids = set()
        for column in columns:
            if column["key"] in column_ids:
                raise ValueError(f"Duplicate column: {table_id}.{column['key']}")
            column_ids.add(column["key"])
            if column["type"] not in COLUMN_TYPES or set(column) - COLUMN_KEYS:
                raise ValueError(f"Unsupported column contract: {table_id}.{column['key']}")
            if column.get("required") and "default" in column:
                raise ValueError(f"Required column cannot have a default: {table_id}.{column['key']}")
        indexes = []
        index_ids = set()
        for index in table.get("indexes", []):
            if set(index) != {"key", "type", "columns"} or index["type"] not in INDEX_TYPES:
                raise ValueError(f"Unsupported index contract: {table_id}")
            if index["key"] in index_ids or not set(index["columns"]).issubset(column_ids):
                raise ValueError(f"Invalid index: {table_id}.{index['key']}")
            index_ids.add(index["key"])
            # Inline create-table uses `attributes`, despite response metadata
            # and the standalone create-index API using `columns`.
            indexes.append({"key": index["key"], "type": index["type"], "attributes": index["columns"]})
        args = ["appwrite", "tablesdb", "create-table", "--database-id", database,
                "--table-id", table_id, "--name", table["name"],
                "--row-security", "--enabled", "--json"]
        for column in columns:
            args.extend(["--columns", compact(column)])
        for index in indexes:
            args.extend(["--indexes", compact(index)])
        results.append({"tableId": table_id, "columns": columns, "indexes": indexes,
                        "columnCount": len(columns), "indexCount": len(indexes),
                        "command": shlex.join(args)})
    return results


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--schema", type=Path, default=Path(__file__).resolve().parents[1] / "appwrite_backend/schema.json")
    parser.add_argument("--output-dir", type=Path, default=Path("/private/tmp/tinkerloom-new-project-provisioning"))
    args = parser.parse_args()
    raw = args.schema.read_bytes()
    schema = json.loads(raw)
    tables = prepare(schema)
    counts = {"tables": len(tables), "columns": sum(t["columnCount"] for t in tables),
              "indexes": sum(t["indexCount"] for t in tables)}
    output = {"databaseId": schema["databaseId"], "schemaSha256": hashlib.sha256(raw).hexdigest(),
              "counts": counts, "privateTablesOnly": True, "permissions": [],
              "scope": "Schema command preparation only; no execution, network, credentials or business data",
              "tables": tables,
              "functionScopes": schema["functionScopes"], "workerFunction": schema["workerFunction"],
              "storage": schema["storage"]}
    args.output_dir.mkdir(parents=True, exist_ok=True)
    (args.output_dir / "tables.json").write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n")
    (args.output_dir / "commands.txt").write_text("\n".join(t["command"] for t in tables) + "\n")
    print(json.dumps({"outputDirectory": str(args.output_dir), "schemaSha256": output["schemaSha256"], **counts}))


if __name__ == "__main__":
    main()
