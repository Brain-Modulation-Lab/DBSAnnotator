"""
Clinical scale data models.

This module contains classes for managing clinical assessment scales
used in DBS programming sessions.
"""

import math
from dataclasses import dataclass

# Written to TSV when a Step 3 session scale is deactivated (X); must stay
# a literal string on round-trip (see pandas read_csv na_filter=False).
SESSION_SCALE_OMITTED_TSV = "NaN"


def is_session_scale_value_omitted(value: object) -> bool:
    """True if *value* means the scale was not scored (omit from reports)."""
    if value is None:
        return True
    try:
        if isinstance(value, (int, float, str, bytes, bytearray)):
            fv = float(value)
            if math.isnan(fv):
                return True
    except (TypeError, ValueError, OverflowError):
        pass
    s = str(value).strip()
    if not s:
        return True
    lowered = s.lower()
    return lowered == "nan" or lowered == "<na>"


@dataclass
class ClinicalScale:
    """
    Represents a clinical assessment scale with a name and value.

    Attributes:
        name: The name of the clinical scale (e.g., "YBOCS", "MADRS")
        value: The score/value for this scale (optional)
    """

    name: str
    value: str | None = None

    def is_valid(self) -> bool:
        """Check if the scale has both name and value."""
        return bool(
            self.name and self.name.strip() and self.value and self.value.strip()
        )

    def __repr__(self) -> str:
        return f"ClinicalScale(name='{self.name}', value='{self.value}')"


@dataclass
class SessionScale:
    """
    Represents a session tracking scale with name and min/max range.

    Attributes:
        name: The name of the session scale (e.g., "Mood", "Anxiety")
        min_value: Minimum value for the scale
        max_value: Maximum value for the scale
        current_value: Current value during session (optional)
    """

    name: str
    min_value: str = "0"
    max_value: str = "10"
    current_value: str | None = None

    def is_valid(self) -> bool:
        """Check if the scale has a valid name."""
        return bool(self.name and self.name.strip())

    def has_value(self) -> bool:
        """Check if the scale has a current value set."""
        return bool(self.current_value and self.current_value.strip())

    def __repr__(self) -> str:
        return (
            f"SessionScale(name='{self.name}', "
            f"range=[{self.min_value}, {self.max_value}], "
            f"value='{self.current_value}')"
        )
