"""
Configuration file for DBS electrode models
Based on Lead-DBS repository: https://github.com/netstim/leaddbs/tree/master/templates/electrode_models
All measurements in millimeters
"""


class ContactState:
    """Possible states for a contact"""

    OFF = 0
    ANODIC = 1
    CATHODIC = 2


class StimulationRule:
    """Rules for valid stimulation configurations"""

    _custom_validators = []

    @staticmethod
    def add_validator(validator_fn):
        """Register a custom validator.

        The callable must accept ``(contact_states, case_state)`` and return
        either ``(is_valid, error_message)`` or ``None``.
        """
        if validator_fn not in StimulationRule._custom_validators:
            StimulationRule._custom_validators.append(validator_fn)

    @staticmethod
    def validate_configuration(contact_states, case_state):
        """
        Validate stimulation configuration according to clinical rules

        Args:
            contact_states (dict): Dictionary mapping
                ``(contact_idx, segment_idx)`` to ``ContactState``.
            case_state (ContactState): State of the case

        Returns:
            tuple: (is_valid, error_message)
        """
        # Rule 1: If case is cathodic, no other contact can be cathodic
        if case_state == ContactState.CATHODIC:
            cathodic_contacts = [
                cid
                for cid, state in contact_states.items()
                if state == ContactState.CATHODIC
            ]
            if cathodic_contacts:
                return False, "When CASE is cathodic, no other contacts can be cathodic"

        # Rule 2: If case is anodic, no other contact can be anodic
        if case_state == ContactState.ANODIC:
            anodic_contacts = [
                cid
                for cid, state in contact_states.items()
                if state == ContactState.ANODIC
            ]
            if anodic_contacts:
                return False, "When CASE is anodic, no other contacts can be anodic"

        # Rule 3: At least one anodic contact must exist if any cathodic contact exists
        has_cathodic = any(
            state == ContactState.CATHODIC for state in contact_states.values()
        )
        has_anodic = case_state == ContactState.ANODIC or any(
            state == ContactState.ANODIC for state in contact_states.values()
        )

        if has_cathodic and not has_anodic:
            return (
                False,
                "At least one anodic contact (or CASE) required when using "
                "cathodic contacts",
            )

        for validator_fn in list(StimulationRule._custom_validators):
            try:
                result = validator_fn(contact_states, case_state)
            except Exception:
                result = None
            if result:
                is_valid, error_msg = result
                if not is_valid:
                    return False, error_msg

        return True, ""

    @staticmethod
    def get_suggested_fix(contact_states, case_state):
        """
        Suggest a fix for invalid configuration

        Args:
            contact_states (dict): Dictionary of contact states
            case_state (ContactState): State of the case

        Returns:
            str: Suggestion message
        """
        if case_state == ContactState.CATHODIC:
            cathodic_contacts = [
                cid
                for cid, state in contact_states.items()
                if state == ContactState.CATHODIC
            ]
            if cathodic_contacts:
                return (
                    "Suggestion: Turn off cathodic contacts or switch CASE "
                    "to anodic/off"
                )

        has_cathodic = any(
            state == ContactState.CATHODIC for state in contact_states.values()
        )
        has_anodic = case_state == ContactState.ANODIC or any(
            state == ContactState.ANODIC for state in contact_states.values()
        )

        if has_cathodic and not has_anodic:
            return "Suggestion: Add at least one anodic contact or set CASE to anodic"

        return ""


class ElectrodeModel:
    """Base class for electrode models"""

    def __init__(
        self,
        name,
        num_contacts,
        contact_height,
        contact_spacing,
        lead_diameter,
        is_directional=False,
        tip_contact=False,
        directional_levels=None,
    ):
        self.name = name
        self.num_contacts = num_contacts
        self.contact_height = contact_height  # mm
        self.contact_spacing = contact_spacing  # mm
        self.lead_diameter = lead_diameter  # mm
        self.is_directional = is_directional
        # True if the distal contact IS the tip (e.g. Boston Scientific).
        self.tip_contact = tip_contact
        self.segments_per_level = 3 if is_directional else 1
        self._directional_levels = (
            directional_levels  # Optional: 0-indexed list of levels that are segmented
        )

    def is_level_directional(self, level_idx):
        """Return True if the given level index has directional (segmented) contacts."""
        if not self.is_directional:
            return False
        if self._directional_levels is not None:
            return level_idx in self._directional_levels
        # Default: all levels except first and last are directional
        return 0 < level_idx < self.num_contacts - 1


# ============================================================================
# MEDTRONIC ELECTRODES
# ============================================================================

MEDTRONIC_3387 = ElectrodeModel(
    name="Medtronic 3387",
    num_contacts=4,
    contact_height=1.5,
    contact_spacing=1.5,
    lead_diameter=1.27,
    is_directional=False,
)

MEDTRONIC_3389 = ElectrodeModel(
    name="Medtronic 3389",
    num_contacts=4,
    contact_height=1.5,
    contact_spacing=0.5,
    lead_diameter=1.27,
    is_directional=False,
)

MEDTRONIC_3391 = ElectrodeModel(
    name="Medtronic 3391",
    num_contacts=4,
    contact_height=3.0,
    contact_spacing=4.0,
    lead_diameter=1.27,
    is_directional=False,
)

# Medtronic SenSight Directional Leads
MEDTRONIC_B33005 = ElectrodeModel(
    name="Medtronic SenSight B33005",
    num_contacts=4,
    contact_height=1.5,
    contact_spacing=0.5,
    lead_diameter=1.27,
    is_directional=True,
)

MEDTRONIC_B33015 = ElectrodeModel(
    name="Medtronic SenSight B33015",
    num_contacts=4,
    contact_height=1.5,
    contact_spacing=1.5,
    lead_diameter=1.27,
    is_directional=True,
)

# ============================================================================
# BOSTON SCIENTIFIC ELECTRODES
# ============================================================================

BOSTON_VERCISE = ElectrodeModel(
    name="Boston Scientific Vercise",
    num_contacts=8,
    contact_height=1.5,
    contact_spacing=0.5,
    lead_diameter=1.3,
    is_directional=False,
    tip_contact=True,
)

BOSTON_VERCISE_DIRECTED = ElectrodeModel(
    name="Boston Scientific Vercise Directed",
    num_contacts=4,
    contact_height=1.5,
    contact_spacing=0.5,
    lead_diameter=1.3,
    is_directional=True,
    tip_contact=True,
    directional_levels=[1, 2],  # Ring(tip)-Seg×3-Seg×3-Ring = 8 contacts
)

BOSTON_VERCISE_CARTESIA_HX = ElectrodeModel(
    name="Boston Scientific Vercise Cartesia HX",
    num_contacts=6,
    contact_height=1.5,
    contact_spacing=1.5,
    lead_diameter=1.3,
    is_directional=True,
    tip_contact=True,
    directional_levels=[1, 2, 3, 4, 5],  # Ring(tip)+5×Seg×3 = 16 contacts
)

BOSTON_VERCISE_CARTESIA_X = ElectrodeModel(
    name="Boston Scientific Vercise Cartesia X",
    num_contacts=6,
    contact_height=1.5,
    contact_spacing=0.5,
    lead_diameter=1.3,
    is_directional=True,
    tip_contact=True,
    directional_levels=[1, 2, 3, 4, 5],  # Ring(tip)+5×Seg×3 = 16 contacts
)

# ============================================================================
# ABBOTT (ST. JUDE) ELECTRODES
# ============================================================================

ABBOTT_ACTIVETIP_6142_6145 = ElectrodeModel(
    name="Abbott ActiveTip 6142-6145",
    num_contacts=4,
    contact_height=1.5,
    contact_spacing=0.5,
    lead_diameter=1.27,
    is_directional=False,
)

ABBOTT_ACTIVETIP_6146_6149 = ElectrodeModel(
    name="Abbott ActiveTip 6146-6149",
    num_contacts=4,
    contact_height=1.5,
    contact_spacing=1.5,
    lead_diameter=1.27,
    is_directional=False,
)

ABBOTT_STJUDE_INFINITY_6172 = ElectrodeModel(
    name="Abbott StJude 6172",
    num_contacts=4,
    contact_height=1.5,
    contact_spacing=0.5,
    lead_diameter=1.29,
    is_directional=True,
)

ABBOTT_STJUDE_INFINITY_6173 = ElectrodeModel(
    name="Abbott StJude 6173",
    num_contacts=4,
    contact_height=1.5,
    contact_spacing=1.5,
    lead_diameter=1.29,
    is_directional=True,
)

# ABBOTT_INFINITY_6172 = ElectrodeModel(
#     name='Abbott Infinity 6172',
#     num_contacts=8,
#     contact_height=1.5,
#     contact_spacing=0.5,
#     lead_diameter=1.27,
#     is_directional=False
# )

# ABBOTT_INFINITY_6173 = ElectrodeModel(
#     name='Abbott Infinity 6173',
#     num_contacts=8,
#     contact_height=1.5,
#     contact_spacing=1.5,
#     lead_diameter=1.27,
#     is_directional=False
# )

# ABBOTT_INFINITY_DIRECTED = ElectrodeModel(
#     name='Abbott Infinity Directed',
#     num_contacts=8,
#     contact_height=1.5,
#     contact_spacing=0.5,
#     lead_diameter=1.27,
#     is_directional=True
# )

# ============================================================================
# PINS MEDICAL (CHINA) ELECTRODES
# ============================================================================

PINS_L301 = ElectrodeModel(
    name="PINS Medical L301",
    num_contacts=4,
    contact_height=1.5,
    contact_spacing=0.5,
    lead_diameter=1.27,
    is_directional=False,
)

PINS_L302 = ElectrodeModel(
    name="PINS Medical L302",
    num_contacts=4,
    contact_height=1.5,
    contact_spacing=1.5,
    lead_diameter=1.27,
    is_directional=False,
)

PINS_L303 = ElectrodeModel(
    name="PINS Medical L303",
    num_contacts=4,
    contact_height=3.0,
    contact_spacing=4.0,
    lead_diameter=1.27,
    is_directional=False,
)

# ============================================================================
# ALEVA NEUROTHERAPEUTICS ELECTRODES
# ============================================================================

ALEVA_DIRECTSTIM = ElectrodeModel(
    name="ALEVA directSTIM",
    num_contacts=4,
    contact_height=1.5,
    contact_spacing=0.5,
    lead_diameter=1.27,
    is_directional=True,
    directional_levels=[
        0,
        1,
        2,
        3,
    ],  # ALL 4 levels segmented (3-3-3-3), no ring contacts = 12 contacts
)

# ============================================================================
# ELECTRODE MODELS DICTIONARY
# ============================================================================

ELECTRODE_MODELS = {
    # Medtronic
    "Medtronic 3387": MEDTRONIC_3387,
    "Medtronic 3389": MEDTRONIC_3389,
    "Medtronic 3391": MEDTRONIC_3391,
    "Medtronic SenSight B33005": MEDTRONIC_B33005,
    "Medtronic SenSight B33015": MEDTRONIC_B33015,
    # Boston Scientific
    "Boston Scientific Vercise": BOSTON_VERCISE,
    "Boston Scientific Vercise Directed": BOSTON_VERCISE_DIRECTED,
    "Boston Scientific Vercise Cartesia HX": BOSTON_VERCISE_CARTESIA_HX,
    "Boston Scientific Vercise Cartesia X": BOSTON_VERCISE_CARTESIA_X,
    # Abbott (St. Jude)
    "Abbott ActiveTip 6142-6145": ABBOTT_ACTIVETIP_6142_6145,
    "Abbott ActiveTip 6146-6149": ABBOTT_ACTIVETIP_6146_6149,
    "Abbott StJude Infinity 6172": ABBOTT_STJUDE_INFINITY_6172,
    "Abbott StJude Infinity 6173": ABBOTT_STJUDE_INFINITY_6173,
    # 'Abbott Infinity 6172': ABBOTT_INFINITY_6172,
    # 'Abbott Infinity 6173': ABBOTT_INFINITY_6173,
    # 'Abbott Infinity Directed': ABBOTT_INFINITY_DIRECTED,
    # PINS Medical
    "PINS Medical L301": PINS_L301,
    "PINS Medical L302": PINS_L302,
    "PINS Medical L303": PINS_L303,
    # ALEVA
    "ALEVA directSTIM": ALEVA_DIRECTSTIM,
}


# ============================================================================
# MANUFACTURER GROUPING (for organized UI)
# ============================================================================

MANUFACTURERS = {
    "Medtronic": [
        "Medtronic 3387",
        "Medtronic 3389",
        "Medtronic 3391",
        "Medtronic SenSight B33005",
        "Medtronic SenSight B33015",
    ],
    "Boston Scientific": [
        "Boston Scientific Vercise",
        "Boston Scientific Vercise Directed",
        "Boston Scientific Vercise Cartesia HX",
        "Boston Scientific Vercise Cartesia X",
    ],
    "Abbott": [
        "Abbott ActiveTip 6142-6145",
        "Abbott ActiveTip 6146-6149",
        "Abbott StJude Infinity 6172",
        "Abbott StJude Infinity 6173",
        # 'Abbott Infinity 6172',
        # 'Abbott Infinity 6173',
        # 'Abbott Infinity Directed',
    ],
    "PINS Medical": [
        "PINS Medical L301",
        "PINS Medical L302",
        "PINS Medical L303",
    ],
    "ALEVA": [
        "ALEVA directSTIM",
    ],
}


def get_model_by_name(name):
    """
    Get electrode model by name

    Args:
        name (str): Model name

    Returns:
        ElectrodeModel: Electrode model object or None if not found
    """
    return ELECTRODE_MODELS.get(name, None)


def get_all_model_names():
    """
    Get list of all electrode model names

    Returns:
        list: List of model names
    """
    return list(ELECTRODE_MODELS.keys())


def get_models_by_manufacturer(manufacturer):
    """
    Get list of models for a specific manufacturer

    Args:
        manufacturer (str): Manufacturer name

    Returns:
        list: List of model names for the manufacturer
    """
    return MANUFACTURERS.get(manufacturer, [])


def get_all_manufacturers():
    """
    Get list of all manufacturers

    Returns:
        list: List of manufacturer names
    """
    return list(MANUFACTURERS.keys())
