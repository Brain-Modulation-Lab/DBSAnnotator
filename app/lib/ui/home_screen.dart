import 'package:flutter/material.dart';

import '../app_info.dart';
import 'annotations_screen.dart';
import 'longitudinal_screen.dart';
import 'session_screen.dart';
import 'theme.dart';

/// Launcher mirroring the desktop Step 0 mode selection, touch-first.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DBS Annotator'),
        actions: const [
          TextSizeButtons(),
          HelpButton(),
          ThemeToggleButton()
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              _WorkflowCard(
                icon: Icons.medical_services_outlined,
                title: 'Complete workflow',
                subtitle: 'Stimulation params + scales + notes → reports',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SessionScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _WorkflowCard(
                icon: Icons.edit_note,
                title: 'Annotations only',
                subtitle: 'Notes → report',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AnnotationsScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _WorkflowCard(
                icon: Icons.timeline,
                title: 'Longitudinal review',
                subtitle: 'TSV reports → PDF report',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const LongitudinalScreen(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkflowCard extends StatelessWidget {
  const _WorkflowCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Card(
      child: ListTile(
        enabled: enabled,
        leading: Icon(icon, size: 36),
        title: Text(title, style: Theme.of(context).textTheme.titleLarge),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        onTap: onTap,
      ),
    );
  }
}
