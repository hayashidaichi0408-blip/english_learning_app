import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Googleサインインのインスタンスをクラス内で保持するように修正
  final _googleSignIn = GoogleSignIn(
  clientId: "398835549126-fqien8td8rpfpv5qub69t8h50mh8c3fk.apps.googleusercontent.com", // index.htmlに貼ったものと同じID
);
  // ログイン状態を監視するストリーム
  Stream<User?> get user => _auth.authStateChanges();

  // メールとパスワードで新規登録
  Future<User?> signUp(String email, String password) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email, 
        password: password
      );
      return result.user;
    } catch (e) {
      print("新規登録エラー: $e");
      return null;
    }
  }

  // ログイン
  Future<User?> signIn(String email, String password) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email, 
        password: password
      );
      return result.user;
    } catch (e) {
      print("ログインエラー: $e");
      return null;
    }
  }

  // ログアウト
  Future<void> signOut() async {
    try {
      // Googleサインインも同時にログアウトさせるのが一般的です
      await _googleSignIn.signOut();
      await _auth.signOut();
    } catch (e) {
      print("ログアウトエラー: $e");
    }
  }

  // Googleログイン（修正版）
  Future<User?> signInWithGoogle() async {
    try {
      // 1. Googleサインインのフローを開始
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null; // キャンセルされた場合

      // 2. 認証詳細を取得
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      // 3. Firebase用のクレデンシャル（証明書）を作成
      // OAuthCredential 型として明示的に受け取ります
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // 4. Firebaseにサインイン
      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      return userCredential.user;
    } catch (e) {
      print("Googleログインエラー: $e");
      return null;
    }
  }
}
