import 'package:english_learning_app/services/note_service.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:english_learning_app/services/note_service.dart';

class ReviewNotePage extends StatelessWidget {
  final NoteService _noteService = NoteService();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    // 未ログイン時の表示
    if (user == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text("復習ノートを利用するにはログインが必要です"),
              ElevatedButton(
                onPressed: () => Navigator.pushNamed(context, '/login'), // ログイン画面へ
                child: Text("ログインする"),
              ),
            ],
          ),
        ),
      );
    }

    // ログイン済みの場合
    return Scaffold(
      appBar: AppBar(title: Text("📚 復習ノート")),
      body: StreamBuilder<QuerySnapshot>(
        stream: _noteService.getNotesStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Text("エラーが発生しました");
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          final notes = snapshot.data!.docs;

                    // 🌟 ここから追加：アプリ側でお気に入りと日付順に並び替える
                    notes.sort((a, b) {
                      final aData = a.data() as Map<String, dynamic>;
                      final bData = b.data() as Map<String, dynamic>;
                      
                      // 1. まずピン留め(pinned)されているものを上に配置
                      final aPinned = aData['pinned'] == true ? 1 : 0;
                      final bPinned = bData['pinned'] == true ? 1 : 0;
                      if (aPinned != bPinned) return bPinned.compareTo(aPinned);
                      
                      // 2. ピン留めが同じなら作成日時(createdAt)が新しい順に配置
                      final aTime = aData['createdAt'] as Timestamp?;
                      final bTime = bData['createdAt'] as Timestamp?;
                      if (aTime == null || bTime == null) return 0;
                      return bTime.compareTo(aTime);
                    });
                    // 🌟 ここまで追加

                    if (notes.isEmpty) {
                      return Center(child: Text("まだ保存された問題はありません。"));
                    }

          return ListView.builder(
            itemCount: notes.length,
            itemBuilder: (context, index) {
              final noteId = notes[index].id;
              final data = notes[index].data() as Map<String, dynamic>;

              return Card(
  margin: EdgeInsets.all(8),
  child: ExpansionTile(
    leading: IconButton(
      // 🌟 pinned が無ければ false にする（エラー対策）
      icon: Icon((data['pinned'] ?? false) ? Icons.push_pin : Icons.push_pin_outlined),
      color: (data['pinned'] ?? false) ? Colors.orange : Colors.grey,
      onPressed: () => _noteService.togglePin(noteId, data['pinned'] ?? false),
    ),
    title: Text(data['q'] ?? '問題文なし'),
    // 🌟 source が無ければ「不明」にする（エラー対策）
    subtitle: Text("出典: ${data['source'] ?? '不明'}"),
    children: [
      Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("【正解例】", style: TextStyle(fontWeight: FontWeight.bold)),
            // 🌟 原本の "answer" と "ans" どちらでも動くようにする（エラー対策）
            Text(data['answer'] ?? data['ans'] ?? '解答なし'),
            Divider(),
            Text("【解説】"),
            Text(data['advice'] ?? '解説なし'),
            Text("\n【ポイント】"),
            Text(data['keypoint'] ?? 'ポイントなし'),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: Icon(Icons.delete, color: Colors.red),
                onPressed: () => _noteService.deleteNote(noteId),
              ),
            )
          ],
        ),
      )
    ],
  ),
);
            },
          );
        },
      ),
    );
  }
}