import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Firebaseプロジェクト`ohana-works-parent`の接続情報。
/// `flutterfire configure`の代わりに、secrets/配下のGoogleService-Info.plist・
/// google-services.jsonの値をそのまま書き出したもの(値自体はクライアント埋め込み前提の
/// 識別子でありシークレットではない。サーバー側の秘密鍵はFCM_SERVICE_ACCOUNT_JSONとして
/// Supabase Edge Function側にのみ保管している)。
class DefaultFirebaseOptions {
  DefaultFirebaseOptions._();

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('保護者アプリはiOS/Androidのみ対応です');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError('未対応のプラットフォームです: $defaultTargetPlatform');
    }
  }

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBhJdtPoWqPJxP581kSHrFddGOp9gB8h8A',
    appId: '1:1097006569701:ios:bd65793de22e2f43789c0c',
    messagingSenderId: '1097006569701',
    projectId: 'ohana-works-parent',
    storageBucket: 'ohana-works-parent.firebasestorage.app',
    iosBundleId: 'com.ohanaworks.parent',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyB4PIsHzdR1oQvcCye5eIdWwoewiI2zVtE',
    appId: '1:1097006569701:android:19d9a668645ed7e6789c0c',
    messagingSenderId: '1097006569701',
    projectId: 'ohana-works-parent',
    storageBucket: 'ohana-works-parent.firebasestorage.app',
  );
}
