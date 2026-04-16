"""
Stimulation parameters data model.

This module contains the class for managing Deep Brain Stimulation parameters
including frequency, contacts, amplitudes, and pulse widths.
"""

from dataclasses import dataclass


@dataclass
class StimulationParameters:
    """
    Represents DBS stimulation parameters for both left and right sides.

    Attributes:
        left_frequency: Left stimulation frequency in Hz
        left_cathode: Left electrode cathode configuration
        left_anode: Left electrode anode configuration
        left_amplitude: Left stimulation amplitude in mA
        left_pulse_width: Left pulse width in µs
        right_frequency: Right stimulation frequency in Hz
        right_cathode: Right electrode cathode configuration
        right_anode: Right electrode anode configuration
        right_amplitude: Right stimulation amplitude in mA
        right_pulse_width: Right pulse width in µs
    """

    left_frequency: str | None = None
    left_cathode: str | None = None
    left_anode: str | None = None
    left_amplitude: str | None = None
    left_pulse_width: str | None = None
    right_frequency: str | None = None
    right_cathode: str | None = None
    right_anode: str | None = None
    right_amplitude: str | None = None
    right_pulse_width: str | None = None

    def to_dict(self) -> dict:
        """Convert stimulation parameters to a dictionary."""
        return {
            "left_stim_freq": self.left_frequency or "",
            "left_cathode": self.left_cathode or "",
            "left_anode": self.left_anode or "",
            "left_amplitude": self.left_amplitude or "",
            "left_pulse_width": self.left_pulse_width or "",
            "right_stim_freq": self.right_frequency or "",
            "right_cathode": self.right_cathode or "",
            "right_anode": self.right_anode or "",
            "right_amplitude": self.right_amplitude or "",
            "right_pulse_width": self.right_pulse_width or "",
        }

    @classmethod
    def from_dict(cls, data: dict) -> StimulationParameters:
        """Create StimulationParameters from a dictionary."""
        return cls(
            left_frequency=data.get("left_stim_freq"),
            left_cathode=data.get("left_cathode"),
            left_anode=data.get("left_anode"),
            left_amplitude=data.get("left_amplitude"),
            left_pulse_width=data.get("left_pulse_width"),
            right_frequency=data.get("right_stim_freq"),
            right_cathode=data.get("right_cathode"),
            right_anode=data.get("right_anode"),
            right_amplitude=data.get("right_amplitude"),
            right_pulse_width=data.get("right_pulse_width"),
        )

    def copy(self) -> StimulationParameters:
        """Create a copy of the stimulation parameters."""
        return StimulationParameters(
            left_frequency=self.left_frequency,
            left_cathode=self.left_cathode,
            left_anode=self.left_anode,
            left_amplitude=self.left_amplitude,
            left_pulse_width=self.left_pulse_width,
            right_frequency=self.right_frequency,
            right_cathode=self.right_cathode,
            right_anode=self.right_anode,
            right_amplitude=self.right_amplitude,
            right_pulse_width=self.right_pulse_width,
        )

    def __repr__(self) -> str:
        return (
            f"StimulationParameters("
            f"L:{self.left_frequency}Hz,C{self.left_cathode}/A{self.left_anode}@{self.left_amplitude}mA/{self.left_pulse_width}µs, "
            f"R:{self.right_frequency}Hz,C{self.right_cathode}/A{self.right_anode}@{self.right_amplitude}mA/{self.right_pulse_width}µs)"
        )
