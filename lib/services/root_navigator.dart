import 'package:flutter/material.dart';

/// アプリ全体の Navigator を参照するための共有キー。
/// SessionBanner は MaterialApp.builder で Navigator の外側に置かれるため、
/// バナーからダイアログ等を開く際は banner 自身の context ではなく
/// このキーの currentContext(=Navigator配下)を使う(黒帯の施設切替ダイアログで使用)。
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
