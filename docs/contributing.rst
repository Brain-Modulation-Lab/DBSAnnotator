Contributing to Clinical DBS Annotator
====================================

We welcome contributions to the Clinical DBS Annotator! This document provides guidelines for contributors who want to help improve this open-source software for deep brain stimulation research.

.. contents::
   :local:
   :depth: 2

Getting Started
---------------

Prerequisites
~~~~~~~~~~~~~

To contribute to this project, you should have:

- Python 3.8 or higher
- Git installed and configured
- Basic knowledge of PyQt5/PyQt6 (helpful but not required)
- Understanding of deep brain stimulation concepts (helpful but not required)

Development Setup
~~~~~~~~~~~~~~~~~

1. **Fork the repository** on GitHub and clone your fork:

   .. code-block:: bash

      git clone https://github.com/yourusername/App_ClinicalDBSAnnot.git
      cd App_ClinicalDBSAnnot

2. **Create a virtual environment**:

   .. code-block:: bash

      python -m venv .venv
      source .venv/bin/activate  # On Windows: .venv\Scripts\activate

3. **Install dependencies**:

   .. code-block:: bash

      pip install -r requirements.txt
      pip install -r docs/requirements.txt

4. **Install in development mode**:

   .. code-block:: bash

      pip install -e .

5. **Run the application** to verify installation:

   .. code-block:: bash

      python -m clinical_dbs_annotator

Types of Contributions
----------------------

We welcome the following types of contributions:

Bug Reports
~~~~~~~~~~~

If you find a bug, please:

1. **Check existing issues** to see if it's already reported
2. **Create a new issue** with:
   - Clear title describing the bug
   - Steps to reproduce the issue
   - Expected vs actual behavior
   - System information (OS, Python version, etc.)
   - Screenshots if applicable

Feature Requests
~~~~~~~~~~~~~~~~

For new features:

1. **Check existing issues** for similar requests
2. **Create an issue** describing:
   - The feature you'd like to see
   - Why it would be useful
   - How you envision it working
   - Any implementation ideas you have

Code Contributions
~~~~~~~~~~~~~~~~~~

We accept code contributions through pull requests. Please follow these guidelines:

1. **Fork and create a branch**:

   .. code-block:: bash

      git checkout -b feature/your-feature-name

2. **Make your changes** following our coding standards (see below)

3. **Test your changes** thoroughly

4. **Commit your changes**:

   .. code-block:: bash

      git commit -m "feat: add new feature description"

5. **Push to your fork** and create a pull request

Documentation Improvements
~~~~~~~~~~~~~~~~~~~~~~~~~

Documentation is crucial for research software. We welcome:

- Improved README sections
- Better API documentation
- Additional examples and tutorials
- Translation to other languages
- Fixing typos and grammatical errors

Code Standards
---------------

Style Guidelines
~~~~~~~~~~~~~~~~

We follow these coding standards:

- **Python**: PEP 8 style guide
- **Docstrings**: Google style or NumPy style
- **Comments**: Clear, concise comments explaining complex logic
- **Variable names**: Descriptive names in snake_case
- **Class names**: PascalCase

Example:

.. code-block:: python

   def calculate_stimulation_amplitude(self, contact_states: Dict) -> float:
       """Calculate the total stimulation amplitude for given contact states.
       
       Args:
           contact_states: Dictionary mapping contact indices to their states
           
       Returns:
           Total stimulation amplitude in milliamps
           
       Raises:
           ValueError: If contact states are invalid
       """
       if not contact_states:
           raise ValueError("Contact states cannot be empty")
       
       total_amplitude = 0.0
       for contact_idx, state in contact_states.items():
           if state == ContactState.CATHODIC:
               total_amplitude += self.contact_amplitudes.get(contact_idx, 0.0)
       
       return total_amplitude

Testing
~~~~~~~

All new features should include tests:

1. **Unit tests** for individual functions/classes
2. **Integration tests** for GUI interactions
3. **Manual testing** for user workflows

Test structure:

.. code-block:: python

   import unittest
   from clinical_dbs_annotator.models.electrode_viewer import ElectrodeCanvas

   class TestElectrodeCanvas(unittest.TestCase):
       def setUp(self):
           self.canvas = ElectrodeCanvas()
       
       def test_scale_calculation(self):
           """Test that scale calculation works correctly."""
           # Mock electrode model
           mock_model = Mock()
           mock_model.num_contacts = 8
           mock_model.contact_height = 1.5
           mock_model.contact_spacing = 0.5
           
           self.canvas.model = mock_model
           scale = self.canvas.calculate_scale()
           
           self.assertIsInstance(scale, float)
           self.assertGreater(scale, 0)

Run tests with:

.. code-block:: bash

   python -m pytest tests/

GUI Testing
~~~~~~~~~~~

For GUI components:

1. **Test widget creation** doesn't crash
2. **Test user interactions** (clicks, inputs)
3. **Test data flow** between components
4. **Test error handling** in user interactions

Pull Request Process
--------------------

Before Submitting
~~~~~~~~~~~~~~~~~

1. **Update documentation** if needed
2. **Add tests** for new functionality
3. **Run all tests** and ensure they pass
4. **Check code style** with tools like flake8 or black
5. **Test the application** manually

Pull Request Template
~~~~~~~~~~~~~~~~~~~~~

When creating a pull request, please include:

**Description**
- Brief description of changes
- Why these changes are needed
- How you tested the changes

**Type of Change**
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

**Testing**
- [ ] Unit tests pass
- [ ] Manual testing completed
- [ ] GUI testing completed

**Checklist**
- [ ] Code follows project style guidelines
- [ ] Self-review completed
- [ ] Documentation updated
- [ ] Tests added/updated

Review Process
~~~~~~~~~~~~~~

Our review process:

1. **Automated checks** (tests, code style)
2. **Peer review** by maintainers
3. **Discussion** of any required changes
4. **Testing** by reviewer
5. **Approval** and merge

Community Guidelines
--------------------

Code of Conduct
~~~~~~~~~~~~~~~

We are committed to providing a welcoming and inclusive environment. Please:

- Be respectful and professional
- Welcome newcomers and help them learn
- Focus on constructive feedback
- Assume good intentions
- Be patient with different perspectives

Communication Channels
~~~~~~~~~~~~~~~~~~~~~

- **GitHub Issues**: For bug reports and feature requests
- **GitHub Discussions**: For general questions and ideas
- **Pull Requests**: For code contributions

Getting Help
~~~~~~~~~~~~

If you need help contributing:

1. **Check existing issues** and discussions
2. **Read the documentation** thoroughly
3. **Ask questions** in GitHub Discussions
4. **Contact maintainers** if needed

Recognition
~~~~~~~~~~~~

Contributors are recognized through:

- **Author credits** in commit history
- **Contributors section** in README
- **Co-authorship** opportunities for significant contributions
- **Acknowledgments** in publications

Research Impact
~~~~~~~~~~~~~~~

This software is designed for research use. If you use or extend this software in your research:

- **Cite the software** in your publications
- **Let us know** about your use cases
- **Share feedback** to help improve the software
- **Consider contributing** improvements back

Development Workflow
---------------------

Branch Strategy
~~~~~~~~~~~~~~~

We use a simple branching strategy:

- ``main``: Stable production code
- ``develop``: Integration branch for features
- ``feature/*``: Feature development branches
- ``bugfix/*``: Bug fix branches
- ``hotfix/*``: Critical fixes for production

Release Process
~~~~~~~~~~~~~~~

1. **Update version number** in setup.py
2. **Update changelog** with new features and fixes
3. **Create release tag** on GitHub
4. **Upload to PyPI** (if applicable)
5. **Update documentation**

Continuous Integration
~~~~~~~~~~~~~~~~~~~~~~~

We use GitHub Actions for:

- **Automated testing** on multiple Python versions
- **Code style checks**
- **Documentation building**
- **Package building**

Specialized Contributions
------------------------

Clinical Domain Experts
~~~~~~~~~~~~~~~~~~~~~~~

If you're a clinical researcher or DBS specialist:

- **Share use cases** and workflows
- **Suggest improvements** based on clinical needs
- **Provide feedback** on electrode models and stimulation patterns
- **Help validate** clinical accuracy

GUI/UX Experts
~~~~~~~~~~~~~~

For contributors with GUI expertise:

- **Improve user interface** design
- **Enhance user experience** workflows
- **Test accessibility** features
- **Suggest visual improvements**

Data Scientists
~~~~~~~~~~~~~~~

For data science contributions:

- **Improve data analysis** features
- **Add statistical tools** for outcome analysis
- **Enhance longitudinal reporting**
- **Integrate with external tools**

Thank You
----------

Thank you for considering contributing to the Clinical DBS Annotator! Your contributions help make deep brain stimulation research more accessible and effective for the research community.

For questions about contributing, please open an issue or start a discussion on GitHub.
