import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NoteService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 1. 問題を保存する
  
  Future<void> saveNote({
  required String question,
  required String answer,
  required String advice,
  required String keypoint,
  required String source,
}) async {
  final user = _auth.currentUser;
  if (user == null) return;

  // --- 追加: すでに保存されているかチェック ---
  final query = await _db
      .collection('users')
      .doc(user.uid)
      .collection('saved_notes')
      .where('q', isEqualTo: question) // 同じ問題文があるか探す
      .get();

  if (query.docs.isNotEmpty) {
    // すでに存在する場合は何もしない
    return;
  }
  // --------------------------------------

  await _db.collection('users').doc(user.uid).collection('saved_notes').add({
    'q': question,
    'ans': answer,
    'advice': advice,
    'keypoint': keypoint,
    'source': source,
    'pinned': false,
    'createdAt': FieldValue.serverTimestamp(),
  });
}

  // 2. ユーザーごとの保存済みリストを取得する
// 2. ユーザーごとの保存済みリストを取得する
  Stream<QuerySnapshot> getNotesStream() {
    final user = _auth.currentUser;
    if (user == null) return const Stream.empty();

    // 🌟 orderBy は使わず、データだけをそのまま安全に取得する
    return _db
        .collection('users')
        .doc(user.uid)
        .collection('saved_notes')
        .snapshots();
  }

  // 3. お気に入り(ピン)の切り替え
  Future<void> togglePin(String noteId, bool currentStatus) async {
    final user = _auth.currentUser;
    await _db
        .collection('users')
        .doc(user!.uid)
        .collection('saved_notes')
        .doc(noteId)
        .update({'pinned': !currentStatus});
  }

  // 4. 削除
  Future<void> deleteNote(String noteId) async {
    final user = _auth.currentUser;
    // 🌟 ログインしていない場合は処理を中断（エラー対策）
    if (user == null) return;

    try {
      await _db
          .collection('users')
          .doc(user.uid)
          .collection('saved_notes')
          .doc(noteId)
          .delete();
      print("削除成功: $noteId");
    } catch (e) {
      print("削除失敗: $e");
    }
  }
}