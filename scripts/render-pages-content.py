#!/usr/bin/env python3
"""Render report, milestone, and journal data into the static Pages landing page."""

from __future__ import annotations

import calendar
import html
import json
import re
import sys
from dataclasses import dataclass
from datetime import date
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path


REPOSITORY = "https://github.com/blinklabs-io/treasury-proposal"
REPORT_NAME = re.compile(
    r"(?P<year>\d{4})-(?:(?P<month>0[1-9]|1[0-2])|Q(?P<quarter>[1-4]))-report\.md$"
)
JOURNAL_NAME = re.compile(r"(?P<date>\d{4}-\d{2}-\d{2})-.+\.md$")
TRANSACTION_HASH = re.compile(r"^[0-9a-fA-F]{64}$")
PLACEHOLDER = "<!-- GENERATED_REPORTS_AND_JOURNAL -->"
ROADMAP_STATUS_PLACEHOLDERS = {
    "Q2 2026": "<!-- GENERATED_Q2_2026_STATUS -->",
    "Q3 2026": "<!-- GENERATED_Q3_2026_STATUS -->",
    "Q4 2026": "<!-- GENERATED_Q4_2026_STATUS -->",
    "Q1 2027": "<!-- GENERATED_Q1_2027_STATUS -->",
}
PLACEHOLDERS = {
    "status_period": "<!-- GENERATED_STATUS_PERIOD -->",
    "current_status": "<!-- GENERATED_CURRENT_STATUS -->",
    "upcoming": "<!-- GENERATED_UPCOMING_WORK -->",
    "risks": "<!-- GENERATED_REPORT_RISKS -->",
    "funding": "<!-- GENERATED_FUNDING_SUMMARY -->",
}


@dataclass(frozen=True)
class Milestone:
    title: str
    target: str
    status: str
    notes: str


@dataclass(frozen=True)
class Report:
    path: Path
    title: str
    end_date: date
    is_quarterly: bool
    summary: tuple[str, ...]
    milestones: tuple[Milestone, ...]
    upcoming: tuple[str, ...]
    risks: tuple[str, ...]


@dataclass(frozen=True)
class JournalEntry:
    path: Path
    entry_date: date
    action: str
    transaction_hash: str
    justification: str


@dataclass(frozen=True)
class FundingSummary:
    allocated_usdcx: int
    allocated_ada: int
    claimed_usdcx: int
    claimed_ada: int
    claimed_milestone_count: int
    milestone_count: int


def markdown_text(value: str) -> str:
    """Reduce the small inline Markdown subset used in summaries to safe text."""
    value = re.sub(r"<!--.*?-->", " ", value, flags=re.DOTALL)
    value = re.sub(r"!\[([^\]]*)\]\([^)]*\)", r"\1", value)
    value = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", value)
    value = re.sub(r"`([^`]*)`", r"\1", value)
    value = re.sub(r"\*\*([^*]+)\*\*|__([^_]+)__", lambda m: m[1] or m[2], value)
    value = re.sub(r"(?m)^\s*[-*]\s+", "• ", value)
    return re.sub(r"\s+", " ", value).strip()


def github_file_url(relative_path: str) -> str:
    return f"{REPOSITORY}/blob/main/{relative_path}"


def section_body(markdown: str, heading: str) -> str:
    match = re.search(rf"(?m)^## {re.escape(heading)}\s*$", markdown)
    if not match:
        return ""
    start = match.end()
    following = re.search(r"(?m)^##\s+", markdown[start:])
    end = start + following.start() if following else len(markdown)
    return markdown[start:end].strip()


def report_period(path: Path) -> tuple[date, bool] | None:
    match = REPORT_NAME.fullmatch(path.name)
    if not match:
        return None
    year = int(match.group("year"))
    if match.group("month"):
        month = int(match.group("month"))
        quarterly = False
    else:
        quarter = int(match.group("quarter"))
        month = quarter * 3
        quarterly = True
    end_date = date(year, month, calendar.monthrange(year, month)[1])
    return end_date, quarterly


def parse_milestones(markdown: str) -> tuple[Milestone, ...]:
    milestones: list[Milestone] = []
    for line in section_body(markdown, "Milestones").splitlines():
        if not line.lstrip().startswith("|"):
            continue
        cells = [markdown_text(cell) for cell in line.strip().strip("|").split("|")]
        if len(cells) < 4 or cells[0] == "Milestone":
            continue
        if all(re.fullmatch(r"[-: ]+", cell or " ") for cell in cells):
            continue
        milestones.append(
            Milestone(
                title=cells[0],
                target=cells[1],
                status=cells[2],
                notes=cells[3],
            )
        )
    return tuple(milestones)


def parse_bullet_items(markdown: str, heading: str) -> tuple[str, ...]:
    items: list[str] = []
    current: list[str] = []

    def finish() -> None:
        if current:
            item = markdown_text(" ".join(current))
            if item:
                items.append(item)
            current.clear()

    for line in section_body(markdown, heading).splitlines():
        match = re.match(r"^\s*[-*]\s+(.*)$", line)
        if match:
            finish()
            current.append(match.group(1))
        elif line.strip() and current:
            current.append(line.strip())
        elif not line.strip():
            finish()
    finish()
    return tuple(items)


def load_reports(report_dir: Path) -> list[Report]:
    reports: list[Report] = []
    for path in report_dir.glob("*.md"):
        period = report_period(path)
        if period is None:
            continue
        markdown = path.read_text(encoding="utf-8")

        summary_body = section_body(markdown, "Summary")
        paragraphs = tuple(
            text
            for block in re.split(r"\n\s*\n", summary_body)
            if (text := markdown_text(block))
        )
        if not paragraphs:
            raise ValueError(f"report has no Summary section: {path}")

        title_match = re.search(r"(?m)^#\s+(.+?)\s*$", markdown)
        title = markdown_text(title_match.group(1)) if title_match else path.stem
        reports.append(
            Report(
                path=path,
                title=title,
                end_date=period[0],
                is_quarterly=period[1],
                summary=paragraphs,
                milestones=parse_milestones(markdown),
                upcoming=parse_bullet_items(markdown, "Upcoming Work"),
                risks=parse_bullet_items(markdown, "Risks and Issues"),
            )
        )

    return sorted(
        reports,
        key=lambda report: (report.end_date, report.is_quarterly, report.path.name),
        reverse=True,
    )


def table_fields(markdown: str) -> dict[str, str]:
    fields: dict[str, str] = {}
    for line in markdown.splitlines():
        if not line.lstrip().startswith("|"):
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if len(cells) < 2:
            continue
        key = markdown_text(cells[0]).rstrip(":")
        if key in {
            "Date",
            "Transaction Hash",
            "Action",
            "Justification",
        }:
            fields[key] = markdown_text(cells[1])
    return fields


def load_journal(journal_dir: Path) -> list[JournalEntry]:
    entries: list[JournalEntry] = []
    for path in journal_dir.glob("*.md"):
        if not JOURNAL_NAME.fullmatch(path.name):
            continue
        markdown = path.read_text(encoding="utf-8")

        fields = table_fields(markdown)
        try:
            entry_date = date.fromisoformat(fields["Date"])
            action = fields["Action"]
            transaction_hash = fields["Transaction Hash"]
            justification = fields["Justification"]
        except (KeyError, ValueError) as error:
            raise ValueError(f"incomplete journal entry {path}: {error}") from error
        if not action or not justification:
            raise ValueError(f"incomplete journal entry {path}")

        entries.append(
            JournalEntry(
                path=path,
                entry_date=entry_date,
                action=action,
                transaction_hash=transaction_hash,
                justification=justification,
            )
        )

    return sorted(entries, key=lambda entry: (entry.entry_date, entry.path.name), reverse=True)


def report_card(reports: list[Report]) -> str:
    if not reports:
        raise ValueError("no progress reports available")

    latest = reports[0]
    report_path = f"docs/reports/{latest.path.name}"
    url = html.escape(github_file_url(report_path), quote=True)
    title = html.escape(latest.title)
    summary = "\n".join(
        f'<p class="activity-summary">{html.escape(paragraph)}</p>'
        for paragraph in latest.summary[:2]
    )

    archive = ""
    older_reports = reports[1:]
    if older_reports:
        links = "\n".join(
            "<li><a href=\"{}\">{}</a></li>".format(
                html.escape(github_file_url(f"docs/reports/{report.path.name}"), quote=True),
                html.escape(report.title),
            )
            for report in older_reports
        )
        archive = (
            '<details class="activity-archive"><summary>Earlier reports</summary>'
            f"<ul>{links}</ul></details>"
        )

    return (
        '<article class="activity-card">'
        '<p class="activity-label">Latest Progress Report</p>'
        f'<h3><a href="{url}">{title}</a></h3>'
        f"{summary}"
        f'<a class="activity-more" href="{url}">Read the full report</a>'
        f"{archive}"
        "</article>"
    )


def status_class(status: str) -> str:
    classes = {
        "complete": "complete",
        "in progress": "in-progress",
        "not started": "not-started",
        "planned": "not-started",
        "target": "not-started",
    }
    try:
        return classes[status.casefold()]
    except KeyError:
        raise ValueError(f"unsupported milestone status: {status!r}") from None


def validate_latest_report(report: Report) -> None:
    for quarter in ROADMAP_STATUS_PLACEHOLDERS:
        roadmap_status(report, quarter)
    if len(report.milestones) != len(ROADMAP_STATUS_PLACEHOLDERS):
        raise ValueError(f"{report.path}: unexpected milestone rows")
    for milestone in report.milestones:
        if not all((milestone.title, milestone.target, milestone.status, milestone.notes)):
            raise ValueError(f"{report.path}: incomplete milestone row: {milestone.title}")
        status_class(milestone.status)
    if not report.upcoming:
        raise ValueError(f"{report.path}: missing Upcoming Work bullet items")
    if not report.risks:
        raise ValueError(f"{report.path}: missing Risks and Issues bullet items")


def report_url(report: Report) -> str:
    return html.escape(
        github_file_url(f"docs/reports/{report.path.name}"), quote=True
    )


def status_period(report: Report) -> str:
    return f'Based on <a href="{report_url(report)}">{html.escape(report.title)}</a>'


def current_status(report: Report) -> str:
    items: list[str] = []
    # Put ongoing work first, then future targets, then completed work.
    priority = {"in-progress": 0, "not-started": 1, "complete": 2}
    milestones = sorted(report.milestones, key=lambda item: priority[status_class(item.status)])
    for milestone in milestones:
        dot_class = "" if status_class(milestone.status) == "complete" else " orange"
        label = milestone.title.split(":", 1)[0]
        items.append(
            '<li><span class="dot{}"></span><span><strong>{} — {}</strong>'
            '<span class="status-scope">{}</span>'
            '<span class="status-note">{}</span></span></li>'.format(
                dot_class,
                html.escape(label),
                html.escape(milestone.status),
                html.escape(milestone.title.split(":", 1)[1].strip()),
                html.escape(milestone.notes),
            )
        )
    return "\n".join(items)


def roadmap_status(report: Report, quarter: str) -> str:
    matching = [
        milestone
        for milestone in report.milestones
        if milestone.title.startswith(f"{quarter}:")
    ]
    if len(matching) != 1:
        raise ValueError(
            f"{report.path}: expected exactly one milestone for {quarter}, found {len(matching)}"
        )
    return html.escape(matching[0].status)


def context_card(title: str, items: tuple[str, ...], report: Report) -> str:
    if not items:
        raise ValueError(f"{report.path}: missing {title} bullet items")
    item_html = "".join(f"<li>{html.escape(item)}</li>" for item in items)
    heading = html.escape(title)
    return f'<article class="report-context-card"><h3>{heading}</h3><ul>{item_html}</ul></article>'


def render_funding_summary(root: Path, entries: list[JournalEntry]) -> str:
    metadata_dir = root / "metadata" / "transactions"
    metadata_documents: list[tuple[Path, dict[str, object]]] = []
    for path in metadata_dir.glob("*.json"):
        document = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(document, dict):
            continue
        candidates = [document, *[value for value in document.values() if isinstance(value, dict)]]
        for candidate in candidates:
            body = candidate.get("body")
            if isinstance(body, dict):
                metadata_documents.append((path, body))
                break

    fund_records = [
        (path, body)
        for path, body in metadata_documents
        if body.get("event") == "fund"
        and isinstance(body.get("totals"), dict)
        and isinstance(body.get("milestones"), list)
    ]
    if len(fund_records) != 1:
        raise ValueError("funding schedule metadata is missing or ambiguous")

    _, fund_body = fund_records[0]
    totals = fund_body["totals"]
    schedule = fund_body["milestones"]
    allocated_usdcx = totals.get("usdcxBaseUnits")
    allocated_ada = totals.get("adaLovelace")
    if not isinstance(allocated_usdcx, int) or not isinstance(allocated_ada, int):
        raise ValueError("funding totals are not valid base-unit integers")

    milestone_amounts: dict[str, tuple[int, int]] = {}
    for milestone in schedule:
        if not isinstance(milestone, dict):
            raise ValueError("funding schedule contains an unsupported milestone")
        milestone_id = milestone.get("id")
        usdcx = milestone.get("usdcx_base")
        ada = milestone.get("ada_lovelace")
        if (
            not isinstance(milestone_id, str)
            or not isinstance(usdcx, int)
            or not isinstance(ada, int)
            or milestone_id in milestone_amounts
        ):
            raise ValueError("funding schedule has invalid or duplicate milestone values")
        milestone_amounts[milestone_id] = (usdcx, ada)

    if (
        sum(value[0] for value in milestone_amounts.values()) != allocated_usdcx
        or sum(value[1] for value in milestone_amounts.values()) != allocated_ada
    ):
        raise ValueError("funding totals do not match the milestone schedule")

    unsupported_actions = {
        entry.action.casefold().replace(" ", "-")
        for entry in entries
        if entry.action.casefold().replace(" ", "-")
        in {"modify-project", "reorganize", "sweep-early"}
    }
    if unsupported_actions:
        raise ValueError("later schedule changes, reorganizations, or sweeps need reconciliation")

    claim_entries: dict[str, int] = {}
    for entry in entries:
        if entry.action.casefold().replace(" ", "-") == "milestone-claim":
            claim_entries[entry.entry_date.isoformat()] = (
                claim_entries.get(entry.entry_date.isoformat(), 0) + 1
            )

    withdrawal_documents: dict[str, list[dict[str, object]]] = {}
    for path, body in metadata_documents:
        if body.get("event") != "withdraw":
            continue
        date_match = re.match(r"(\d{4}-\d{2}-\d{2})", path.name)
        if date_match:
            withdrawal_documents.setdefault(date_match.group(1), []).append(body)

    if set(claim_entries) != set(withdrawal_documents) or any(
        claim_entries[day] != len(withdrawal_documents[day]) for day in claim_entries
    ):
        raise ValueError("milestone claims and withdrawal metadata do not match")

    claimed_ids: list[str] = []
    for bodies in withdrawal_documents.values():
        for body in bodies:
            claimed = body.get("milestones")
            if not isinstance(claimed, dict):
                raise ValueError("withdrawal metadata has no milestone list")
            claimed_ids.extend(claimed.keys())

    if len(claimed_ids) != len(set(claimed_ids)) or any(
        milestone_id not in milestone_amounts for milestone_id in claimed_ids
    ):
        raise ValueError("claimed milestone IDs are duplicated or absent from the schedule")

    claimed_usdcx = sum(milestone_amounts[mid][0] for mid in claimed_ids)
    claimed_ada = sum(milestone_amounts[mid][1] for mid in claimed_ids)
    if claimed_usdcx > allocated_usdcx or claimed_ada > allocated_ada:
        raise ValueError("claimed milestone amounts exceed the funded schedule")

    summary = FundingSummary(
        allocated_usdcx=allocated_usdcx,
        allocated_ada=allocated_ada,
        claimed_usdcx=claimed_usdcx,
        claimed_ada=claimed_ada,
        claimed_milestone_count=len(claimed_ids),
        milestone_count=len(milestone_amounts),
    )
    return funding_cards(summary)


def format_units(base_units: int, places: int = 2) -> str:
    unit = Decimal(10**6)
    quantum = Decimal(1).scaleb(-places)
    value = (Decimal(base_units) / unit).quantize(quantum, rounding=ROUND_HALF_UP)
    return f"{value:,.{places}f}"


def funding_cards(summary: FundingSummary) -> str:
    remaining_usdcx = summary.allocated_usdcx - summary.claimed_usdcx
    remaining_ada = summary.allocated_ada - summary.claimed_ada
    return (
        '<article class="funding-figure"><p class="label">Vendor Schedule</p>'
        f'<p class="value">{format_units(summary.allocated_usdcx)} USDCx</p>'
        f'<p class="subvalue">+ {format_units(summary.allocated_ada, 0)} ADA</p>'
        '<p class="note">Total milestone allocation from the funding metadata.</p></article>'
        '<article class="funding-figure"><p class="label">Claimed To Date</p>'
        f'<p class="value">{format_units(summary.claimed_usdcx)} USDCx</p>'
        f'<p class="subvalue">+ {format_units(summary.claimed_ada, 0)} ADA</p>'
        f'<p class="note">{summary.claimed_milestone_count} of {summary.milestone_count} milestones claimed, '
        'based on journal entries and their withdrawal metadata.</p></article>'
        '<article class="funding-figure"><p class="label">Unclaimed Schedule</p>'
        f'<p class="value">{format_units(remaining_usdcx)} USDCx</p>'
        f'<p class="subvalue">+ {format_units(remaining_ada, 0)} ADA</p>'
        '<p class="note">Remaining scheduled milestone amounts, including any paused milestones.</p></article>'
    )


def journal_card(entries: list[JournalEntry]) -> str:
    if not entries:
        raise ValueError("no journal entries available")

    items: list[str] = []
    for entry in entries[:5]:
        relative_path = f"journal/{entry.path.name}"
        journal_url = html.escape(github_file_url(relative_path), quote=True)
        date_text = entry.entry_date.isoformat()
        action = html.escape(entry.action)
        justification = html.escape(entry.justification)
        transaction_link = ""
        if TRANSACTION_HASH.fullmatch(entry.transaction_hash):
            tx_url = html.escape(
                f"https://cexplorer.io/tx/{entry.transaction_hash}", quote=True
            )
            transaction_link = f'<a href="{tx_url}">View transaction</a>'
        links = f'<a href="{journal_url}">Journal details</a>'
        if transaction_link:
            links = f"{transaction_link}{links}"
        items.append(
            "<li class=\"journal-entry\">"
            '<div class="journal-heading">'
            f'<span class="journal-action">{action}</span>'
            f'<time class="journal-date" datetime="{date_text}">{date_text}</time>'
            "</div>"
            f"<p>{justification}</p>"
            f'<div class="activity-links">{links}</div>'
            "</li>"
        )

    journal_index = html.escape(f"{REPOSITORY}/tree/main/journal", quote=True)
    return (
        '<article class="activity-card">'
        '<p class="activity-label">Recent Treasury Journal</p>'
        f'<ul class="journal-list">{"".join(items)}</ul>'
        f'<a class="activity-more" href="{journal_index}">Browse the full journal</a>'
        "</article>"
    )


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: render-pages-content.py REPOSITORY_ROOT OUTPUT_INDEX", file=sys.stderr)
        return 2

    repository_root = Path(sys.argv[1]).resolve()
    output_index = Path(sys.argv[2]).resolve()
    try:
        page = output_index.read_text(encoding="utf-8")
    except OSError as error:
        print(f"error: cannot read generated site index {output_index}: {error}", file=sys.stderr)
        return 1

    required_placeholders = {PLACEHOLDER, *PLACEHOLDERS.values(), *ROADMAP_STATUS_PLACEHOLDERS.values()}
    for placeholder in required_placeholders:
        if page.count(placeholder) != 1:
            print(
                f"error: expected one {placeholder} placeholder in {output_index}",
                file=sys.stderr,
            )
            return 1

    reports = load_reports(repository_root / "docs" / "reports")
    entries = load_journal(repository_root / "journal")
    if not reports:
        raise ValueError("no progress reports available")
    latest_report = reports[0]
    validate_latest_report(latest_report)
    replacements = {
        PLACEHOLDER: f"{report_card(reports)}\n{journal_card(entries)}",
        PLACEHOLDERS["status_period"]: status_period(latest_report),
        PLACEHOLDERS["current_status"]: current_status(latest_report),
        PLACEHOLDERS["upcoming"]: context_card(
            "Upcoming Work", latest_report.upcoming, latest_report
        ),
        PLACEHOLDERS["risks"]: context_card(
            "Risks and Issues", latest_report.risks, latest_report
        ),
        PLACEHOLDERS["funding"]: render_funding_summary(repository_root, entries),
    }
    replacements.update(
        {
            placeholder: roadmap_status(latest_report, quarter)
            for quarter, placeholder in ROADMAP_STATUS_PLACEHOLDERS.items()
        }
    )
    for placeholder, rendered in replacements.items():
        page = page.replace(placeholder, rendered)
    if "<!-- GENERATED_" in page:
        raise ValueError("unresolved generated content placeholder")
    output_index.write_text(page, encoding="utf-8")
    print(
        f"Rendered {len(reports)} reports and {min(len(entries), 5)} journal entries"
        f" into {output_index}"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1) from None
