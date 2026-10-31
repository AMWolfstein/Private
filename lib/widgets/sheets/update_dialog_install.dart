part of 'update_dialog.dart';

class _VersionChip extends StatelessWidget {
  final String version;
  final String label;
  final ColorScheme colorScheme;
  final bool isNew;

  const _VersionChip({
    required this.version,
    required this.label,
    required this.colorScheme,
    this.isNew = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        Text(
          'v$version',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: isNew ? colorScheme.primary : colorScheme.onSurfaceVariant,
            fontWeight: isNew ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

Future<String> _hashApkInBackground(String path) async =>
    (await sha256.bind(File(path).openRead()).first).toString();
