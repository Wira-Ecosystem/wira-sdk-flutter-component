import 'dart:async';
import 'dart:convert';

import 'package:polygonid_flutter_sdk/circuits/data/circuit_model.dart';
import 'package:polygonid_flutter_sdk/circuits/data/circuits_to_download_param.dart';
import 'package:polygonid_flutter_sdk/common/domain/entities/chain_config_entity.dart';
import 'package:polygonid_flutter_sdk/common/domain/entities/env_entity.dart';
import 'package:polygonid_flutter_sdk/common/domain/entities/filter_entity.dart';
import 'package:polygonid_flutter_sdk/credential/domain/entities/claim_entity.dart';
import 'package:polygonid_flutter_sdk/iden3comm/domain/entities/credential/request/offer_iden3_message_entity.dart';
import 'package:polygonid_flutter_sdk/iden3comm/domain/entities/proof/request/contract_iden3_message_entity.dart';
import 'package:polygonid_flutter_sdk/proof/domain/entities/download_info_entity.dart';
import 'package:polygonid_flutter_sdk/sdk/polygon_id_sdk.dart';

class _Lock {
  Completer<void>? _completer;

  Future<T> synchronized<T>(Future<T> Function() fn) async {
    while (_completer != null) {
      await _completer!.future;
    }
    _completer = Completer<void>();
    try {
      return await fn();
    } finally {
      final c = _completer!;
      _completer = null;
      c.complete();
    }
  }
}

class ZkGenerator {
  static final EnvEntity defaultEnv = EnvEntity(
    pushUrl: 'https://push-staging.polygonid.com/api/v1',
    ipfsUrl: 'https://ipfs.io',
    ipfsGatewayUrl: 'https://ipfs.io/ipfs/',
    chainConfigs: {
      "80002": ChainConfigEntity(
        blockchain: 'polygon',
        network: 'amoy',
        rpcUrl: 'https://rpc-amoy.polygon.technology/',
        stateContractAddr: '0x1a4cC30f2aA0377b0c3bc9848766D90cb4404124',
      )
    },
    didMethods: []
  );
  static final defaultCircuits = CircuitsToDownloadParam(
    zipFileName: "circuits",
    bucketUrl: "https://0bb12tnp-3001.brs.devtunnels.ms/api/v1/circuits/keys.zip",
    circuitsWithChecksum: [
      CircuitModel(
        fileName: 'authV2.dat',
        circuitId: 'authV2',
        checksum: null,
      ),
      CircuitModel(
        fileName: 'credentialAtomicQuerySigV2.dat',
        circuitId: 'credentialAtomicQuerySigV2',
        checksum: null,
      ),
    ],
  );

  final _lock = _Lock();

  ZkGenerator();

  Future<void> initialize(EnvEntity? env) async {
    await PolygonIdSdk.init(env: env ?? defaultEnv);
  }

  Future<Stream<DownloadInfo>> downloadCircuits(
    CircuitsToDownloadParam? circuitsToDownload
  ) async {
    var areDownloaded = await PolygonIdSdk.I.circuits.checkCircuits(circuitsToCheck: circuitsToDownload?.circuitsWithChecksum
      ?? defaultCircuits.circuitsWithChecksum );

    if (areDownloaded) {
      return Stream<DownloadInfo>.fromIterable([
        DownloadInfoOnDone(contentLength: 0, downloaded: 0)
      ]);
    }

    return PolygonIdSdk.I.circuits.initCircuitsDownloadAndGetInfoStream(
      circuitsToDownload: circuitsToDownload ?? defaultCircuits,
    );
  }

  void handleDownloadInfo(Stream<DownloadInfo> stream, void Function(String, String) onInfo) {
    late StreamSubscription<DownloadInfo> subscription;

    subscription = stream.listen((info) {
        if (info is DownloadInfoOnProgress) {
          onInfo('downloading', '${(info.downloaded / info.contentLength * 100).toStringAsFixed(2)} %');
        } else if (info is DownloadInfoOnDone) {
          onInfo('done', 'Download completed');
          subscription.cancel();
        } else if (info is DownloadInfoOnError) {
          onInfo('error', 'Download error: ${info.errorMessage}');
        }
      },
      cancelOnError: true,
      onError: (error) => onInfo('error', 'Stream error occurred: $error'),
    );
  }

  Future<String> addIdentity() async {
    return _lock.synchronized(() async {
      var identityEntity = await PolygonIdSdk.I.identity.addIdentity();
      return jsonEncode(identityEntity.toJson());
    });
  }

  Future<void> authenticate(String msg, String did, String pk) async {
    await _lock.synchronized(() async {
      var message = await PolygonIdSdk.I.iden3comm.getIden3Message(message: msg);
      await PolygonIdSdk.I.iden3comm.authenticate(
        privateKey: pk,
        genesisDid: did,
        message: message,
      );
    });
  }

  Future<String> getProof(String message, String did, String pk, String challenge, String byField, String byValue) async {
    return _lock.synchronized(() async {
      var credentials = await PolygonIdSdk.I.credential.getClaims(
        genesisDid: did,
        privateKey: pk,
        filters: [
          FilterEntity(operator: FilterOperator.equal, name: byField, value: byValue)
        ]
      );

      if (credentials.isEmpty) {
        throw Exception("No credentials found for the identity");
      }

      var credential = credentials.first;

      var iden3message = await PolygonIdSdk.I.iden3comm.getIden3Message(message: message) as ContractInvokeRequestMessage;
      var proof = await PolygonIdSdk.I.iden3comm.getProof(
        request: iden3message.body.scope[0],
        genesisDid: did,
        privateKey: pk,
        verifierDid: '',
        transactionData: iden3message.body.transactionData.toJson(),
        credential: credential,
        challenge: challenge
      );
      return jsonEncode(proof.toJson());
    });
  }

  Future<List<CredentialEntity>> claimCredential(String message, String did, String pk) async {
    return _lock.synchronized(() async {
      var iden3message = await PolygonIdSdk.I.iden3comm.getIden3Message(message: message);
      return await PolygonIdSdk.I.iden3comm.fetchAndSaveClaims(
        message: iden3message as CredentialsOfferMessage,
        genesisDid: did,
        privateKey: pk,
        profileNonce: BigInt.from(0),
        keys: []
      );
    });
  }

  Future<String> backupIdentity(String did, String pk) async {
    return _lock.synchronized(() async {
      return await PolygonIdSdk.I.identity.backupIdentity(
        genesisDid: did,
        privateKey: pk,
      );
    });
  }

  Future<void> restoreIdentity(String backup, String did, String pk) async {
    await _lock.synchronized(() async {
      await PolygonIdSdk.I.identity.restoreIdentity(
        genesisDid: did,
        privateKey: pk,
        encryptedDb: backup,
      );
    });
  }

  Future<List<CredentialEntity>> getCredentials(String did, String pk, String? byField, String? byValue) async {
    return _lock.synchronized(() async {
      return await PolygonIdSdk.I.credential.getClaims(
        genesisDid: did,
        privateKey: pk,
        filters: [
          if (byField != null && byValue != null)
            FilterEntity(operator: FilterOperator.equal, name: byField, value: byValue)
        ]
      );
    });
  }
}