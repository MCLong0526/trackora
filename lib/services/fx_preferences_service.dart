import 'package:cloud_firestore/cloud_firestore.dart';

class FxPreferences {
  final List<String> starred;
  final List<String> hidden;

  const FxPreferences({
    this.starred = const [],
    this.hidden = const [],
  });

  factory FxPreferences.fromMap(Map<String, dynamic> map) => FxPreferences(
        starred: List<String>.from(map['starred'] ?? []),
        hidden: List<String>.from(map['hidden'] ?? []),
      );

  Map<String, dynamic> toMap() => {
        'starred': starred,
        'hidden': hidden,
      };

  FxPreferences copyWith({List<String>? starred, List<String>? hidden}) =>
      FxPreferences(
        starred: starred ?? this.starred,
        hidden: hidden ?? this.hidden,
      );

  bool isStarred(String code) => starred.contains(code);
  bool isHidden(String code) => hidden.contains(code);

  FxPreferences toggleStar(String code) {
    final list = List<String>.from(starred);
    if (list.contains(code)) {
      list.remove(code);
    } else {
      list.add(code);
    }
    return copyWith(starred: list);
  }

  FxPreferences toggleHide(String code) {
    final list = List<String>.from(hidden);
    if (list.contains(code)) {
      list.remove(code);
    } else {
      list.remove(code); // ensure no dup
      list.add(code);
      // If hiding a starred item, also unstar it
      final starList = List<String>.from(starred)..remove(code);
      return copyWith(hidden: list, starred: starList);
    }
    return copyWith(hidden: list);
  }

  FxPreferences unhide(String code) {
    final list = List<String>.from(hidden)..remove(code);
    return copyWith(hidden: list);
  }
}

class FxPreferencesService {
  final FirebaseFirestore _db;
  final String _userId;

  FxPreferencesService(this._db, this._userId);

  DocumentReference<Map<String, dynamic>> get _doc => _db
      .collection('users')
      .doc(_userId)
      .collection('settings')
      .doc('fxPreferences');

  Stream<FxPreferences> stream() => _doc.snapshots().map((snap) {
        if (!snap.exists || snap.data() == null) return const FxPreferences();
        return FxPreferences.fromMap(snap.data()!);
      });

  Future<void> save(FxPreferences prefs) =>
      _doc.set(prefs.toMap(), SetOptions(merge: false));
}
