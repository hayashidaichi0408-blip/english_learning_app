import 'package:flutter/material.dart';

import 'data.dart'; // DATAマップが入っている想定
import 'package:google_generative_ai/google_generative_ai.dart';
import 'dart:convert'; // JSONのパースに使用
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart'; // 自動生成されたファイルをインポート
import 'screens/login_screen.dart'; // インポート
import 'package:firebase_auth/firebase_auth.dart';
import 'package:english_learning_app/pages/review_note_page.dart';
import 'package:english_learning_app/services/note_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  // Flutterの初期化を確実に行う
  WidgetsFlutterBinding.ensureInitialized();

  // Firebaseの初期化
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
      title: '無限英訳サバイバル',
      debugShowCheckedModeBanner: false,
      // 楽しげなオレンジベースのテーマ
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  // --- 状態管理 ---
  int _selectedIndex = 0;
  String? grade;
  String? level;
  String? chapter;
  String? section;
  int qIdx = 0;
  int maxQIdx = 0;
  Map<String, dynamic>? lastRes;
  Map<String, bool> cleared = {};

  final TextEditingController _answerController = TextEditingController();
  bool _isLoading = false;
  bool _isSaving = false; // 保存ボタンの連打防止用フラグ

  // 最初に戻る
  void _resetAll() {
    setState(() {
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
        title: const Text('無限英訳サバイバル', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.orange.shade200,
        actions: [
          // StreamBuilderを使ってログイン状態をリアルタイム監視してボタン切り替え
          StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.active) {
                final user = snapshot.data;
                
                if (user == null) {
                  // 未ログインの場合：ログインボタンを表示
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: TextButton.icon(
                      icon: const Icon(Icons.login, color: Colors.black),
                      label: const Text('ログインする', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const LoginScreen()),
                        );
                      },
                    ),
                  );
                } else {
                  // ログイン済みの場合：ログアウトボタンを表示
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: TextButton.icon(
                      icon: const Icon(Icons.logout, color: Colors.red),
                      label: const Text('ログアウト', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                      onPressed: () async {
                        await FirebaseAuth.instance.signOut();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('ログアウトしました')),
                          );
                        }
                      },
                    ),
                  );
                }
              }
              return const SizedBox.shrink();
            },
          ),
          IconButton(
            icon: const Icon(Icons.home, color: Colors.black),
            onPressed: _resetAll,
            tooltip: '最初に戻る',
          )
        ],
      ),
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
            unselectedLabelTextStyle: const TextStyle(color: Colors.black, fontSize: 11),
            selectedLabelTextStyle: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11),
            destinations: const [
              NavigationRailDestination(icon: Icon(Icons.edit, color: Colors.black), label: Text('演習')),
              NavigationRailDestination(icon: Icon(Icons.book, color: Colors.black), label: Text('復習ノート')),
              NavigationRailDestination(icon: Icon(Icons.info_outline, color: Colors.black), label: Text('アプリについて')),
              NavigationRailDestination(icon: Icon(Icons.gavel, color: Colors.black), label: Text('規約・ポリシー')),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: _buildMenuContent(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // メニューごとの画面出し分け
  Widget _buildMenuContent() {
    switch (_selectedIndex) {
      case 0:
        return _buildCurrentScreen();
      case 1:
        return ReviewNotePage();
      case 2:
        return _buildAboutAppPage();
      case 3:
        return _buildPolicyPage();
      default:
        return _buildCurrentScreen();
    }
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
        const Text('学年選択', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black)),
        const SizedBox(height: 16),
        ...DATA.keys.map((g) => Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade50,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => setState(() => grade = g),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.school_outlined, color: Colors.black),
                    const SizedBox(width: 8),
                    Text(g, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  ],
                ),
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
        const Text('難易度選択', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black)),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          label: const Text('学年選択に戻る', style: TextStyle(color: Colors.black)),
          onPressed: () => setState(() => grade = null),
        ),
        const SizedBox(height: 16),
        ...gradeData.keys.map((lv) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade50,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => setState(() => level = lv),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star_border_purple500, color: Colors.black),
                  const SizedBox(width: 8),
                  Text(lv, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ],
              ),
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
        const Text('章選択', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black)),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          label: const Text('難易度選択に戻る', style: TextStyle(color: Colors.black)),
          onPressed: () => setState(() => level = null),
        ),
        const SizedBox(height: 16),
        ...levelData.keys.map((ch) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade50,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => setState(() => chapter = ch),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.auto_stories_outlined, color: Colors.black),
                  const SizedBox(width: 8),
                  Text(ch, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ],
              ),
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
        const Text('節選択', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black)),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          label: const Text('章選択に戻る', style: TextStyle(color: Colors.black)),
          onPressed: () => setState(() => chapter = null),
        ),
        const SizedBox(height: 16),
        ...sectionData.keys.map((sec) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple.shade50,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                setState(() {
                  section = sec;
                  qIdx = 0;
                  maxQIdx = 0;
                  lastRes = null;
                  _answerController.clear();
                });
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.flag_outlined, color: Colors.black),
                  const SizedBox(width: 8),
                  Text(sec, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ],
              ),
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
                icon: const Icon(Icons.arrow_back, color: Colors.black),
                label: const Text('節選択へ', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                onPressed: () {
                  setState(() {
                    section = null;
                    lastRes = null;
                  });
                },
              ),
              if (qIdx > 0)
                TextButton.icon(
                  icon: const Icon(Icons.arrow_left, color: Colors.black),
                  label: const Text('前の問題', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
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
                  icon: const Icon(Icons.arrow_right, color: Colors.black),
                  label: const Text('次の問題', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
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
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: (qIdx + 1) / questions.length),
          const SizedBox(height: 24),
          
          // 問題文
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('和訳対象:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                const SizedBox(height: 8),
                Text(currentQ, style: const TextStyle(fontSize: 18, color: Colors.black, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 入力フォーム
          TextField(
            controller: _answerController,
            style: const TextStyle(color: Colors.black),
            decoration: const InputDecoration(
              labelText: '英文を入力してください',
              labelStyle: TextStyle(color: Colors.black),
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 16),

          // 採点ボタン
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Colors.orange.shade300,
            ),
            onPressed: _isLoading ? null : () {
              _gradeAnswer(currentQ, questions.length);
            },
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                  )
                : const Text('採点・解説', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
          ),
          const SizedBox(height: 24),

          // 結果表示エリア
          if (lastRes != null) _buildResultArea(questions.length, currentQ),
        ],
      ),
    );
  }

  // 採点処理（最新の Gemini 2.5 Flash モデルを使用）
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
      // 1. モデルの初期化 (最新の gemini-2.5-flash に更新)
      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: const String.fromEnvironment('GEMINI_API_KEY', defaultValue: 'YOUR_API_KEY'),
      );

      // 2. プロンプト（AIへの指示）
      final prompt = """
あなたは「世界一不親切な英語の先生」です。
ストーリーブックの主人公のような、ユーモアがあって励ましてくれるような口調で回答してください。
たとえ生徒の回答が間違っていたとしても、励まし、分かりやすく楽しい方法で解説してください。
専門用語はできるだけ使わないでください。

以下の「問題」と「ユーザーの回答」をもとに、厳格に採点を行ってください。
現在の問題に基づいてのみ回答してください。

問題: $currentQ
生徒の回答: $userInput

【回答構成ルール】
1. SCORE: 2〜10点の間で採点。
2. IMPROVE: 修正結果とアドバイス。楽しくて励まされるような書き方にしてください。
3. KEYPOINT: 文法のポイント。この問題で使われている、最も一般的で重要な2つの文法ポイントを見つけ、ユーモアを交え、生活に即した例を挙げて解説してください。
4. VOCAB: 単語の解説。
5. ANSWER: 最も自然な正解例。

フォーマット(JSONのみを返却してください):
{
  "score": (整数),
  "improve": "アドバイス",
  "keypoint": "文法ポイント",
  "vocab": "単語解説",
  "answer": "正答例"
}
""";

      // 3. API呼び出し
      final response = await model.generateContent([Content.text(prompt)]);
      final text = response.text ?? '{}';

      // 4. JSON抽出の強化（マークダウン等が含まれる場合も確実に抽出）
      final RegExp jsonRegExp = RegExp(r'\{[\s\S]*\}');
      final match = jsonRegExp.firstMatch(text);
      final cleanJson = match != null ? match.group(0)! : text;

      final Map<String, dynamic> result = json.decode(cleanJson);

      setState(() {
        _isLoading = false;
        lastRes = result;
        // 8点以上で合格判定
        final rawScore = result['score'];
        final scoreVal = (rawScore is int) ? rawScore : int.tryParse(rawScore.toString()) ?? 0;
        if (scoreVal >= 8) {
          if (qIdx + 1 > maxQIdx) {
            maxQIdx = qIdx + 1;
          }
        }
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('エラー詳細: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 10),
          action: SnackBarAction(
            label: '閉じる',
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
      print("🚨 開発用ログ: $e");
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
            color: isPassed ? Colors.green.shade50 : Colors.red.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isPassed ? Icons.sentiment_very_satisfied : Icons.sentiment_neutral,
                color: isPassed ? Colors.green : Colors.red,
                size: 28,
              ),
              const SizedBox(width: 8),
              Text(
                'スコア: $score / 10 (${isPassed ? "合格！" : "まだまだこれから！"})',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18, 
                  fontWeight: FontWeight.bold, 
                  color: Colors.black,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // --- 保存ボタン ---
        if (FirebaseAuth.instance.currentUser == null)
          ElevatedButton.icon(
            icon: const Icon(Icons.lock_outline, color: Colors.black),
            label: const Text('ログインして復習ノートに保存', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
              );
            },
          )
        else
          FutureBuilder<QuerySnapshot>(
            future: FirebaseFirestore.instance
                .collection('users')
                .doc(FirebaseAuth.instance.currentUser?.uid)
                .collection('saved_notes')
                .where('q', isEqualTo: currentQ)
                .get(),
            builder: (context, snapshot) {
              bool alreadySaved = snapshot.hasData && snapshot.data!.docs.isNotEmpty;
              bool isDisabled = alreadySaved || _isSaving;

              return ElevatedButton.icon(
                icon: Icon(isDisabled ? Icons.check : Icons.star_border, color: Colors.black),
                label: Text(
                  _isSaving ? '保存中...' : (alreadySaved ? '保存済み' : '🌟 復習ノートに保存'),
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDisabled ? Colors.grey.shade300 : Colors.amber.shade200,
                  foregroundColor: Colors.black,
                ),
                onPressed: isDisabled ? null : () async {
                  setState(() => _isSaving = true); // 連打を即ブロック

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
                    if (mounted) {
                      setState(() => _isSaving = false);
                    }
                  }
                },
              );
            },
          ),

        const SizedBox(height: 16),
        const Text('改善点・添削解説:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
        Text(lastRes!['improve'].toString(), style: const TextStyle(color: Colors.black)),
        const Divider(),
        
        ExpansionTile(
          title: const Text('正答例・重要単語を表示', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          children: [
            ListTile(
              title: const Text('正答例', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              subtitle: Text(lastRes!['answer'].toString(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
            ),
            ListTile(
              title: const Text('重要単語', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              subtitle: Text(
                lastRes!['vocab'] is List
                    ? (lastRes!['vocab'] as List).join(', ')
                    : (lastRes!['vocab']?.toString() ?? 'なし'),
                style: const TextStyle(color: Colors.black),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        if (isPassed)
          if (qIdx + 1 < totalQuestions)
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade200),
              onPressed: () {
                setState(() {
                  qIdx++;
                  lastRes = null;
                  _answerController.clear();
                });
              },
              child: const Text('合格！次の問題へ進む ➡️', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
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
                  child: const Text('🎉 章選択に戻る', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
      ],
    );
  }

  // アプリについての解説ページ
  Widget _buildAboutAppPage() {
    return const SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('無限英訳サバイバルとは？', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black)),
          SizedBox(height: 16),
          Text(
            '当アプリ「無限英訳サバイバル」は、最先端の生成AI（Gemini API）を活用した、全く新しい英語学習支援型Webアプリケーションです。従来の選択式クイズや固定されたフレーズの丸暗記とは異なり、ユーザーが自由に入力した英文をリアルタイムで解析・採点し、英語学習における「能動的なアウトプット能力（発信力）」を飛躍的に高めることを目的として開発されました。\n\n'
            '英語の習得において、リーディング（読む）やリスニング（聞く）といったインプット学習に比べて、ライティング（書く）やスピーキング（話す）といったアウトプット学習は圧倒的に実践の場が不足しがちです。また、独学で英文を作成しても「自分の書いた英語が本当に自然なのか」「どこをどう直せばより良くなるのか」を瞬時にフィードバックしてくれる環境はこれまで身近にありませんでした。当アプリはその課題を解決します。',
            style: TextStyle(fontSize: 14, color: Colors.black87, height: 1.6),
          ),
          SizedBox(height: 20),
          Text('本アプリの特徴と学習効果', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)),
          SizedBox(height: 8),
          Text(
            '1. AIによるリアルタイム個別添削指導\n'
            'ユーザーが入力した英文は即座に評価され、10点満点でのスコアリングとともに詳細なアドバイス（改善点）が提示されます。単なる正誤判定ではなく、「ストーリーブックの主人公のような、ユーモアに溢れ励ましてくれる解説」によって、学習のモチベーションを維持しながら楽しく継続できます。\n\n'
            '2. 文法と重要語彙の深掘り解説\n'
            '採点結果と同時に、その課題において最も重要かつ汎用性の高い「2つの主要な英文法ポイント」を日常的な分かりやすい例を挙げて個別解説します。さらに、問題に含まれる重要単語や熟語（VOCAB）の一覧も抽出されるため、1つの問題から得られる知識量が最大化されます。\n\n'
            '3. 確実な定着を狙う復習ノート機能\n'
            '苦手な問題や、AIから指摘された有益な解説は、Firebase Cloud Firestoreと連携した「復習ノート」にワンタップで永久保存可能。ユーザーがいつでも自分の弱点をピンポイントで見直し、反復練習を行うことができる効率的な学習サイクルを提供しています。',
            style: TextStyle(fontSize: 14, color: Colors.black87, height: 1.6),
          ),
          SizedBox(height: 20),
          Text('開発背景と教育的な教育価値', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)),
          SizedBox(height: 8),
          Text(
            '現代の英語教育においては、ただ知識を詰め込むだけでなく、「自分の言葉で相手に伝える力」が重視されています。「無限英訳サバイバル」は、学習者が間違えることを恐れずに何度でもトライ＆エラーを繰り返せる「サバイバル環境」を提供し、自立的な言語学習を後押しします。中学生から高校生、そして大人のやり直し英語まで、幅広い学年・難易度データに対応しており、一人ひとりの習得度に寄り添う持続可能な教育系デジタルコンテンツです。',
            style: TextStyle(fontSize: 14, color: Colors.black87, height: 1.6),
          ),
        ],
      ),
    );
  }

  // プライバシーポリシー＆免責事項ページ
  Widget _buildPolicyPage() {
    return const SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('プライバシーポリシー及び利用規約', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black)),
          SizedBox(height: 16),
          Text(
            'プライバシーポリシー\n\n'
            '1. 個人情報の収集と利用について\n'
            '当アプリケーション（以下、「当アプリ」）では、ユーザーの学習履歴（復習ノート機能など）の保存および認証管理を行うため、Googleが提供するFirebase（Firebase Authentication、Cloud Firestore）を利用しています。これに伴い、匿名のユーザー識別子や、登録されたメールアドレス、保存された学習用テキストデータがセキュアに収集・蓄積されます。これらの情報は、ユーザーにパーソナライズされた学習環境を提供する目的以外には一切使用いたしません。\n\n'
            '2. APIの利用とデータの送信について\n'
            '当アプリでは、入力された英文の採点および解説の生成を行うため、Google CloudのGenerative Language API（Gemini API）にデータを送信しています。送信されるデータはユーザーが入力した解答テキストのみであり、氏名やパスワード等の個人情報が送信されることはありません。\n\n'
            '3. 広告の配信について（Google AdSense）\n'
            '当アプリでは、第三者配信の広告サービス「Google AdSense」を利用する場合があります。広告配信事業者は、ユーザーの興味に応じた適切な商品やサービスの広告を表示するため、当サイトや他サイトへのアクセスに関する情報「Cookie」（氏名、住所、メールアドレス、電話番号は含まれません）を使用することがあります。ユーザーはブラウザの設定によりCookieを無効にすることが可能です。',
            style: TextStyle(fontSize: 13, color: Colors.black87, height: 1.6),
          ),
          Divider(height: 32),
          Text(
            '利用規約・免責事項\n\n'
            '1. サービスの提供について\n'
            '当アプリが提供する採点結果、解説、およびアドバイスは、生成AIの技術を用いて自動生成されたものです。AIモデルの性質上、出力結果の正確性、完全性、妥当性、または特定の学習目的への適合性について、明示的にも黙示的にもいかなる保証も行うものではありません。\n\n'
            '2. 免責事項\n'
            'ユーザーが当アプリを利用したこと、または利用できなかったことにより生じた、いかなる直接的・間接的な損害、学習上の不利益、システムトラブル等に対しても、開発者は一切の責任を負いません。外部APIサービス（Firebase、Gemini API等）の仕様変更や停止に伴うサービスの休止についても同様とします。\n\n'
            '3. 著作権について\n'
            '当アプリに掲載されている学習データ、独自テキスト、デザイン、その他のコンテンツの著作権は開発者に帰属します。無断での複製、転載、配布を固く禁じます。',
            style: TextStyle(fontSize: 13, color: Colors.black87, height: 1.6),
          ),
        ],
      ),
    );
  }
}
