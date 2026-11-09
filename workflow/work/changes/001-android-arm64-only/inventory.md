# Removal inventory 001-android-arm64-only

Generated from the source tree at change creation. Each row is one file:
- delete: removed whole (path rule or test for a removed area)
- edit: remove the listed platform/Link/arm32 references, keep the Android path
- exception: left unchanged on purpose, with the reason

| kind | path | why |
|---|---|---|
| delete | integration_test/desktop_backend_smoke_test.dart | removed area (path rule) |
| delete | integration_test/desktop_ffmpeg_bundle_test.dart | removed area (path rule) |
| delete | integration_test/desktop_playback_deck_test.dart | removed area (path rule) |
| delete | lib/screens/settings/link_desktop_settings_page.dart | removed area (path rule) |
| delete | lib/screens/settings/link_pairing_dialogs.dart | removed area (path rule) |
| delete | lib/screens/settings/link_settings_page.dart | removed area (path rule) |
| delete | lib/services/backend/ffi_backend_transport.dart | removed area (path rule) |
| delete | lib/services/backend/rust_ffi_backend.dart | removed area (path rule) |
| delete | lib/services/desktop_deep_links.dart | removed area (path rule) |
| delete | lib/services/desktop_diagnostics.dart | removed area (path rule) |
| delete | lib/services/desktop_library_watcher.dart | removed area (path rule) |
| delete | lib/services/desktop_updater.dart | removed area (path rule) |
| delete | lib/services/ffmpeg_desktop.dart | removed area (path rule) |
| delete | lib/services/link/client/link_client_bonsoir.dart | removed area (path rule) |
| delete | lib/services/link/client/link_client_controller.dart | removed area (path rule) |
| delete | lib/services/link/client/link_client_discovery.dart | removed area (path rule) |
| delete | lib/services/link/client/link_client_http.dart | removed area (path rule) |
| delete | lib/services/link/client/link_client_library.dart | removed area (path rule) |
| delete | lib/services/link/client/link_client_pairing.dart | removed area (path rule) |
| delete | lib/services/link/client/link_client_session.dart | removed area (path rule) |
| delete | lib/services/link/client/link_client_store.dart | removed area (path rule) |
| delete | lib/services/link/desktop/link_arriving_files.dart | removed area (path rule) |
| delete | lib/services/link/desktop/link_catalog_exporter.dart | removed area (path rule) |
| delete | lib/services/link/desktop/link_catalog_index.dart | removed area (path rule) |
| delete | lib/services/link/desktop/link_desktop_backend.dart | removed area (path rule) |
| delete | lib/services/link/desktop/link_desktop_host.dart | removed area (path rule) |
| delete | lib/services/link/desktop/link_desktop_ops.dart | removed area (path rule) |
| delete | lib/services/link/desktop/link_desktop_transfers.dart | removed area (path rule) |
| delete | lib/services/link/desktop/link_downloads.dart | removed area (path rule) |
| delete | lib/services/link/desktop/link_library_executor.dart | removed area (path rule) |
| delete | lib/services/link/desktop/link_library_jobs_host.dart | removed area (path rule) |
| delete | lib/services/link/desktop/link_phone_catalogs.dart | removed area (path rule) |
| delete | lib/services/link/desktop/link_phone_library.dart | removed area (path rule) |
| delete | lib/services/link/desktop/link_phone_playback.dart | removed area (path rule) |
| delete | lib/services/link/desktop/link_phone_sources.dart | removed area (path rule) |
| delete | lib/services/link/desktop/link_player.dart | removed area (path rule) |
| delete | lib/services/link/desktop/link_transfer_songs.dart | removed area (path rule) |
| delete | lib/services/link/desktop/link_web_covers.dart | removed area (path rule) |
| delete | lib/services/link/features/link_desktop_remote.dart | removed area (path rule) |
| delete | lib/services/link/features/link_downloads.dart | removed area (path rule) |
| delete | lib/services/link/features/link_handoff.dart | removed area (path rule) |
| delete | lib/services/link/features/link_ios_now_playing.dart | removed area (path rule) |
| delete | lib/services/link/features/link_library_jobs_client.dart | removed area (path rule) |
| delete | lib/services/link/features/link_library_lookup.dart | removed area (path rule) |
| delete | lib/services/link/features/link_library_reconcile.dart | removed area (path rule) |
| delete | lib/services/link/features/link_phone_client.dart | removed area (path rule) |
| delete | lib/services/link/features/link_phone_features.dart | removed area (path rule) |
| delete | lib/services/link/features/link_phone_files.dart | removed area (path rule) |
| delete | lib/services/link/features/link_phone_library.dart | removed area (path rule) |
| delete | lib/services/link/features/link_phone_library_sync.dart | removed area (path rule) |
| delete | lib/services/link/features/link_phone_options.dart | removed area (path rule) |
| delete | lib/services/link/features/link_phone_player.dart | removed area (path rule) |
| delete | lib/services/link/features/link_phone_receiver.dart | removed area (path rule) |
| delete | lib/services/link/features/link_phone_sender.dart | removed area (path rule) |
| delete | lib/services/link/features/link_phone_session.dart | removed area (path rule) |
| delete | lib/services/link/features/link_playback_preferences.dart | removed area (path rule) |
| delete | lib/services/link/features/link_remote_playback.dart | removed area (path rule) |
| delete | lib/services/link/features/link_save_offline.dart | removed area (path rule) |
| delete | lib/services/link/features/link_track_refs.dart | removed area (path rule) |
| delete | lib/services/link/features/link_track_resolver.dart | removed area (path rule) |
| delete | lib/services/link/link_client_api.dart | removed area (path rule) |
| delete | lib/services/link/link_cover_shrink.dart | removed area (path rule) |
| delete | lib/services/link/link_host_router.dart | removed area (path rule) |
| delete | lib/services/link/link_library_jobs.dart | removed area (path rule) |
| delete | lib/services/link/link_lyrics_translations.dart | removed area (path rule) |
| delete | lib/services/link/link_mirrored_playback.dart | removed area (path rule) |
| delete | lib/services/link/link_playback_details.dart | removed area (path rule) |
| delete | lib/services/link/link_protocol.dart | removed area (path rule) |
| delete | lib/services/link/link_source_names.dart | removed area (path rule) |
| delete | lib/services/link/link_transfers.dart | removed area (path rule) |
| delete | lib/services/link/sync/link_collection_sync_schema.dart | removed area (path rule) |
| delete | lib/services/link/sync/link_collection_sync_store.dart | removed area (path rule) |
| delete | lib/services/link/sync/link_history_artwork.dart | removed area (path rule) |
| delete | lib/services/link/sync/link_history_sync_schema.dart | removed area (path rule) |
| delete | lib/services/link/sync/link_history_sync_store.dart | removed area (path rule) |
| delete | lib/services/link/sync/link_sync_handlers.dart | removed area (path rule) |
| delete | lib/services/link/sync/link_sync_protocol.dart | removed area (path rule) |
| delete | lib/services/link/sync/link_sync_runner.dart | removed area (path rule) |
| delete | lib/services/media_session_desktop.dart | removed area (path rule) |
| delete | lib/utils/desktop_folders.dart | removed area (path rule) |
| delete | lib/utils/desktop_platform.dart | removed area (path rule) |
| delete | lib/utils/ios_container_paths.dart | removed area (path rule) |
| delete | lib/utils/windows_path_identity.dart | removed area (path rule) |
| delete | lib/widgets/desktop/context_menu.dart | removed area (path rule) |
| delete | lib/widgets/desktop/desktop_cast_button.dart | removed area (path rule) |
| delete | lib/widgets/desktop/desktop_commands.dart | removed area (path rule) |
| delete | lib/widgets/desktop/desktop_downloads_button.dart | removed area (path rule) |
| delete | lib/widgets/desktop/desktop_inspector.dart | removed area (path rule) |
| delete | lib/widgets/desktop/desktop_link_devices_button.dart | removed area (path rule) |
| delete | lib/widgets/desktop/desktop_link_devices_sheet.dart | removed area (path rule) |
| delete | lib/widgets/desktop/desktop_link_library_jobs_view.dart | removed area (path rule) |
| delete | lib/widgets/desktop/desktop_link_transfer_actions.dart | removed area (path rule) |
| delete | lib/widgets/desktop/desktop_mini_player.dart | removed area (path rule) |
| delete | lib/widgets/desktop/desktop_navigation.dart | removed area (path rule) |
| delete | lib/widgets/desktop/desktop_now_playing.dart | removed area (path rule) |
| delete | lib/widgets/desktop/desktop_player_bar.dart | removed area (path rule) |
| delete | lib/widgets/desktop/desktop_scroll_arrows.dart | removed area (path rule) |
| delete | lib/widgets/desktop/desktop_selection.dart | removed area (path rule) |
| delete | lib/widgets/desktop/desktop_shortcuts.dart | removed area (path rule) |
| delete | lib/widgets/desktop/desktop_volume_scroll.dart | removed area (path rule) |
| delete | lib/widgets/desktop/desktop_window.dart | removed area (path rule) |
| delete | lib/widgets/desktop/desktop_window_controls.dart | removed area (path rule) |
| delete | lib/widgets/desktop/detail_header.dart | removed area (path rule) |
| delete | lib/widgets/desktop/hover_play_button.dart | removed area (path rule) |
| delete | lib/widgets/desktop/library_drop_target.dart | removed area (path rule) |
| delete | lib/widgets/desktop/library_track_menu.dart | removed area (path rule) |
| delete | lib/widgets/desktop/link_text_input_dialog.dart | removed area (path rule) |
| delete | lib/widgets/desktop/track_list_table.dart | removed area (path rule) |
| delete | lib/widgets/desktop/track_table.dart | removed area (path rule) |
| delete | lib/widgets/ios_library_folder_sheet.dart | removed area (path rule) |
| delete | lib/widgets/link/link_actions.dart | removed area (path rule) |
| delete | lib/widgets/link/link_devices_sheet.dart | removed area (path rule) |
| delete | lib/widgets/link/link_library_actions.dart | removed area (path rule) |
| delete | lib/widgets/link/link_transfer_tile.dart | removed area (path rule) |
| delete | lib/widgets/link/link_transfers_view.dart | removed area (path rule) |
| delete | test/artist_desktop_highlights_test.dart | test for removed area (name rule) |
| delete | test/desktop_backend_gates_test.dart | test for removed area (name rule) |
| delete | test/desktop_deep_links_test.dart | test for removed area (name rule) |
| delete | test/desktop_diagnostics_test.dart | test for removed area (name rule) |
| delete | test/desktop_discord_channel_test.dart | test for removed area (name rule) |
| delete | test/desktop_header_artwork_scheme_test.dart | test for removed area (name rule) |
| delete | test/desktop_library_songs_table_test.dart | test for removed area (name rule) |
| delete | test/desktop_library_table_rows_test.dart | test for removed area (name rule) |
| delete | test/desktop_library_watcher_test.dart | test for removed area (name rule) |
| delete | test/desktop_link_devices_button_test.dart | test for removed area (name rule) |
| delete | test/desktop_link_library_jobs_view_test.dart | test for removed area (name rule) |
| delete | test/desktop_link_transfer_actions_test.dart | test for removed area (name rule) |
| delete | test/desktop_list_interaction_test.dart | test for removed area (name rule) |
| delete | test/desktop_list_screens_test.dart | test for removed area (name rule) |
| delete | test/desktop_loading_layout_test.dart | test for removed area (name rule) |
| delete | test/desktop_material_density_test.dart | test for removed area (name rule) |
| delete | test/desktop_menu_bar_rebuild_test.dart | test for removed area (name rule) |
| delete | test/desktop_mini_player_test.dart | test for removed area (name rule) |
| delete | test/desktop_navigation_lifecycle_test.dart | test for removed area (name rule) |
| delete | test/desktop_now_playing_lyrics_test.dart | test for removed area (name rule) |
| delete | test/desktop_pages_test.dart | test for removed area (name rule) |
| delete | test/desktop_platform_test.dart | test for removed area (name rule) |
| delete | test/desktop_scroll_arrows_test.dart | test for removed area (name rule) |
| delete | test/desktop_shell_test.dart | test for removed area (name rule) |
| delete | test/desktop_storage_test.dart | test for removed area (name rule) |
| delete | test/desktop_track_table_cache_test.dart | test for removed area (name rule) |
| delete | test/desktop_track_table_extent_test.dart | test for removed area (name rule) |
| delete | test/desktop_updater_test.dart | test for removed area (name rule) |
| delete | test/desktop_window_mode_test.dart | test for removed area (name rule) |
| delete | test/ffmpeg_desktop_test.dart | test for removed area (name rule) |
| delete | test/file_access_ios_test.dart | test for removed area (name rule) |
| delete | test/ios_container_paths_test.dart | test for removed area (name rule) |
| delete | test/ios_download_folder_test.dart | test for removed area (name rule) |
| delete | test/ios_history_restore_test.dart | test for removed area (name rule) |
| delete | test/ios_library_folder_sheet_test.dart | test for removed area (name rule) |
| delete | test/library_ios_container_migration_test.dart | test for removed area (name rule) |
| delete | test/link_arriving_files_test.dart | test for removed area (name rule) |
| delete | test/link_client_bonsoir_test.dart | test for removed area (name rule) |
| delete | test/link_client_controller_test.dart | test for removed area (name rule) |
| delete | test/link_client_discovery_test.dart | test for removed area (name rule) |
| delete | test/link_client_http_test.dart | test for removed area (name rule) |
| delete | test/link_client_pairing_test.dart | test for removed area (name rule) |
| delete | test/link_client_session_test.dart | test for removed area (name rule) |
| delete | test/link_client_store_test.dart | test for removed area (name rule) |
| delete | test/link_collection_sync_test.dart | test for removed area (name rule) |
| delete | test/link_cover_shrink_test.dart | test for removed area (name rule) |
| delete | test/link_desktop_catalog_test.dart | test for removed area (name rule) |
| delete | test/link_desktop_host_test.dart | test for removed area (name rule) |
| delete | test/link_desktop_index_test.dart | test for removed area (name rule) |
| delete | test/link_desktop_ops_test.dart | test for removed area (name rule) |
| delete | test/link_desktop_phone_test.dart | test for removed area (name rule) |
| delete | test/link_desktop_remote_test.dart | test for removed area (name rule) |
| delete | test/link_desktop_settings_page_test.dart | test for removed area (name rule) |
| delete | test/link_desktop_transfers_host_test.dart | test for removed area (name rule) |
| delete | test/link_desktop_transfers_test.dart | test for removed area (name rule) |
| delete | test/link_devices_sheet_test.dart | test for removed area (name rule) |
| delete | test/link_download_updates_test.dart | test for removed area (name rule) |
| delete | test/link_downloads_test.dart | test for removed area (name rule) |
| delete | test/link_file_lyrics_test.dart | test for removed area (name rule) |
| delete | test/link_handoff_test.dart | test for removed area (name rule) |
| delete | test/link_history_artwork_test.dart | test for removed area (name rule) |
| delete | test/link_history_sync_test.dart | test for removed area (name rule) |
| delete | test/link_ios_now_playing_test.dart | test for removed area (name rule) |
| delete | test/link_library_actions_test.dart | test for removed area (name rule) |
| delete | test/link_library_executor_test.dart | test for removed area (name rule) |
| delete | test/link_library_jobs_client_test.dart | test for removed area (name rule) |
| delete | test/link_library_jobs_host_test.dart | test for removed area (name rule) |
| delete | test/link_library_reconcile_test.dart | test for removed area (name rule) |
| delete | test/link_lyrics_translations_test.dart | test for removed area (name rule) |
| delete | test/link_phone_catalogs_test.dart | test for removed area (name rule) |
| delete | test/link_phone_files_test.dart | test for removed area (name rule) |
| delete | test/link_phone_library_sync_test.dart | test for removed area (name rule) |
| delete | test/link_phone_library_test.dart | test for removed area (name rule) |
| delete | test/link_phone_playback_test.dart | test for removed area (name rule) |
| delete | test/link_phone_receiver_test.dart | test for removed area (name rule) |
| delete | test/link_phone_sender_test.dart | test for removed area (name rule) |
| delete | test/link_phone_session_test.dart | test for removed area (name rule) |
| delete | test/link_phone_song_test.dart | test for removed area (name rule) |
| delete | test/link_phone_sources_test.dart | test for removed area (name rule) |
| delete | test/link_playback_details_test.dart | test for removed area (name rule) |
| delete | test/link_playback_preferences_test.dart | test for removed area (name rule) |
| delete | test/link_player_state_cache_test.dart | test for removed area (name rule) |
| delete | test/link_remote_playback_test.dart | test for removed area (name rule) |
| delete | test/link_save_offline_test.dart | test for removed area (name rule) |
| delete | test/link_seek_slider_test.dart | test for removed area (name rule) |
| delete | test/link_settings_page_test.dart | test for removed area (name rule) |
| delete | test/link_subsonic_download_test.dart | test for removed area (name rule) |
| delete | test/link_sync_handlers_test.dart | test for removed area (name rule) |
| delete | test/link_sync_runner_test.dart | test for removed area (name rule) |
| delete | test/link_track_refs_test.dart | test for removed area (name rule) |
| delete | test/link_transfer_actions_test.dart | test for removed area (name rule) |
| delete | test/link_transfer_songs_test.dart | test for removed area (name rule) |
| delete | test/link_transfers_test.dart | test for removed area (name rule) |
| delete | test/link_transfers_view_test.dart | test for removed area (name rule) |
| delete | test/link_web_covers_test.dart | test for removed area (name rule) |
| delete | test/media_session_desktop_test.dart | test for removed area (name rule) |
| delete | test/network_storage_darwin_test.dart | test for removed area (name rule) |
| delete | test/notification_service_linux_test.dart | test for removed area (name rule) |
| delete | test/platform_bridge_desktop_backend_test.dart | test for removed area (name rule) |
| delete | test/support/link_client_fakes.dart | test for removed area (name rule) |
| delete | test/support/link_desktop_fakes.dart | test for removed area (name rule) |
| delete | test/support/link_fakes.dart | test for removed area (name rule) |
| delete | test/support/link_sync_support.dart | test for removed area (name rule) |
| delete | test/track_metadata_desktop_menu_test.dart | test for removed area (name rule) |
| delete | test/windows_path_identity_test.dart | test for removed area (name rule) |
| delete | test/windows_verbatim_path_keys_test.dart | test for removed area (name rule) |
| edit | integration_test/download_pipeline_performance_test.dart | macOS platform check, desktop-only import |
| edit | integration_test/media_kit_playback_deck_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, macOS platform check, desktop-only import, arm32/universal APK |
| edit | integration_test/mornye_glass_visual_test.dart | Platform.isIOS / TargetPlatform.iOS |
| edit | integration_test/native_backend_followup_test.dart | macOS platform check, Windows platform check, Linux platform check, RustFfiBackend / FfiBackendTransport |
| edit | integration_test/playback_pipeline_performance_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, macOS platform check, desktop-only import |
| edit | integration_test/wasapi_exclusive_playback_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, Windows platform check, desktop-only import |
| edit | lib/app.dart | isDesktopPlatform, desktop_platform.dart import, macOS platform check, Link import, desktop-only import |
| edit | lib/controllers/batch_track_actions.dart | Link import |
| edit | lib/controllers/extension_auth_launcher.dart | isDesktopPlatform, desktop_platform.dart import, Platform.isIOS / TargetPlatform.iOS, desktop-only import |
| edit | lib/controllers/local_track_batch_actions.dart | Link import |
| edit | lib/controllers/open_audio_controller.dart | Platform.isIOS / TargetPlatform.iOS |
| edit | lib/controllers/selection_mode_mixin.dart | desktop-only import |
| edit | lib/main.dart | isDesktopPlatform, desktop_platform.dart import, Platform.isIOS / TargetPlatform.iOS, Link import, desktop-only import |
| edit | lib/models/theme_settings.dart | isDesktopPlatform, desktop_platform.dart import, macOS platform check, desktop-only import |
| edit | lib/providers/download_history_provider.dart | Platform.isIOS / TargetPlatform.iOS |
| edit | lib/providers/download_queue_provider.dart | desktop_platform.dart import, Platform.isIOS / TargetPlatform.iOS, desktop-only import |
| edit | lib/providers/download_queue_provider_paths.dart | isDesktopPlatform, Platform.isIOS / TargetPlatform.iOS |
| edit | lib/providers/download_queue_provider_reorganize.dart | Windows platform check |
| edit | lib/providers/extension_provider.dart | isDesktopPlatform, desktop_platform.dart import, desktop-only import |
| edit | lib/providers/local_library_provider.dart | Platform.isIOS / TargetPlatform.iOS |
| edit | lib/providers/local_library_provider_scan.dart | Platform.isIOS / TargetPlatform.iOS |
| edit | lib/providers/local_library_provider_sources.dart | Platform.isIOS / TargetPlatform.iOS |
| edit | lib/providers/network_offline_provider.dart | Link import |
| edit | lib/providers/network_upload_provider.dart | Link import |
| edit | lib/providers/runtime_profile_provider.dart | arm32/universal APK |
| edit | lib/providers/settings_provider.dart | Platform.isIOS / TargetPlatform.iOS |
| edit | lib/providers/system_volume_provider.dart | isDesktopPlatform, desktop_platform.dart import, desktop-only import |
| edit | lib/screens/album_screen.dart | isDesktopPlatform, desktop_platform.dart import, Link import, desktop-only import |
| edit | lib/screens/artist_screen.dart | isDesktopPlatform, desktop_platform.dart import, desktop-only import |
| edit | lib/screens/artist_screen_widgets.dart | isDesktopPlatform |
| edit | lib/screens/downloaded_album_screen.dart | isDesktopPlatform, desktop_platform.dart import, Link import, desktop-only import |
| edit | lib/screens/equalizer_screen.dart | desktop_platform.dart import, desktop-only import |
| edit | lib/screens/equalizer_widgets.dart | isDesktopPlatform |
| edit | lib/screens/extension_collection_screens.dart | isDesktopPlatform, desktop_platform.dart import, desktop-only import |
| edit | lib/screens/home_tab.dart | isDesktopPlatform, desktop_platform.dart import, desktop-only import |
| edit | lib/screens/home_tab_intro.dart | isDesktopPlatform |
| edit | lib/screens/home_tab_recent.dart | isDesktopPlatform |
| edit | lib/screens/home_tab_search_results.dart | isDesktopPlatform |
| edit | lib/screens/home_tab_search_wide.dart | isDesktopPlatform |
| edit | lib/screens/library_mix_screen.dart | isDesktopPlatform, desktop_platform.dart import, desktop-only import |
| edit | lib/screens/library_tracks_folder_screen.dart | isDesktopPlatform, desktop_platform.dart import, Link import, desktop-only import |
| edit | lib/screens/local_album_screen.dart | isDesktopPlatform, desktop_platform.dart import, Link import, desktop-only import |
| edit | lib/screens/main_shell.dart | isDesktopPlatform, desktop_platform.dart import, Link import, desktop-only import |
| edit | lib/screens/mornye_library_screen.dart | isDesktopPlatform, desktop_platform.dart import, desktop-only import |
| edit | lib/screens/network_storage_screen.dart | Link import |
| edit | lib/screens/now_playing_screen.dart | Platform.isIOS / TargetPlatform.iOS, Link import, desktop-only import |
| edit | lib/screens/playlist_screen.dart | isDesktopPlatform, desktop_platform.dart import, Link import, desktop-only import |
| edit | lib/screens/queue_tab.dart | isDesktopPlatform, desktop_platform.dart import, desktop-only import |
| edit | lib/screens/queue_tab_download_dialogs.dart | Platform.isIOS / TargetPlatform.iOS |
| edit | lib/screens/queue_tab_filter_widgets.dart | isDesktopPlatform |
| edit | lib/screens/queue_tab_item_widgets.dart | isDesktopPlatform |
| edit | lib/screens/queue_tab_sections.dart | isDesktopPlatform |
| edit | lib/screens/queue_tab_selection.dart | isDesktopPlatform |
| edit | lib/screens/repo_tab.dart | isDesktopPlatform, desktop_platform.dart import, desktop-only import |
| edit | lib/screens/settings/about_page.dart | isDesktopPlatform, desktop_platform.dart import, desktop-only import |
| edit | lib/screens/settings/appearance_settings_page.dart | isDesktopPlatform, desktop_platform.dart import, desktop-only import |
| edit | lib/screens/settings/files_settings_page.dart | isDesktopPlatform, desktop_platform.dart import, Platform.isIOS / TargetPlatform.iOS, desktop-only import |
| edit | lib/screens/settings/keyboard_shortcuts_page.dart | desktop-only import |
| edit | lib/screens/settings/library_settings_page.dart | Platform.isIOS / TargetPlatform.iOS, Link import, desktop-only import |
| edit | lib/screens/settings/playback_settings_page.dart | isDesktopPlatform, desktop_platform.dart import, Platform.isIOS / TargetPlatform.iOS, Linux platform check, desktop-only import |
| edit | lib/screens/settings/settings_tab.dart | isDesktopPlatform, desktop_platform.dart import, Platform.isIOS / TargetPlatform.iOS, Link import, desktop-only import |
| edit | lib/screens/setup_screen.dart | isDesktopPlatform, desktop_platform.dart import, Platform.isIOS / TargetPlatform.iOS, Link import, desktop-only import |
| edit | lib/screens/track_metadata_cards.dart | isDesktopPlatform |
| edit | lib/screens/track_metadata_lyrics.dart | isDesktopPlatform |
| edit | lib/screens/track_metadata_screen.dart | isDesktopPlatform, desktop_platform.dart import, Link import, desktop-only import |
| edit | lib/screens/track_metadata_screen_menu.dart | isDesktopPlatform |
| edit | lib/screens/tutorial_screen.dart | isDesktopPlatform, desktop_platform.dart import, desktop-only import |
| edit | lib/screens/whats_new_screen.dart | isDesktopPlatform, desktop_platform.dart import, Link import, desktop-only import |
| edit | lib/services/backend/backend_channel.dart | isDesktopPlatform, desktop_platform.dart import, RustFfiBackend / FfiBackendTransport, desktop-only import |
| edit | lib/services/backup_service.dart | Platform.isIOS / TargetPlatform.iOS |
| edit | lib/services/cast_output.dart | isDesktopPlatform, desktop_platform.dart import, desktop-only import |
| edit | lib/services/connectivity_monitor.dart | Windows platform check |
| edit | lib/services/cover_download_service.dart | Platform.isIOS / TargetPlatform.iOS |
| edit | lib/services/download_keep_awake.dart | isDesktopPlatform, desktop_platform.dart import, desktop-only import |
| edit | lib/services/extension_storage_service.dart | isDesktopPlatform, desktop_platform.dart import, Linux platform check, desktop-only import |
| edit | lib/services/ffmpeg_support.dart | isDesktopPlatform, desktop_platform.dart import, Windows platform check, desktop-only import |
| edit | lib/services/history_database.dart | Platform.isIOS / TargetPlatform.iOS, Windows platform check, desktop-only import |
| edit | lib/services/history_maintenance.dart | desktop-only import |
| edit | lib/services/library_collections_database.dart | Link import |
| edit | lib/services/library_directory_index.dart | desktop-only import |
| edit | lib/services/library_schema.dart | Platform.isIOS / TargetPlatform.iOS, Windows platform check, desktop-only import |
| edit | lib/services/listening_statistics.dart | Link import |
| edit | lib/services/media_kit_playback_deck.dart | Windows platform check, Linux platform check |
| edit | lib/services/media_session_art_cache.dart | Platform.isIOS / TargetPlatform.iOS, macOS platform check |
| edit | lib/services/media_session_filter.dart | Platform.isIOS / TargetPlatform.iOS, macOS platform check |
| edit | lib/services/music_playback_deck.dart | isDesktopPlatform, desktop_platform.dart import, Platform.isIOS / TargetPlatform.iOS, macOS platform check, desktop-only import |
| edit | lib/services/music_player_cast.dart | Platform.isIOS / TargetPlatform.iOS |
| edit | lib/services/music_player_runtime.dart | isDesktopPlatform, desktop_platform.dart import, Platform.isIOS / TargetPlatform.iOS, macOS platform check, Linux platform check, desktop-only import |
| edit | lib/services/music_player_service.dart | isDesktopPlatform, desktop_platform.dart import, Platform.isIOS / TargetPlatform.iOS, desktop-only import |
| edit | lib/services/music_recognition.dart | Platform.isIOS / TargetPlatform.iOS, macOS platform check, Windows platform check |
| edit | lib/services/network_library_upload.dart | Link import |
| edit | lib/services/network_offline_saver.dart | Link import |
| edit | lib/services/notification_service.dart | isDesktopPlatform, desktop_platform.dart import, Platform.isIOS / TargetPlatform.iOS, macOS platform check, Linux platform check, desktop-only import |
| edit | lib/services/platform_bridge.dart | isDesktopPlatform, desktop_platform.dart import, Platform.isIOS / TargetPlatform.iOS, desktop-only import |
| edit | lib/services/playable_media.dart | desktop-only import |
| edit | lib/services/playback_deck.dart | isDesktopPlatform, desktop_platform.dart import, Windows platform check, Linux platform check, desktop-only import |
| edit | lib/services/share_intent_service.dart | Platform.isIOS / TargetPlatform.iOS |
| edit | lib/services/song_analysis.dart | isDesktopPlatform, desktop_platform.dart import, desktop-only import |
| edit | lib/services/song_feature_analyzer.dart | isDesktopPlatform, desktop_platform.dart import, desktop-only import |
| edit | lib/services/sqlite_helpers.dart | isDesktopPlatform, desktop_platform.dart import, macOS platform check, desktop-only import |
| edit | lib/services/system_volume_service.dart | isDesktopPlatform, desktop_platform.dart import, desktop-only import |
| edit | lib/services/update_checker.dart | isDesktopPlatform, desktop_platform.dart import, Linux platform check, desktop-only import, arm32/universal APK |
| edit | lib/services/user_profile_store.dart | isDesktopPlatform, desktop_platform.dart import, desktop-only import |
| edit | lib/theme/app_theme.dart | isDesktopPlatform, desktop_platform.dart import, Platform.isIOS / TargetPlatform.iOS, macOS platform check, desktop-only import |
| edit | lib/theme/mornye_theme.dart | Platform.isIOS / TargetPlatform.iOS, macOS platform check |
| edit | lib/utils/adaptive_layout.dart | isDesktopPlatform, desktop_platform.dart import, Platform.isIOS / TargetPlatform.iOS, macOS platform check, desktop-only import |
| edit | lib/utils/app_bar_layout.dart | Platform.isIOS / TargetPlatform.iOS, macOS platform check |
| edit | lib/utils/exclusive_output_labels.dart | macOS platform check, Linux platform check |
| edit | lib/utils/file_access.dart | isDesktopPlatform, desktop_platform.dart import, Platform.isIOS / TargetPlatform.iOS, Windows platform check, desktop-only import |
| edit | lib/utils/logger.dart | Platform.isIOS / TargetPlatform.iOS, macOS platform check, Windows platform check, Linux platform check |
| edit | lib/utils/native_platform_name.dart | isDesktopPlatform, desktop_platform.dart import, desktop-only import |
| edit | lib/utils/path_match_keys.dart | desktop-only import |
| edit | lib/utils/settings_search_catalog.dart | isDesktopPlatform, desktop_platform.dart import, desktop-only import |
| edit | lib/widgets/album_detail_header.dart | isDesktopPlatform, desktop_platform.dart import, desktop-only import |
| edit | lib/widgets/animation_utils.dart | isDesktopPlatform, desktop_platform.dart import, desktop-only import |
| edit | lib/widgets/app_alert_dialog.dart | isDesktopPlatform, desktop_platform.dart import, desktop-only import |
| edit | lib/widgets/app_bottom_sheet.dart | isDesktopPlatform, desktop_platform.dart import, desktop-only import |
| edit | lib/widgets/app_refresh_indicator.dart | macOS platform check |
| edit | lib/widgets/audio_info_sheet.dart | Link import |
| edit | lib/widgets/audio_output_button.dart | Platform.isIOS / TargetPlatform.iOS |
| edit | lib/widgets/collection_header_actions.dart | isDesktopPlatform, desktop_platform.dart import, desktop-only import |
| edit | lib/widgets/collection_scaffold.dart | isDesktopPlatform, desktop_platform.dart import, desktop-only import |
| edit | lib/widgets/collection_suggestions_section.dart | isDesktopPlatform, desktop_platform.dart import, desktop-only import |
| edit | lib/widgets/discord_presence_settings.dart | isDesktopPlatform, desktop_platform.dart import, Platform.isIOS / TargetPlatform.iOS, desktop-only import |
| edit | lib/widgets/download_service_picker.dart | isDesktopPlatform, desktop_platform.dart import, desktop-only import |
| edit | lib/widgets/explore_featured_section.dart | desktop-only import |
| edit | lib/widgets/library_directory_view.dart | isDesktopPlatform, desktop_platform.dart import, desktop-only import |
| edit | lib/widgets/library_search_results.dart | isDesktopPlatform, desktop_platform.dart import, desktop-only import |
| edit | lib/widgets/library_selection_playback_actions.dart | isDesktopPlatform, desktop_platform.dart import, Link import, desktop-only import |
| edit | lib/widgets/library_track_selection_bar.dart | isDesktopPlatform, desktop_platform.dart import, desktop-only import |
| edit | lib/widgets/lyrics_editor_sheet.dart | isDesktopPlatform, desktop_platform.dart import, desktop-only import |
| edit | lib/widgets/mini_player.dart | isDesktopPlatform, desktop_platform.dart import, Link import, desktop-only import |
| edit | lib/widgets/mornye_artist_header.dart | isDesktopPlatform, desktop_platform.dart import, desktop-only import |
| edit | lib/widgets/mornye_chrome.dart | isDesktopPlatform, desktop_platform.dart import, desktop-only import |
| edit | lib/widgets/mornye_mix_banner.dart | isDesktopPlatform, desktop_platform.dart import, desktop-only import |
| edit | lib/widgets/mornye_player_queue.dart | isDesktopPlatform, desktop_platform.dart import, desktop-only import |
| edit | lib/widgets/network_offline_actions.dart | Platform.isIOS / TargetPlatform.iOS, Link import |
| edit | lib/widgets/open_audio_button.dart | desktop-only import |
| edit | lib/widgets/playback_source_label.dart | Link import |
| edit | lib/widgets/player_details_sheet.dart | isDesktopPlatform, desktop_platform.dart import, desktop-only import |
| edit | lib/widgets/player_lyrics.dart | isDesktopPlatform, desktop_platform.dart import, desktop-only import |
| edit | lib/widgets/player_lyrics_line_style.dart | isDesktopPlatform |
| edit | lib/widgets/player_playback_controls.dart | Link import |
| edit | lib/widgets/player_volume_control.dart | desktop-only import |
| edit | lib/widgets/preview_button.dart | isDesktopPlatform, desktop_platform.dart import, desktop-only import |
| edit | lib/widgets/selection_action_button.dart | isDesktopPlatform, desktop_platform.dart import, desktop-only import |
| edit | lib/widgets/selection_bottom_bar.dart | isDesktopPlatform, desktop_platform.dart import, desktop-only import |
| edit | lib/widgets/tool_button_group.dart | isDesktopPlatform, desktop_platform.dart import, desktop-only import |
| edit | lib/widgets/track_card.dart | desktop-only import |
| edit | lib/widgets/track_collection_quick_actions.dart | isDesktopPlatform, desktop_platform.dart import, Link import, desktop-only import |
| edit | lib/widgets/update_dialog.dart | desktop-only import |
| edit | test/android_keyboard_lifecycle_test.dart | Windows platform check |
| edit | test/app_dialog_size_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, macOS platform check, desktop-only import |
| edit | test/app_refresh_indicator_test.dart | macOS platform check |
| edit | test/appearance_settings_test.dart | Platform.isIOS / TargetPlatform.iOS |
| edit | test/artist_album_selection_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, macOS platform check, Windows platform check, desktop-only import |
| edit | test/artist_album_shelf_arrows_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, desktop-only import |
| edit | test/artist_discography_sort_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, RustFfiBackend / FfiBackendTransport, desktop-only import |
| edit | test/audio_file_open_service_test.dart | Windows platform check |
| edit | test/audio_output_button_test.dart | Platform.isIOS / TargetPlatform.iOS, Linux platform check |
| edit | test/audio_service_queue_platform_test.dart | Platform.isIOS / TargetPlatform.iOS, macOS platform check, Windows platform check, Linux platform check |
| edit | test/collection_reorder_ui_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, Link import, desktop-only import |
| edit | test/collection_suggestions_widget_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, desktop-only import |
| edit | test/cover_cache_info_repository_test.dart | Windows platform check |
| edit | test/cover_store_test.dart | Windows platform check |
| edit | test/design_system_test.dart | Platform.isIOS / TargetPlatform.iOS |
| edit | test/download_keep_awake_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, RustFfiBackend / FfiBackendTransport, desktop-only import |
| edit | test/download_service_picker_drag_test.dart | Platform.isIOS / TargetPlatform.iOS |
| edit | test/duplicate_review_sheet_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, Windows platform check, Linux platform check, desktop-only import |
| edit | test/exclusive_output_settings_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, macOS platform check, Windows platform check, Linux platform check, desktop-only import |
| edit | test/extension_backup_restore_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, RustFfiBackend / FfiBackendTransport, desktop-only import |
| edit | test/extension_storage_service_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, Linux platform check, desktop-only import |
| edit | test/extension_storage_setting_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, macOS platform check, Linux platform check, desktop-only import |
| edit | test/extension_verification_browser_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, Platform.isIOS / TargetPlatform.iOS, macOS platform check, Windows platform check, Linux platform check, desktop-only import |
| edit | test/ffmpeg_lossless_conversion_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, desktop-only import |
| edit | test/ffmpeg_lossy_conversion_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, desktop-only import |
| edit | test/ffmpeg_metadata_arguments_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, desktop-only import |
| edit | test/file_access_check_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, desktop-only import |
| edit | test/file_stat_boundary_test.dart | Windows platform check |
| edit | test/find_moved_downloads_test.dart | Windows platform check |
| edit | test/folder_path_template_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, RustFfiBackend / FfiBackendTransport, desktop-only import |
| edit | test/folder_template_settings_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, Platform.isIOS / TargetPlatform.iOS, macOS platform check, Windows platform check, Linux platform check, RustFfiBackend / FfiBackendTransport, desktop-only import |
| edit | test/home_continue_listening_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, desktop-only import |
| edit | test/home_search_tabs_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, desktop-only import |
| edit | test/home_search_wide_layout_test.dart | desktop-only import |
| edit | test/keyboard_shortcuts_page_test.dart | macOS platform check, Windows platform check, desktop-only import |
| edit | test/library_directory_view_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, desktop-only import |
| edit | test/library_fast_scroller_test.dart | macOS platform check, Windows platform check, Linux platform check |
| edit | test/library_mix_ui_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, desktop-only import |
| edit | test/library_scan_scheduling_test.dart | Link import |
| edit | test/library_search_results_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, desktop-only import |
| edit | test/library_toolbar_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, Windows platform check, desktop-only import |
| edit | test/liked_local_tracks_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, desktop-only import |
| edit | test/lyrics_editor_sheet_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, desktop-only import |
| edit | test/lyrics_translation_ui_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, desktop-only import |
| edit | test/lyrics_translation_word_sync_ui_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, desktop-only import |
| edit | test/main_shell_rebuild_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, desktop-only import |
| edit | test/material_shared_controls_test.dart | macOS platform check |
| edit | test/material_theme_roles_test.dart | desktop-only import |
| edit | test/media_kit_completion_test.dart | macOS platform check |
| edit | test/media_kit_playback_deck_test.dart | Linux platform check |
| edit | test/media_session_art_cache_test.dart | Platform.isIOS / TargetPlatform.iOS, macOS platform check |
| edit | test/media_session_filter_test.dart | Platform.isIOS / TargetPlatform.iOS, macOS platform check |
| edit | test/mornye_artist_capsule_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, desktop-only import |
| edit | test/mornye_glass_level_test.dart | arm32/universal APK |
| edit | test/mornye_library_actions_test.dart | Platform.isIOS / TargetPlatform.iOS |
| edit | test/music_player_runtime_test.dart | Link import |
| edit | test/native_autoplay_taste_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, RustFfiBackend / FfiBackendTransport, desktop-only import |
| edit | test/native_backend_migration_ffi_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, RustFfiBackend / FfiBackendTransport, desktop-only import |
| edit | test/native_directory_stats_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, Windows platform check, RustFfiBackend / FfiBackendTransport, desktop-only import |
| edit | test/network_library_upload_test.dart | Link import |
| edit | test/network_offline_saver_test.dart | Link import |
| edit | test/network_storage_screen_test.dart | Link import |
| edit | test/now_playing_catalog_rows_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, desktop-only import |
| edit | test/now_playing_lyrics_transition_test.dart | Platform.isIOS / TargetPlatform.iOS |
| edit | test/now_playing_rows_test.dart | desktop-only import |
| edit | test/playback_deck_selection_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, Platform.isIOS / TargetPlatform.iOS, macOS platform check, Windows platform check, Linux platform check, desktop-only import |
| edit | test/playback_equalizer_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, desktop-only import |
| edit | test/player_artwork_theme_test.dart | desktop-only import |
| edit | test/player_details_sheet_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, macOS platform check, desktop-only import |
| edit | test/player_lyrics_empty_state_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, desktop-only import |
| edit | test/player_lyrics_mp3_round_trip_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, desktop-only import |
| edit | test/player_lyrics_scroll_continuity_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, desktop-only import |
| edit | test/player_lyrics_wrapping_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, desktop-only import |
| edit | test/player_presentation_settings_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, desktop-only import |
| edit | test/player_volume_control_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, desktop-only import |
| edit | test/playlist_playback_test.dart | isDesktopPlatform, desktop_platform.dart import, debugDesktopPlatformOverride, desktop-only import |
| edit | test/rust_ffi_backend_test.dart | RustFfiBackend / FfiBackendTransport |
| edit | test/selection_action_grid_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, desktop-only import |
| edit | test/settings_bottom_inset_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, desktop-only import |
| edit | test/settings_shared_helpers_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, desktop-only import |
| edit | test/subsonic_screen_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, Platform.isIOS / TargetPlatform.iOS, macOS platform check, Windows platform check, Linux platform check, desktop-only import |
| edit | test/support/search_results_fixture.dart | desktop_platform.dart import, debugDesktopPlatformOverride, desktop-only import |
| edit | test/track_metadata_sidecar_export_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, RustFfiBackend / FfiBackendTransport, desktop-only import |
| edit | test/update_checker_test.dart | arm32/universal APK |
| edit | test/user_profile_test.dart | desktop_platform.dart import, debugDesktopPlatformOverride, desktop-only import |
| exception | lib/services/discord_presence_service.dart | Discord untouched (FR-007); its desktop branch kept with shortcut comment |

Totals: {'delete': 221, 'edit': 236, 'exception': 1}
