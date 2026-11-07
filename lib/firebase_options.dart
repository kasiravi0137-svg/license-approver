import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not configured for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAaCPmZPkDM83GuRZ9a7RS8pTsPHcdug-c',
    appId: '1:793430610366:web:b2e27d93daf5245348e9ef',
    messagingSenderId: '793430610366',
    projectId: 'myapp---license',
    authDomain: 'myapp---license.firebaseapp.com',
    storageBucket: 'myapp---license.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDBrfP88_COVY3tjKnJWC7nBaWZM67BnB4',
    appId: '1:793430610366:android:e07dd929ccc3294e48e9ef',
    messagingSenderId: '793430610366',
    projectId: 'myapp---license',
    storageBucket: 'myapp---license.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'REPLACE_ME',
    appId: 'REPLACE_ME',
    messagingSenderId: 'REPLACE_ME',
    projectId: 'REPLACE_ME',
    storageBucket: 'REPLACE_ME',
    iosBundleId: 'com.example.licenseApprover',
  );
}
