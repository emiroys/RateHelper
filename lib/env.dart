import 'package:envied/envied.dart';

part 'env.g.dart';

@Envied(path: '.env', obfuscate: true)
abstract class Env {
  @EnviedField(varName: 'APP_SIGNATURE', obfuscate: true)
  static final String appSignature = _Env.appSignature;

  @EnviedField(varName: 'GIST_URL', obfuscate: true)
  static final String gistUrl = _Env.gistUrl;
}
