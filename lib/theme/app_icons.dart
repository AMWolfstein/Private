import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:sistrum/theme/app_theme.dart';

/// Cupertino counterparts for the shared Settings and extension UI symbols.
/// Directional chevrons use the glyphs that mirror in right-to-left layouts
/// ([CupertinoIcons.back], not [CupertinoIcons.chevron_back]).
IconData appIconFor(IconData icon) {
  if (icon.fontFamily == CupertinoIcons.iconFont) return icon;
  return switch (icon) {
    Icons.apps ||
    Icons.grid_view ||
    Icons.grid_view_outlined ||
    Icons.grid_view_rounded => CupertinoIcons.square_grid_2x2,
    Icons.palette_outlined ||
    Icons.color_lens_outlined => CupertinoIcons.paintbrush,
    Icons.library_music ||
    Icons.library_music_outlined ||
    Icons.queue_music_outlined => CupertinoIcons.music_note_list,
    Icons.lyrics_outlined => CupertinoIcons.quote_bubble,
    Icons.folder_outlined || Icons.folder_open => CupertinoIcons.folder,
    Icons.create_new_folder_outlined => CupertinoIcons.folder_badge_plus,
    Icons.storage_outlined ||
    Icons.sd_storage_outlined ||
    Icons.usb_rounded => CupertinoIcons.tray,
    Icons.settings_backup_restore || Icons.history => CupertinoIcons.clock,
    Icons.article_outlined => CupertinoIcons.doc_text,
    Icons.favorite_outline || Icons.favorite_border => CupertinoIcons.heart,
    Icons.favorite => CupertinoIcons.heart_fill,
    Icons.arrow_back || Icons.chevron_left => CupertinoIcons.back,
    Icons.close => CupertinoIcons.xmark,
    Icons.play_arrow || Icons.play_arrow_rounded => CupertinoIcons.play_fill,
    Icons.shuffle => CupertinoIcons.shuffle,
    Icons.playlist_add || Icons.queue_music => CupertinoIcons.text_badge_plus,
    Icons.edit_outlined => CupertinoIcons.pencil,
    Icons.date_range ||
    Icons.today ||
    Icons.event_outlined => CupertinoIcons.calendar,
    Icons.check || Icons.check_rounded => CupertinoIcons.checkmark,
    Icons.call_split => CupertinoIcons.arrow_branch,
    Icons.info_outline => CupertinoIcons.info,
    Icons.settings_outlined => CupertinoIcons.gear_alt,
    Icons.tune || Icons.tune_rounded => CupertinoIcons.slider_horizontal_3,
    Icons.people_alt_outlined => CupertinoIcons.person_2,
    Icons.person || Icons.person_outline => CupertinoIcons.person,
    Icons.image_outlined => CupertinoIcons.photo,
    Icons.photo_library_outlined => CupertinoIcons.photo_on_rectangle,
    Icons.graphic_eq || Icons.graphic_eq_outlined => CupertinoIcons.waveform,
    Icons.filter_alt_outlined ||
    Icons.filter_list => CupertinoIcons.line_horizontal_3_decrease,
    Icons.language || Icons.translate => CupertinoIcons.globe,
    Icons.text_fields => CupertinoIcons.textformat,
    Icons.record_voice_over_outlined => CupertinoIcons.mic,
    Icons.music_note || Icons.music_note_outlined => CupertinoIcons.music_note,
    Icons.speed || Icons.speed_outlined => CupertinoIcons.gauge,
    Icons.auto_awesome ||
    Icons.auto_awesome_outlined => CupertinoIcons.wand_stars,
    Icons.sync ||
    Icons.sync_rounded ||
    Icons.autorenew_rounded => CupertinoIcons.arrow_2_circlepath,
    Icons.refresh ||
    Icons.refresh_rounded ||
    Icons.system_update => CupertinoIcons.arrow_clockwise,
    Icons.content_copy_outlined ||
    Icons.copy_outlined ||
    Icons.copy => CupertinoIcons.doc_on_doc,
    Icons.swap_horiz ||
    Icons.compare_arrows ||
    Icons.difference_outlined => CupertinoIcons.arrow_right_arrow_left,
    Icons.cleaning_services_outlined => CupertinoIcons.sparkles,
    Icons.delete_outline || Icons.delete_sweep_outlined => CupertinoIcons.trash,
    Icons.open_in_new => CupertinoIcons.arrow_up_right_square,
    Icons.play_circle_outline => CupertinoIcons.play_circle,
    Icons.share || Icons.ios_share => CupertinoIcons.share,
    Icons.contrast => CupertinoIcons.circle_lefthalf_fill,
    Icons.animation => CupertinoIcons.play_rectangle,
    Icons.blur_on => CupertinoIcons.drop,
    Icons.bug_report => CupertinoIcons.ant,
    Icons.timer_outlined => CupertinoIcons.timer,
    Icons.timer_off_outlined => CupertinoIcons.timer,
    Icons.search => CupertinoIcons.search,
    Icons.add => CupertinoIcons.add,
    Icons.album || Icons.album_outlined => CupertinoIcons.square_stack,
    Icons.playlist_play => CupertinoIcons.music_note_list,
    Icons.podcasts => CupertinoIcons.mic,
    Icons.warning_amber_rounded ||
    Icons.warning_amber_outlined => CupertinoIcons.exclamationmark_triangle,
    Icons.error_outline => CupertinoIcons.exclamationmark_circle,
    Icons.check_circle => CupertinoIcons.checkmark_circle,
    Icons.phone_android => CupertinoIcons.device_phone_portrait,
    _ => icon,
  };
}

extension AppIconContext on BuildContext {
  /// [icon] as-is, or its Cupertino counterpart when the Sistrum theme is on.
  IconData adaptiveIcon(IconData icon) =>
      isAppTheme ? appIconFor(icon) : icon;
}
