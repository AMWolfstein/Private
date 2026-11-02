import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/core/models/app_crash_report.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/services/platform/app_crash_service.dart';
import 'package:sistrum/widgets/primitives/app_bottom_sheet.dart';
import 'package:sistrum/utils/logging/logger.dart';

final latestAppCrashProvider = FutureProvider.autoDispose<AppCrashReport?>((
  ref,
) async {
  try {
    final report = await AppCrashService.latest();
    return report == null ? null : AppCrashReport.fromMap(report);
  } on MissingPluginException {
    return null;
  } catch (error) {
    AppLogger('CrashReport').w('Could not load saved crash report: $error');
    return null;
  }
});

/// A saved process-exit report, retained independently of the live log buffer.
class AppCrashDiagnostic extends ConsumerWidget {
  const AppCrashDiagnostic({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(latestAppCrashProvider).asData?.value;
    if (report == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: ListTile(
          leading: const Icon(Icons.error_outline),
          title: Text(
            report.isAnr
                ? context.l10n.appAnrTitle
                : context.l10n.appCrashTitle,
          ),
          subtitle: Text(
            report.description.isEmpty ? report.reason : report.description,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            tooltip: context.l10n.appCrashCopy,
            icon: const Icon(Icons.copy),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: report.report));
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(context.l10n.logCopied)));
              }
            },
          ),
          onTap: () => showAppBottomSheet<void>(
            context: context,
            title: report.isAnr
                ? context.l10n.appAnrTitle
                : context.l10n.appCrashTitle,
            maxHeightFactor: .9,
            builder: (_) => SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: SelectableText(report.report),
            ),
          ),
        ),
      ),
    );
  }
}
