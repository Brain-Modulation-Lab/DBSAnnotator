"""Helpers to keep related Word report blocks on the same page."""

from __future__ import annotations

from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.table import Table
from docx.text.paragraph import Paragraph


def keep_with_next(paragraph: Paragraph) -> None:
    """Keep *paragraph* on the same page as the following paragraph or table."""
    paragraph.paragraph_format.keep_with_next = True


def keep_paragraphs_with_following_block(paragraphs: list[Paragraph]) -> None:
    """Glue *paragraphs* to each other and to the block that follows them."""
    for paragraph in paragraphs:
        keep_with_next(paragraph)


def keep_table_rows_together(table: Table) -> None:
    """Prevent table rows (e.g. electrode captions and images) from splitting."""
    for row in table.rows:
        tr = row._tr
        tr_pr = tr.get_or_add_trPr()
        if tr_pr.find(qn("w:cantSplit")) is None:
            tr_pr.append(OxmlElement("w:cantSplit"))
