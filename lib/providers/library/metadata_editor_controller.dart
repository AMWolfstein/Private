import 'package:flutter/widgets.dart';
import 'package:sistrum/utils/text/string_utils.dart';

/// Editable tags and request generations, independent of sheet navigation.
class MetadataEditorController {
  static const fieldKeys = <String>[
    'title',
    'artist',
    'album',
    'album_artist',
    'date',
    'track_number',
    'total_tracks',
    'disc_number',
    'total_discs',
    'genre',
    'isrc',
    'lyrics',
    'label',
    'copyright',
    'composer',
    'comment',
    'album_type',
    'explicit',
    'upc',
    'cover',
  ];

  final Map<String, TextEditingController> _fields;
  final Map<String, String> _initial;
  final Set<String> _changed = {};
  final Set<String> autoFillFields = {};
  bool explicit;
  final bool _initialExplicit;
  int _generation = 0;
  bool _disposed = false;

  MetadataEditorController(Map<String, String> initialValues)
    : _fields = {
        for (final key in fieldKeys)
          if (key != 'explicit' && key != 'cover')
            key: TextEditingController(text: initialValues[key] ?? ''),
      },
      _initial = {
        for (final key in fieldKeys)
          if (key != 'explicit' && key != 'cover')
            key: initialValues[key] ?? '',
      },
      explicit = parseExplicitFlag(initialValues['explicit']) == true,
      _initialExplicit = parseExplicitFlag(initialValues['explicit']) == true {
    for (final entry in _fields.entries) {
      final field = entry.value;
      var previousText = field.text;
      field.addListener(() {
        if (field.text == previousText) return;
        previousText = field.text;
        if (field.text == _initial[entry.key]) {
          _changed.remove(entry.key);
        } else {
          _changed.add(entry.key);
        }
        invalidateLookup();
      });
    }
  }

  TextEditingController? operator [](String key) => _fields[key];

  Map<String, String> get values => {
    for (final entry in _fields.entries) entry.key: entry.value.text,
    'explicit': explicit ? '1' : '0',
  };

  void invalidateLookup() => _generation++;
  bool isCurrent(int generation) => !_disposed && generation == _generation;

  int apply(Map<String, String> values) {
    var filled = 0;
    for (final key in autoFillFields) {
      final value = values[key];
      if (value == null) continue;
      if (key == 'explicit') {
        final parsed = parseExplicitFlag(value);
        if (parsed == null) continue;
        explicit = parsed;
      } else {
        final field = _fields[key];
        if (field == null) continue;
        field.text = value;
      }
      filled++;
    }
    return filled;
  }

  /// Tags to write, with each name field exactly as it was typed.
  Map<String, String> buildMetadataTags({bool onlyChanged = false}) {
    final tags = values;
    tags['track_total'] = tags.remove('total_tracks')!;
    tags['disc_total'] = tags.remove('total_discs')!;
    tags['compilation'] =
        tags['album_type']!.trim().toLowerCase() == 'compilation' ? '1' : '0';
    if (!onlyChanged) return tags;
    final changedKeys = {..._changed};
    for (final (numberKey, totalKey) in [
      ('track_number', 'total_tracks'),
      ('disc_number', 'total_discs'),
    ]) {
      if (changedKeys.contains(totalKey) &&
          !changedKeys.contains(numberKey) &&
          (_initial[numberKey] ?? '').isNotEmpty) {
        // FFmpeg only understands "number/total"; include the current number
        // when the total changes so the edit cannot drop it.
        changedKeys.add(numberKey);
      }
      if (changedKeys.contains(numberKey) && !changedKeys.contains(totalKey)) {
        changedKeys.add(totalKey);
      }
    }
    final changed = <String, String>{};
    for (final key in changedKeys) {
      final target = switch (key) {
        'total_tracks' => 'track_total',
        'total_discs' => 'disc_total',
        _ => key,
      };
      final value = tags[target];
      if (value != null) changed[target] = value;
    }
    if (_changed.contains('album_type')) {
      changed['compilation'] = tags['compilation']!;
    }
    if (explicit != _initialExplicit) changed['explicit'] = tags['explicit']!;
    return changed;
  }

  void dispose() {
    _disposed = true;
    for (final field in _fields.values) {
      field.dispose();
    }
  }
}
