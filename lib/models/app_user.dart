import '../app_config.dart';

class AppUser {
  final String uid;
  final String? email;

  const AppUser({required this.uid, this.email});

  const AppUser.local() : uid = localUserId, email = localUserEmail;
}
