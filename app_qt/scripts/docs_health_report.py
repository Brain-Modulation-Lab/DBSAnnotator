"""Generate a lightweight docs health report.

The report is intended for CI trend tracking and artifact inspection.
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

HEALTH_DIR = Path("docs/_build/health")


def _run(cmd: list[str]) -> tuple[int, str]:
    result = subprocess.run(cmd, capture_output=True, text=True, check=False)
    output = (result.stdout or "") + (result.stderr or "")
    return result.returncode, output


def _count_warnings(output: str) -> int:
    return sum(1 for line in output.splitlines() if "WARNING:" in line)


def _parse_linkcheck_broken() -> int:
    output_file = Path("docs/_build/linkcheck/output.txt")
    if not output_file.exists():
        return 0
    text = output_file.read_text(encoding="utf-8", errors="ignore")
    return sum(
        1
        for line in text.splitlines()
        if "broken" in line.lower() or "timed out" in line.lower()
    )


def main() -> int:
    HEALTH_DIR.mkdir(parents=True, exist_ok=True)

    html_code, html_out = _run(
        [
            "uv",
            "run",
            "sphinx-build",
            "-b",
            "html",
            "--keep-going",
            "docs",
            "docs/_build/html",
        ]
    )
    link_code, link_out = _run(
        [
            "uv",
            "run",
            "sphinx-build",
            "-b",
            "linkcheck",
            "docs",
            "docs/_build/linkcheck",
        ]
    )

    report = {
        "html_build_exit_code": html_code,
        "html_warning_count": _count_warnings(html_out),
        "linkcheck_exit_code": link_code,
        "linkcheck_warning_count": _count_warnings(link_out),
        "linkcheck_broken_or_timeout_count": _parse_linkcheck_broken(),
    }

    (HEALTH_DIR / "report.json").write_text(
        json.dumps(report, indent=2) + "\n",
        encoding="utf-8",
    )
    (HEALTH_DIR / "html-build.log").write_text(html_out, encoding="utf-8")
    (HEALTH_DIR / "linkcheck.log").write_text(link_out, encoding="utf-8")

    md = "\n".join(
        [
            "# Docs Health Report",
            "",
            f"- html_build_exit_code: `{report['html_build_exit_code']}`",
            f"- html_warning_count: `{report['html_warning_count']}`",
            f"- linkcheck_exit_code: `{report['linkcheck_exit_code']}`",
            f"- linkcheck_warning_count: `{report['linkcheck_warning_count']}`",
            (
                "- linkcheck_broken_or_timeout_count: "
                f"`{report['linkcheck_broken_or_timeout_count']}`"
            ),
            "",
            "See `html-build.log` and `linkcheck.log` for details.",
            "",
        ]
    )
    (HEALTH_DIR / "report.md").write_text(md, encoding="utf-8")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
