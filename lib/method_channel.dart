import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:polygonid_flutter_sdk/circuits/data/circuit_model.dart';
import 'package:polygonid_flutter_sdk/circuits/data/circuits_to_download_param.dart';
import 'package:polygonid_flutter_sdk/common/domain/entities/env_entity.dart';
import 'package:wira_flutter_module/zk_gen.dart';

const MethodChannel _channel = MethodChannel('wira_logic');
ZkGenerator _zkGenerator = ZkGenerator();

void initializeWiraLogic() {
  _channel.setMethodCallHandler(_handleCall);
}

String encodeResponse(Map<String, dynamic> response) {
  return jsonEncode(response);
}

Future<dynamic> _handleCall(MethodCall call) async {
  switch (call.method) {
    case 'initialize':
      try {
        final String stringEnv = call.arguments['env'] ?? '';

        EnvEntity? env;
        if (stringEnv != '') {
          env = EnvEntity.fromJson(jsonDecode(stringEnv));
        }

        await _zkGenerator.initialize(env);
        return encodeResponse({'success': true});
      } catch (e) {
        return encodeResponse({'success': false, 'error': e.toString(), 'arguments': jsonEncode(call.arguments)});
      }
    case 'downloadCircuits':
      final String stringCircuits = call.arguments['circuitsToDownload'] ?? '';

      try {
        CircuitsToDownloadParam? circuits;
        if (stringCircuits != '') {
          Map<String, dynamic> map = jsonDecode(stringCircuits);
          map['circuitsWithChecksum'] = (map['circuitsWithChecksum'] as List).map((e) => CircuitModel.fromJson(e)).toList();
          circuits = CircuitsToDownloadParam.fromJson(map);
        }

        final stream = await _zkGenerator.downloadCircuits(circuits);
        _zkGenerator.handleDownloadInfo(stream, (status, info) {
          _channel.invokeMethod('downloadInfo', jsonEncode({'status': status, 'info': info}));
        });
        return encodeResponse({'success': true});
      } catch (e) {
        return encodeResponse({'success': false, 'error': e.toString()});
      }
    case 'addIdentity':
      try {
        String identity = await _zkGenerator.addIdentity();
        return encodeResponse({'success': true, 'identity': identity});
      } catch (e) {
        return encodeResponse({'success': false, 'error': e.toString()});
      }
    case 'authenticate':
      final args = call.arguments;
      final String message = args['message'] ?? '';
      final String userDid = args['userDid'] ?? '';
      final String userPk = args['userPk'] ?? '';
      final List<String>? requestedCredentialIds = args['requestedCredentialIds']?.cast<String>();

      if (message == '' || userDid == '' || userPk == '') {
        return encodeResponse({'success': false, 'error': 'Missing arguments'});
      }

      try {
        await _zkGenerator.authenticate(message, userDid, userPk, requestedCredentialIds);
        return encodeResponse({'success': true});
      } catch (e, stackTrace) {
        return encodeResponse({'success': false, 'error': e.toString(), 'stackTrace': stackTrace.toString()});
      }
    case 'getProof':
      final args = call.arguments;
      final String message = args['message'] ?? '';
      final String userDid = args['userDid'] ?? '';
      final String userPk = args['userPk'] ?? '';
      final String challenge = args['challenge'] ?? '';
      final String byField = args['byField'] ?? '';
      final String byValue = args['byValue'] ?? '';
      if (message == '' || userDid == '' || userPk == '' || challenge == '' || byField == '' || byValue == '') {
        return encodeResponse({'success': false, 'error': 'Missing arguments'});
      }

      try {
        var proof = await _zkGenerator.getProof(message, userDid, userPk, challenge, byField, byValue);
        return encodeResponse({'success': true, 'proof': proof});
      } catch (e, stackTrace) {
        return encodeResponse({'success': false, 'error': e.toString(), 'stackTrace': stackTrace.toString()});
      }
    case 'claimCredential':
      final args = call.arguments;
      final String offerMessage = args['offerMessage'] ?? '';
      final String userDid = args['userDid'] ?? '';
      final String userPk = args['userPk'] ?? '';
      if (offerMessage == '' || userDid == '' || userPk == '') {
        return encodeResponse({'success': false, 'error': 'Missing arguments'});
      }

      try {
        var credentials = await _zkGenerator.claimCredential(offerMessage, userDid, userPk);
        return encodeResponse({'success': true, 'credentials': credentials.map((e) => e.toJson()).toList()});
      } catch (e, stackTrace) {
        return encodeResponse({'success': false, 'error': e.toString(), 'stackTrace': stackTrace.toString()});
      }

    case 'backupIdentity':
      final args = call.arguments;
      final String userDid = args['userDid'] ?? '';
      final String userPk = args['userPk'] ?? '';
      if (userDid == '' || userPk == '') {
        return encodeResponse({'success': false, 'error': 'Missing arguments'});
      }

      try {
        var backup = await _zkGenerator.backupIdentity(userDid, userPk);
        return encodeResponse({'success': true, 'backup': backup});
      } catch (e, stackTrace) {
        return encodeResponse({'success': false, 'error': e.toString(), 'stackTrace': stackTrace.toString()});
      }

    case 'restoreIdentity':
      final args = call.arguments;
      final String backup = args['backup'] ?? '';
      final String userDid = args['userDid'] ?? '';
      final String userPk = args['userPk'] ?? '';
      if (backup == '' || userDid == '' || userPk == '') {
        return encodeResponse({'success': false, 'error': 'Missing arguments'});
      }

      try {
        await _zkGenerator.restoreIdentity(backup, userDid, userPk);
        return encodeResponse({'success': true});
      } catch (e, stackTrace) {
        return encodeResponse({'success': false, 'error': e.toString(), 'stackTrace': stackTrace.toString()});
      }
    
    case 'getCredentials':
      final args = call.arguments;
      final String userDid = args['userDid'] ?? '';
      final String userPk = args['userPk'] ?? '';
      final String? byField = args['byField'] == '' ? null : args['byField'];
      final String? byValue = args['byValue'] == '' ? null : args['byValue'];
      if (userDid == '' || userPk == '') {
        return encodeResponse({'success': false, 'error': 'Missing arguments'});
      }

      try {
        var credentials = await _zkGenerator.getCredentials(userDid, userPk, byField, byValue);
        return encodeResponse({'success': true, 'credentials': credentials.map((e) => e.toJson()).toList()});
      } catch (e, stackTrace) {
        return encodeResponse({'success': false, 'error': e.toString(), 'stackTrace': stackTrace.toString()});
      }

    default:
      //Throw unimplemented error for unknown methods
      throw PlatformException(
        code: 'UNIMPLEMENTED',
        message: 'Method "${call.method}" not implemented in wira_logic, check your method name and arguments.',
      );
  }
}