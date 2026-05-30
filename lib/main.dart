import 'package:flutter/material.dart';
import 'data.dart'; // DATAマップが入っている想定
import 'package:google_generative_ai/google_generative_ai.dart';
import 'dart:convert'; // JSONのパースに使用
import 'package:firebase_core/firebase_core.dart'; // 追加
import 'firebase_options.dart'; // 自動生成されたファイルをインポート
import 'screens/login_screen.dart'; // インポートを忘れずに
import 'package:firebase_auth/firebase_auth.dart'; // ← これが足りていないためエラーが出ています
import 'screens/login_screen.dart';              // ← ログイン画面のファイルも読み込みが必要です
import 'package:english_learning_app/pages/review_note_page.dart';
import 'package:english_learning_app/services/note_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
 // Flutterの初期化を確実に行うための魔法の1行
 WidgetsFlutterBinding.ensureInitialized();

 // Firebaseの初期化（ここで自動生成されたオプションを使います）
 await Firebase.initializeApp(
   options: DefaultFirebaseOptions.currentPlatform,
 );

 runApp(const MugenEiyakuApp());
}

class MugenEiyakuApp extends StatelessWidget {
 const MugenEiyakuApp({super.key});

 @override
 Widget build(BuildContext context) {
   return MaterialApp(
     title: '無限英訳',
     theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue)),
     home: StreamBuilder<User?>(
       stream: FirebaseAuth.instance.authStateChanges(),
       builder: (context, snapshot) {
         // ログインしていればメイン画面、していなければログイン画面
         if (snapshot.hasData) {
           return const MainScreen();
         }
         return const LoginScreen();
       },
     ),
   );
 }
}

class MainScreen extends StatefulWidget {
 const MainScreen({super.key});

 @override
 State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
 // --- 状態管理（Streamlitのst.session_stateに相当） ---
 int _selectedIndex = 0;
 String? grade;
 String? level;
 String? chapter;
 String? section;
 int qIdx = 0;
 int maxQIdx = 0;
 Map<String, dynamic>? lastRes;
  // クリア状況を保存（例: "優しい_第1章" : true）
 Map<String, bool> cleared = {};

 final TextEditingController _answerController = TextEditingController();
 bool _isLoading = false;
 bool _isSaving = false; // 保存ボタンの連打防止用フラグ

 // 最初に戻る
 void _resetAll() {
   setState(() {
     int _selectedIndex = 0; // ← 75行目あたりに追加
     grade = null;
     level = null;
     chapter = null;
     section = null;
     qIdx = 0;
     maxQIdx = 0;
     lastRes = null;
     _answerController.clear();
   });
 }

 @override
 void dispose() {
   _answerController.dispose();
   super.dispose();
 }

 @override
Widget build(BuildContext context) {
 return Scaffold(
   appBar: AppBar(
     title: const Text('無限英訳サバイバル'),
     backgroundColor: Colors.blue.shade100,
     actions: [
       IconButton(
         icon: const Icon(Icons.home),
         onPressed: _resetAll,
         tooltip: '最初に戻る',
       )
     ],
   ),
   // ↓ ここから Row で囲ってメニューを作る形に変更
   body: Row(
     children: [
       NavigationRail(
         selectedIndex: _selectedIndex,
         onDestinationSelected: (int index) {
           setState(() {
             _selectedIndex = index;
           });
         },
         labelType: NavigationRailLabelType.all,
         destinations: const [
           NavigationRailDestination(icon: Icon(Icons.edit), label: Text('演習')),
           NavigationRailDestination(icon: Icon(Icons.book), label: Text('復習ノート')),
         ],
       ),
       const VerticalDivider(thickness: 1, width: 1),
       Expanded(
         child: SafeArea(
           child: Padding(
             padding: const EdgeInsets.all(16.0),
             // ↓ 選ばれたメニューによって、演習画面か復習ノート画面か出し分ける
             child: _selectedIndex == 0
                 ? _buildCurrentScreen()
                 : ReviewNotePage(), // ← 別ファイルで作った復習ノート画面
           ),
         ),
       ),
     ],
   ),
 );
}

 // 現在のStateに応じて表示するウィジェットを切り替える
 Widget _buildCurrentScreen() {
   if (grade == null) return _buildGradeSelection();
   if (level == null) return _buildLevelSelection();
   if (chapter == null) return _buildChapterSelection();
   if (section == null) return _buildSectionSelection();
   return _buildExerciseScreen();
 }

 // 1. 学年選択
 Widget _buildGradeSelection() {
   return ListView(
     children: [
       const Text('学年選択', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
       const SizedBox(height: 16),
       ...DATA.keys.map((g) => Padding(
             padding: const EdgeInsets.only(bottom: 8.0),
             child: ElevatedButton(
               onPressed: () => setState(() => grade = g),
               child: Text(g),
             ),
           )),
     ],
   );
 }

 // 2. 難易度選択
 Widget _buildLevelSelection() {
   final gradeData = DATA[grade] as Map<String, dynamic>;
   return ListView(
     children: [
       const Text('難易度選択', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
       const SizedBox(height: 16),
       ElevatedButton.icon(
         icon: const Icon(Icons.arrow_back),
         label: const Text('学年選択に戻る'),
         onPressed: () => setState(() => grade = null),
       ),
       const SizedBox(height: 16),
       ...gradeData.keys.map((lv) {
         // Streamlitコードと同様に、レベル内の全章クリア判定などもここで実装可能
         return Padding(
           padding: const EdgeInsets.only(bottom: 8.0),
           child: ElevatedButton(
             onPressed: () => setState(() => level = lv),
             child: Text(lv),
           ),
         );
       }),
     ],
   );
 }

 // 3. 章選択
 Widget _buildChapterSelection() {
   final levelData = DATA[grade]![level] as Map<String, dynamic>;
   return ListView(
     children: [
       const Text('章選択', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
       const SizedBox(height: 16),
       ElevatedButton.icon(
         icon: const Icon(Icons.arrow_back),
         label: const Text('難易度選択に戻る'),
         onPressed: () => setState(() => level = null),
       ),
       const SizedBox(height: 16),
       ...levelData.keys.map((ch) {
         return Padding(
           padding: const EdgeInsets.only(bottom: 8.0),
           child: ElevatedButton(
             onPressed: () => setState(() => chapter = ch),
             child: Text(ch),
           ),
         );
       }),
     ],
   );
 }

 // 4. 節選択
 Widget _buildSectionSelection() {
   final sectionData = DATA[grade]![level]![chapter] as Map<String, dynamic>;
   return ListView(
     children: [
       const Text('節選択', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
       const SizedBox(height: 16),
       ElevatedButton.icon(
         icon: const Icon(Icons.arrow_back),
         label: const Text('章選択に戻る'),
         onPressed: () => setState(() => chapter = null),
       ),
       const SizedBox(height: 16),
       ...sectionData.keys.map((sec) {
         return Padding(
           padding: const EdgeInsets.only(bottom: 8.0),
           child: ElevatedButton(
             onPressed: () {
               setState(() {
                 section = sec;
                 qIdx = 0;
                 maxQIdx = 0;
                 lastRes = null;
                 _answerController.clear();
               });
             },
             child: Text(sec),
           ),
         );
       }),
     ],
   );
 }

 // 5. 問題演習メイン
 Widget _buildExerciseScreen() {
   final questions = DATA[grade]![level]![chapter]![section] as List<String>;
   final currentQ = questions[qIdx];

   return SingleChildScrollView(
     child: Column(
       crossAxisAlignment: CrossAxisAlignment.stretch,
       children: [
         // ナビゲーション
         Row(
           mainAxisAlignment: MainAxisAlignment.spaceBetween,
           children: [
             TextButton.icon(
               icon: const Icon(Icons.arrow_back),
               label: const Text('節選択へ'),
               onPressed: () {
                 setState(() {
                   section = null;
                   lastRes = null;
                 });
               },
             ),
             if (qIdx > 0)
               TextButton.icon(
                 icon: const Icon(Icons.arrow_left),
                 label: const Text('前の問題'),
                 onPressed: () {
                   setState(() {
                     qIdx--;
                     lastRes = null;
                     _answerController.clear();
                   });
                 },
               ),
             if (qIdx < maxQIdx && qIdx + 1 < questions.length)
               TextButton.icon(
                 icon: const Icon(Icons.arrow_right),
                 label: const Text('次の問題'),
                 onPressed: () {
                   setState(() {
                     qIdx++;
                     lastRes = null;
                     _answerController.clear();
                   });
                 },
               ),
           ],
         ),
         const SizedBox(height: 16),
         Text(
           '$section (Q ${qIdx + 1}/${questions.length})',
           style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
         ),
         LinearProgressIndicator(value: (qIdx + 1) / questions.length),
         const SizedBox(height: 24),
        
         // 問題文
         Container(
           padding: const EdgeInsets.all(16),
           decoration: BoxDecoration(
             color: Colors.blue.shade50,
             borderRadius: BorderRadius.circular(8),
           ),
           child: Column(
             crossAxisAlignment: CrossAxisAlignment.start,
             children: [
               const Text('和訳対象:', style: TextStyle(fontWeight: FontWeight.bold)),
               const SizedBox(height: 8),
               Text(currentQ, style: const TextStyle(fontSize: 18)),
             ],
           ),
         ),
         const SizedBox(height: 24),

         // 入力フォーム
         TextField(
           controller: _answerController,
           decoration: const InputDecoration(
             labelText: '英文を入力してください',
             border: OutlineInputBorder(),
           ),
           maxLines: 2,
         ),
         const SizedBox(height: 16),

         // 採点ボタン
         ElevatedButton(
           style: ElevatedButton.styleFrom(
             backgroundColor: Colors.blue,
             foregroundColor: Colors.white,
             padding: const EdgeInsets.symmetric(vertical: 16),
           ),
           // ↓ アロー関数 (=>) をやめて、波括弧 {} に書き換えます
           onPressed: _isLoading ? null : () {


             // 本来の処理を呼ぶ
             _gradeAnswer(currentQ, questions.length);
           },
          
           child: _isLoading
               ? const CircularProgressIndicator(color: Colors.white)
               : const Text('採点・解説', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
         ),
         const SizedBox(height: 24),

         // 結果表示エリア

         if (lastRes != null) _buildResultArea(questions.length, currentQ),
       ],
     ),
   );
 }

 // 採点処理（後でここにAIの通信処理を入れる）
// 採点処理（Gemini APIを使用）
 Future<void> _gradeAnswer(String currentQ, int totalQuestions) async {
   final userInput = _answerController.text.trim();
  

   if (userInput.isEmpty) {
     ScaffoldMessenger.of(context).showSnackBar(
       const SnackBar(content: Text('英文を入力してください。')),
     );
     return;
   }

   setState(() {
     _isLoading = true;
   });

   try {
     // 1. モデルの初期化
     final model = GenerativeModel(
       model: 'gemini-2.5-flash',
       apiKey: const String.fromEnvironment('GEMINI_API_KEY', defaultValue: 'YOUR_API_KEY'),
     );

     // 2. プロンプト（AIへの指示）の作成
     final prompt = """
あなたは「世界一わかりやすい英語の先生」です。
                   専門用語は極力使わず、中学生が直感的に理解できる言葉で教えてください。
                   be動詞や一般動詞などの一般的な用語は使用OKです。
                   無駄な言葉（「すごいね」など）を省き、必要なことをわかりやすく説明してください。
                   英訳の正答例は解説の中に直接書かないでください。
                   keypointでは示されたcurrent_qからのみ考え,生徒の解答は全く考慮せず（生徒が間違えた点を重点的に解説する必要は全くない。current_qでもっとも大事だと思われる文法的知識を二つ解説する）一般的に問題を解くためにもっとも重要だと思われる文法的知識をcurrent_qから読み取り詳しく普遍的に使えるように解説してください。
                   以下の「課題」と「ユーザーの回答」を比較し、厳密に採点してください。
　　　　　　　　　　　　他の問題と混同せず、必ず提示された問題文のみに基づいて回答してください。

                   問題文:$currentQ
                   生徒の回答: $userInput
                   【回答の構成ルール】
                   1. SCORE: 2〜10の点数。
                   2. IMPROVE: 添削結果とルールの解説。難しい言葉には補足を入れてください。
                   3. KEYPOINT: 【2. KEYPOINT（重要知識の抽出）】
★重要：ここでは生徒の回答は一切無視してください。
問題文（$currentQ）と正解（$currentQの標準的な英訳）を分析し、
この問題を解くために必要な「普遍的な文法知識」を2つだけ詳しく解説してください。
（例：不定詞の形容詞的用法、関係代名詞の目的格など）
                   4. VOCAB: 単語の意味。
                   5. ANSWER: 最も自然な正解例。これが生徒の解答とほとんど一致している場合は合格（８点以上）にしてください。ほとんど同じと言っても意味が違ったり文法的に間違っていたら不合格にしてください。


返却形式(JSON):
{
 "score": (2から10の整数),
 "improve": "添削結果とアドバイス（日本語）",
 "keypoint": "文法ポイント",
 "vocab": "単語解説",
 "answer": "正答例"
}
""";

     // 3. API呼び出し
     final response = await model.generateContent([Content.text(prompt)]);
     final text = response.text ?? '{}';

// 4. JSONの解析（不要な記号の除去）
     final cleanJson = text.replaceAll('```json', '').replaceAll('```', '').trim();
     final Map<String, dynamic> result = json.decode(cleanJson);

     setState(() {
       _isLoading = false;
       lastRes = result;
       // 8点以上で合格
       if ((result['score'] as int) >= 8) {
         if (qIdx + 1 > maxQIdx) {
           maxQIdx = qIdx + 1;
         }
       }
     });
   } catch (e) {
     setState(() {
       _isLoading = false;
     });
     // 画面の下にエラー内容を表示する
     ScaffoldMessenger.of(context).showSnackBar(
       SnackBar(
         content: Text('エラー詳細: $e'),
         backgroundColor: Colors.red, // 目立つように赤色にする
         duration: const Duration(seconds: 10), // 長めに表示（確認用）
         action: SnackBarAction(
           label: '閉じる',
           textColor: Colors.white,
           onPressed: () {},
         ),
       ),
     );
     print("🚨 開発用ログ: $e"); // デバッグコンソールにも出す
   }
 }

 // 結果と次の問題へ進むボタンの表示
Widget _buildResultArea(int totalQuestions, String currentQ) {
 final dynamic rawScore = lastRes!['score'];
 final int score = (rawScore is int) ? rawScore : int.tryParse(rawScore.toString()) ?? 0;
 final bool isPassed = score >= 8;

 return Column(
   crossAxisAlignment: CrossAxisAlignment.stretch,
   children: [
     // スコア表示
     Container(
       padding: const EdgeInsets.all(12),
       decoration: BoxDecoration(
         color: isPassed ? Colors.green.shade100 : Colors.red.shade100,
         borderRadius: BorderRadius.circular(8),
       ),
       child: Text(
         'スコア: $score / 10 (${isPassed ? "合格" : "不合格"})',
         textAlign: TextAlign.center,
         style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isPassed ? Colors.green.shade800 : Colors.red.shade800),
       ),
     ),
     const SizedBox(height: 16),

     // --- 徹底防止！保存ボタン ---
     FutureBuilder<QuerySnapshot>(
       future: FirebaseFirestore.instance
           .collection('users')
           .doc(FirebaseAuth.instance.currentUser?.uid)
           .collection('saved_notes')
           .where('q', isEqualTo: currentQ)
           .get(),
       builder: (context, snapshot) {
         bool alreadySaved = snapshot.hasData && snapshot.data!.docs.isNotEmpty;

         // 「既に保存済み」または「今保存処理中」ならボタンを無効化する
         bool isDisabled = alreadySaved || _isSaving;

         return ElevatedButton.icon(
           icon: Icon(isDisabled ? Icons.check : Icons.star_border),
           label: Text(_isSaving ? '保存中...' : (alreadySaved ? '保存済み' : '🌟 復習ノートに保存')),
           style: ElevatedButton.styleFrom(
             backgroundColor: isDisabled ? Colors.grey.shade300 : Colors.orange.shade100,
           ),
           // isDisabled が true なら onPressed を null にして、タップを物理的に封印
           onPressed: isDisabled ? null : () async {
             setState(() => _isSaving = true); // 1. 押した瞬間に「保存中」にして連打を即ブロック

             try {
               await NoteService().saveNote(
                 question: currentQ,
                 answer: lastRes!['answer'].toString(),
                 advice: lastRes!['improve'].toString(),
                 keypoint: lastRes!['keypoint'].toString(),
                 source: "$grade > $chapter > $section",
               );
              
               if (mounted) {
                 ScaffoldMessenger.of(context).showSnackBar(
                   const SnackBar(content: Text('復習ノートに保存しました！')),
                 );
               }
             } catch (e) {
               print("保存エラー: $e");
             } finally {
               // 2. 保存が終わったら「保存中」を解除。
               // すると、上の FutureBuilder が「既に保存済み」と判定してボタンが「保存済み」に切り替わる
               setState(() => _isSaving = false);
             }
           },
         );
       },
     ),

     const SizedBox(height: 16),
     const Text('改善点・添削解説:', style: TextStyle(fontWeight: FontWeight.bold)),
     Text(lastRes!['improve'].toString()),
     const Divider(),
    
     ExpansionTile(
       title: const Text('正答例・重要単語を表示'),
       children: [
         ListTile(
           title: const Text('正答例'),
           subtitle: Text(lastRes!['answer'].toString(), style: const TextStyle(fontWeight: FontWeight.bold))
         ),
         ListTile(
           title: const Text('重要単語'),
           subtitle: Text(
             lastRes!['vocab'] is List
               ? (lastRes!['vocab'] as List).join(', ')
               : (lastRes!['vocab']?.toString() ?? 'なし')
           ),
         ),
       ],
     ),
     const SizedBox(height: 24),

     if (isPassed)
       if (qIdx + 1 < totalQuestions)
         ElevatedButton(
           onPressed: () {
             setState(() {
               qIdx++;
               lastRes = null;
               _answerController.clear();
             });
           },
           child: const Text('合格！次の問題へ進む ➡️'),
         )
       else
         Column(
           crossAxisAlignment: CrossAxisAlignment.stretch,
           children: [
             const Text(
               '🎉 この節のすべての問題をクリアしました！',
               textAlign: TextAlign.center,
               style: TextStyle(fontSize: 16, color: Colors.green, fontWeight: FontWeight.bold),
             ),
             const SizedBox(height: 8),
             ElevatedButton(
               onPressed: () {
                 setState(() {
                   section = null;
                 });
               },
               child: const Text('🎉 章選択に戻る'),
             ),
           ],
         ),
   ],
 );
}
}
