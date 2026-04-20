API Reference
=============

This page is generated automatically from the docstrings of the
``dbs_annotator`` package.  It is aimed at developers extending or embedding
the application; clinicians and researchers should prefer the
:doc:`quickstart` and :doc:`workflow_session` guides.

The reference deliberately covers the **data, configuration, and control
layers** of the application.  The Qt UI layers (``dbs_annotator.ui`` and
``dbs_annotator.views``) are `PySide6 <https://doc.qt.io/qtforpython-6/>`_
subclasses whose public surface is Qt signals and slots; refer to the PySide6
documentation and the source itself for those.

.. autosummary::
   :toctree: _autosummary
   :template: autosummary/module.rst
   :recursive:

   dbs_annotator.config
   dbs_annotator.config_electrode_models
   dbs_annotator.controllers
   dbs_annotator.logging_config
   dbs_annotator.models
   dbs_annotator.utils
   dbs_annotator.version
