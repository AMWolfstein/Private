part of 'setup_screen.dart';

extension _SetupScreenStatePart2 on _SetupScreenState {
  Widget _buildLanguageStep(ColorScheme colorScheme) {
    final languages = supportedLanguageChoices;

    return LayoutBuilder(
      builder: (context, constraints) {
        final shortestSide = MediaQuery.sizeOf(context).shortestSide;
        final iconPadding = (shortestSide * 0.06).clamp(16.0, 24.0);
        final iconSize = (shortestSide * 0.12).clamp(32.0, 48.0);
        final titleGap = (shortestSide * 0.06).clamp(16.0, 32.0);
        final descriptionGap = (shortestSide * 0.04).clamp(8.0, 16.0);
        final actionGap = (shortestSide * 0.09).clamp(20.0, 48.0);

        return Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                24 + wideListInset(context, contentMaxWidth: 560),
                24,
                24 + wideListInset(context, contentMaxWidth: 560),
                0,
              ),
              child: Column(
                children: [
                  Container(
                    padding: EdgeInsets.all(iconPadding),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.translate,
                      size: iconSize,
                      color: colorScheme.primary,
                    ),
                  ),
                  SizedBox(height: titleGap),
                  Text(
                    context.l10n.setupLanguageTitle,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: descriptionGap),
                  Text(
                    context.l10n.setupLanguageDescription,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: actionGap),
                ],
              ),
            ),
            Expanded(
              child: ScrollEdgeFade(
                child: Scrollbar(
                  controller: _languageScrollController,
                  thumbVisibility: true,
                  child: _buildLanguageList(languages, colorScheme),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLanguageList(
    List<(String, String, IconData)> languages,
    ColorScheme colorScheme,
  ) {
    return ListView.builder(
      controller: _languageScrollController,
      padding: EdgeInsets.fromLTRB(
        24 + wideListInset(context, contentMaxWidth: 560),
        0,
        24 + wideListInset(context, contentMaxWidth: 560),
        80,
      ),
      itemCount: languages.length,
      itemBuilder: (context, index) {
        final lang = languages[index];
        final code = lang.$1;
        final name = lang.$2;
        final isSelected = _selectedLocale == code;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Material(
            color: isSelected
                ? colorScheme.primaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _onLanguageSelected(code),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Icon(
                      lang.$3,
                      color: isSelected
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurfaceVariant,
                      size: 22,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        code == 'system'
                            ? context.l10n.setupLanguageSystemDefault
                            : name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: isSelected
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurface,
                        ),
                      ),
                    ),
                    if (isSelected)
                      Icon(
                        Icons.check_circle,
                        color: colorScheme.onPrimaryContainer,
                        size: 22,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStorageStep(ColorScheme colorScheme) {
    final scopedFolder =
        _platform == TargetPlatform.android && _androidSdkVersion >= 29;
    return SetupStepLayout(
      title: context.l10n.setupStorageRequired,
      description: scopedFolder
          ? context.l10n.setupLibraryFolderDescription
          : context.l10n.setupStorageDescription,
      icon: Icons.folder,
      child: _storagePermissionGranted
          ? SetupSuccessCard(
              text: context.l10n.setupStorageGranted,
              colorScheme: colorScheme,
            )
          : Column(
              children: [
                FilledButton.tonalIcon(
                  onPressed: _requestStoragePermission,
                  icon: const Icon(Icons.folder_open),
                  label: Text(
                    scopedFolder
                        ? context.l10n.setupChooseMusicFolder
                        : context.l10n.setupGrantPermission,
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                  ),
                ),
                if (scopedFolder)
                  TextButton(
                    onPressed: () async {
                      _rebuild(() => _storageSkipped = true);
                      await _saveProgress();
                    },
                    child: Text(context.l10n.setupSkipForNow),
                  ),
              ],
            ),
    );
  }

  Widget _buildNotificationStep(ColorScheme colorScheme) {
    return SetupStepLayout(
      title: context.l10n.setupNotificationEnable,
      description: context.l10n.setupNotificationBackgroundDescription,
      icon: Icons.notifications,
      child: _notificationPermissionGranted || _notificationPermissionSkipped
          ? SetupSuccessCard(
              text: context.l10n.setupNotificationGranted,
              colorScheme: colorScheme,
            )
          : Column(
              children: [
                FilledButton.tonalIcon(
                  onPressed: _requestNotificationPermission,
                  icon: const Icon(Icons.notifications_active),
                  label: Text(context.l10n.setupEnableNotifications),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    _rebuild(() => _notificationPermissionSkipped = true);
                    await _saveProgress();
                  },
                  child: Text(context.l10n.setupSkipForNow),
                ),
              ],
            ),
    );
  }
}
