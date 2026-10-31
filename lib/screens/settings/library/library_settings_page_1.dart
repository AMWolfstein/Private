part of 'library_settings_page.dart';

extension _LibrarySettingsPageStatePart1 on _LibrarySettingsPageState {
  Future<void> _initDeviceInfo() async {
    if (Platform.isAndroid) {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final sdkVersion = androidInfo.version.sdkInt;

      if (mounted) {
        _rebuild(() {
          _androidSdkVersion = sdkVersion;
          _hasStoragePermission = sdkVersion >= 29;
        });
        if (sdkVersion < 29) {
          final hasPermission = await Permission.storage.isGranted;
          if (mounted) {
            _rebuild(() => _hasStoragePermission = hasPermission);
          }
        }
      }
    } else {
      _rebuild(() => _hasStoragePermission = true);
    }
  }

  Future<bool> _requestStoragePermission() async {
    if (!Platform.isAndroid) return true;
    if (_androidSdkVersion >= 29) return true;

    final status = await Permission.storage.request();

    if (status.isGranted) {
      if (mounted) _rebuild(() => _hasStoragePermission = true);
      return true;
    } else if (status.isPermanentlyDenied) {
      if (mounted) {
        final shouldOpen = await showAppDialog<bool>(
          context: context,
          builder: (context) => AppAlertDialog(
            title: Text(context.l10n.libraryStorageAccessRequired),
            content: Text(context.l10n.libraryStorageAccessMessage),
            actions: [
              AppDialogAction(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.l10n.dialogCancel),
              ),
              AppDialogAction(
                filled: true,
                isDefault: true,
                onPressed: () => Navigator.pop(context, true),
                child: Text(context.l10n.setupOpenSettings),
              ),
            ],
          ),
        );
        if (shouldOpen == true) {
          await openAppSettings();
        }
      }
    }
    return false;
  }

  Future<void> _pickLibraryFolder() async {
    try {
      await _pickLibraryFolderInternal();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.snackbarError(context.friendlyError(error)),
          ),
        ),
      );
    }
  }

  Future<void> _pickLibraryFolderInternal() async {
    // Older Android needs storage permission; Android 10+ and iOS pick a
    // folder through the scoped picker.
    if (!_hasStoragePermission) {
      final granted = await _requestStoragePermission();
      if (!granted || !mounted) return;
    }
    final messenger = ScaffoldMessenger.of(context);
    await selectLibraryFolder(
      ref.read(localLibraryProvider.notifier),
      androidSdkVersion: _androidSdkVersion,
      onFailure: (message) {
        if (mounted) {
          messenger.showSnackBar(SnackBar(content: Text(message)));
        }
      },
    );
  }

  Future<void> _startScan({bool forceFullScan = false}) async {
    final sources = ref.read(localLibraryProvider).sources;
    if (sources.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.libraryScanSelectFolderFirst)),
      );
      return;
    }
    try {
      await ref
          .read(localLibraryProvider.notifier)
          .scanAllSources(forceFullScan: forceFullScan);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.snackbarError(context.friendlyError(error)),
          ),
        ),
      );
    }
  }

  Future<void> _cancelScan() async {
    await ref.read(localLibraryProvider.notifier).cancelScan();
  }

  Future<void> _pauseScan() async {
    await ref.read(localLibraryProvider.notifier).pauseScan();
  }

  Future<void> _resumeScan() async {
    await ref.read(localLibraryProvider.notifier).resumeScan();
  }

  Future<void> _clearLibrary() async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AppAlertDialog(
        title: Text(context.l10n.libraryClearConfirmTitle),
        content: Text(context.l10n.libraryClearConfirmMessage),
        actions: appDestructiveConfirmActions(
          context,
          cancelLabel: context.l10n.dialogCancel,
          confirmLabel: context.l10n.dialogClear,
          cancelIsDefault: true,
        ),
      ),
    );

    if (confirmed == true) {
      await ref.read(localLibraryProvider.notifier).clearLibrary();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.libraryCleared)));
      }
    }
  }

  Future<void> _cleanupMissingFiles() async {
    if (_isCleaningMissingFiles || ref.read(localLibraryProvider).isScanning) {
      return;
    }
    final library = ref.read(localLibraryProvider.notifier);
    _rebuild(() => _isCleaningMissingFiles = true);
    try {
      final missingLibraryEntries = await library.cleanupMissingFiles();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.libraryRemovedMissingFiles(missingLibraryEntries),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.snackbarError(context.friendlyError(error)),
          ),
        ),
      );
    } finally {
      if (mounted) _rebuild(() => _isCleaningMissingFiles = false);
    }
  }

  Future<void> _removeSource(LocalLibrarySource source) async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AppAlertDialog(
        title: Text(context.l10n.libraryRemoveFolder),
        content: Text(context.l10n.libraryRemoveFolderMessage),
        actions: appDestructiveConfirmActions(
          context,
          cancelLabel: context.l10n.dialogCancel,
          confirmLabel: context.l10n.dialogRemove,
          cancelIsDefault: true,
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(localLibraryProvider.notifier).removeSource(source.id);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.snackbarError(context.friendlyError(error)),
          ),
        ),
      );
      return;
    }
  }

  String _getAutoScanLabel(BuildContext context, String mode) {
    switch (mode) {
      case 'on_open':
        return context.l10n.libraryAutoScanOnOpen;
      case 'daily':
        return context.l10n.libraryAutoScanDaily;
      case 'weekly':
        return context.l10n.libraryAutoScanWeekly;
      default:
        return context.l10n.libraryAutoScanOff;
    }
  }

  void _showAutoScanPicker(BuildContext context, String current) {
    showAppScrollableBottomSheet<void>(
      context: context,
      title: context.l10n.libraryAutoScan,
      subtitle: context.l10n.libraryAutoScanSubtitle,
      builder: (context, controller) => SingleChildScrollView(
        controller: controller,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AutoScanOption(
              icon: Icons.block,
              title: context.l10n.libraryAutoScanOff,
              selected: current == 'off',
              onTap: () {
                ref
                    .read(settingsProvider.notifier)
                    .setLocalLibraryAutoScan('off');
                Navigator.pop(context);
              },
            ),
            AutoScanOption(
              icon: Icons.open_in_new,
              title: context.l10n.libraryAutoScanOnOpen,
              selected: current == 'on_open',
              onTap: () {
                ref
                    .read(settingsProvider.notifier)
                    .setLocalLibraryAutoScan('on_open');
                Navigator.pop(context);
              },
            ),
            AutoScanOption(
              icon: Icons.today,
              title: context.l10n.libraryAutoScanDaily,
              selected: current == 'daily',
              onTap: () {
                ref
                    .read(settingsProvider.notifier)
                    .setLocalLibraryAutoScan('daily');
                Navigator.pop(context);
              },
            ),
            AutoScanOption(
              icon: Icons.date_range,
              title: context.l10n.libraryAutoScanWeekly,
              selected: current == 'weekly',
              onTap: () {
                ref
                    .read(settingsProvider.notifier)
                    .setLocalLibraryAutoScan('weekly');
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
