#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="${HOME}/river_sr_isoscape_v2_cluster"

RAW_DIR="${PROJECT_DIR}/data/raw/geology/nrcan_of5529"
OUT_DIR="${PROJECT_DIR}/outputs/nrcan_of5529"

DOI_URL="https://doi.org/10.4095/223767"

mkdir -p \
  "${RAW_DIR}" \
  "${OUT_DIR}"

echo "Resolving DOI:"
echo "${DOI_URL}"

# Save the final landing page and HTTP headers.
curl \
  --location \
  --fail \
  --retry 3 \
  --retry-delay 5 \
  --connect-timeout 30 \
  --max-time 300 \
  --user-agent "Mozilla/5.0 river-sr-isoscape-research" \
  --dump-header "${OUT_DIR}/doi_response_headers.txt" \
  --output "${RAW_DIR}/of5529_landing_response" \
  "${DOI_URL}"

# Record the final URL after all redirects.
curl \
  --location \
  --silent \
  --show-error \
  --connect-timeout 30 \
  --max-time 300 \
  --user-agent "Mozilla/5.0 river-sr-isoscape-research" \
  --output /dev/null \
  --write-out '%{url_effective}\n' \
  "${DOI_URL}" \
  > "${OUT_DIR}/effective_url.txt"

echo
echo "Effective URL:"
cat "${OUT_DIR}/effective_url.txt"

echo
echo "Downloaded landing response:"
ls -lh "${RAW_DIR}/of5529_landing_response"

echo
echo "Detected file type:"
file "${RAW_DIR}/of5529_landing_response"

python3 - <<'PY'
from __future__ import annotations

import csv
import json
import re
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urljoin, urlparse

project = Path.home() / "river_sr_isoscape_v2_cluster"

raw_dir = (
    project
    / "data"
    / "raw"
    / "geology"
    / "nrcan_of5529"
)

out_dir = (
    project
    / "outputs"
    / "nrcan_of5529"
)

response_path = raw_dir / "of5529_landing_response"
effective_path = out_dir / "effective_url.txt"

effective_url = effective_path.read_text(
    encoding="utf-8",
    errors="replace"
).strip()

raw_bytes = response_path.read_bytes()

text = raw_bytes.decode(
    "utf-8",
    errors="replace"
)

class LinkParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.links: list[tuple[str, str]] = []
        self._href: str | None = None
        self._text: list[str] = []

    def handle_starttag(self, tag, attrs):
        if tag.lower() != "a":
            return

        attrs_dict = dict(attrs)
        href = attrs_dict.get("href")

        if href:
            self._href = href
            self._text = []

    def handle_data(self, data):
        if self._href is not None:
            self._text.append(data)

    def handle_endtag(self, tag):
        if (
            tag.lower() == "a"
            and self._href is not None
        ):
            label = " ".join(
                " ".join(self._text).split()
            )

            self.links.append(
                (
                    self._href,
                    label
                )
            )

            self._href = None
            self._text = []

parser = LinkParser()

try:
    parser.feed(text)
except Exception as exc:
    print(
        "HTML parsing warning:",
        repr(exc)
    )

keywords = re.compile(
    r"("
    r"download|dataset|digital|data|gis|geospatial|"
    r"5529|223767|chorlton|geology|bedrock|"
    r"\.zip(?:$|\?)|\.7z(?:$|\?)|\.tar(?:$|\?)|"
    r"\.tgz(?:$|\?)|\.gz(?:$|\?)|\.iso(?:$|\?)|"
    r"\.shp(?:$|\?)|\.gpkg(?:$|\?)|\.gdb(?:$|\?)|"
    r"\.e00(?:$|\?)|\.mdb(?:$|\?)|\.dbf(?:$|\?)"
    r")",
    flags=re.IGNORECASE
)

all_rows = []
candidate_rows = []

seen = set()

for href, label in parser.links:
    absolute_url = urljoin(
        effective_url,
        href
    )

    if absolute_url in seen:
        continue

    seen.add(absolute_url)

    parsed = urlparse(absolute_url)

    if parsed.scheme not in {
        "http",
        "https",
        "ftp"
    }:
        continue

    row = {
        "url": absolute_url,
        "label": label
    }

    all_rows.append(row)

    searchable = f"{absolute_url} {label}"

    if keywords.search(searchable):
        candidate_rows.append(row)

# If DOI redirects directly to a file, retain it as a candidate.
effective_suffix = Path(
    urlparse(effective_url).path
).suffix.lower()

direct_file_suffixes = {
    ".zip",
    ".7z",
    ".tar",
    ".tgz",
    ".gz",
    ".iso",
    ".shp",
    ".gpkg",
    ".e00",
    ".mdb",
    ".pdf"
}

if effective_suffix in direct_file_suffixes:
    direct_row = {
        "url": effective_url,
        "label": "DOI effective URL"
    }

    if direct_row not in candidate_rows:
        candidate_rows.insert(
            0,
            direct_row
        )

def write_tsv(path: Path, rows: list[dict]) -> None:
    with path.open(
        "w",
        encoding="utf-8",
        newline=""
    ) as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=[
                "url",
                "label"
            ],
            delimiter="\t"
        )

        writer.writeheader()
        writer.writerows(rows)

write_tsv(
    out_dir / "all_extracted_links.tsv",
    all_rows
)

write_tsv(
    out_dir / "candidate_download_links.tsv",
    candidate_rows
)

with (
    out_dir / "candidate_download_urls.txt"
).open(
    "w",
    encoding="utf-8"
) as handle:
    for row in candidate_rows:
        handle.write(
            row["url"] + "\n"
        )

summary = {
    "doi": "10.4095/223767",
    "effective_url": effective_url,
    "response_bytes": len(raw_bytes),
    "all_link_count": len(all_rows),
    "candidate_link_count": len(candidate_rows),
    "candidates": candidate_rows[:50],
}

(
    out_dir / "resolution_summary.json"
).write_text(
    json.dumps(
        summary,
        indent=2,
        ensure_ascii=False
    ),
    encoding="utf-8"
)

print()
print("Link extraction summary")
print("-----------------------")
print("Effective URL:", effective_url)
print("All links:", len(all_rows))
print("Candidate links:", len(candidate_rows))

for index, row in enumerate(
    candidate_rows[:30],
    start=1
):
    print(
        f"{index:02d}.",
        row["url"],
        "|",
        row["label"]
    )
PY

echo
echo "Candidate link table:"
sed -n '1,80p' \
  "${OUT_DIR}/candidate_download_links.tsv"

echo
echo "Resolution audit complete."
