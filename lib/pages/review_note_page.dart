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

    // 🔒 未ログイン時の表示（アドセンス審査対策の紹介テキスト付き）
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("📚 復習ノート")),
        body: Center(
          child: SingleChildScrollView( // 画面が小さなスマホでもスクロールできるように対策
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              key: const ValueKey('logged_out_view'),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_outline, size: 80, color: Colors.grey),
                  const SizedBox(height: 20),
                  const Text(
                    "復習ノートは会員限定機能です",
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "無限英訳をご利用いただきありがとうございます！\n\n"
                    "Googleアカウントでログインしていただくと、日々のプレイ履歴と連動して「間違えた問題」や「苦手なフレーズ」がこの復習ノートに自動で保存されます。\n\n"
                    "AI（Gemini）がアドバイスしてくれた添削結果を何度も見直して復習を繰り返すことが、英会話力を圧倒的なスピードで向上させる一番の近道です。データはクラウドに安全に保存されるため、いつでもどこからでも学習を再開できます。",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black87, height: 1.6, fontSize: 14),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pushNamed(context, '/login'), // ログイン画面へ移動
                    icon: const Icon(Icons.login),
                    label: const Text("Googleアカウントでログインする", style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                      textStyle: const TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // ⭕ ログイン済みの場合の表示（元のソート処理などを100%維持）
    return Scaffold(
      appBar: AppBar(title: const Text("📚 復習ノート")),
      body: StreamBuilder<QuerySnapshot>(
        stream: _noteService.getNotesStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text("エラーが発生しました"));
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final notes = snapshot.data!.docs;

          // 🌟 アプリ側でお気に入りと日付順に並び替える処理
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

          if (notes.isEmpty) {
            return const Center(child: Text("まだ保存された問題はありません。"));
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
