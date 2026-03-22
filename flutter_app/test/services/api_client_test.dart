import 'package:dio/dio.dart';
import 'package:edict_app/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDio extends Mock implements Dio {
  final BaseOptions _baseOptions = BaseOptions(baseUrl: 'http://test');

  @override
  BaseOptions get options => _baseOptions;
}

void main() {
  setUpAll(() {
    registerFallbackValue(RequestOptions(path: '/'));
  });

  group('ApiClient constructor', () {
    test('can be created with custom Dio instance', () {
      final dio = MockDio();

      final client = ApiClient(dio: dio);

      expect(client.baseUrl, 'http://test');
    });

    test('can be created with custom baseUrl', () {
      final client = ApiClient(baseUrl: 'https://api.example.com');

      expect(client.baseUrl, 'https://api.example.com');
    });

    test('applies custom baseUrl to provided Dio when non-empty', () {
      final dio = MockDio();

      final client =
          ApiClient(dio: dio, baseUrl: 'https://override.example.com');

      expect(client.baseUrl, 'https://override.example.com');
      expect(dio.options.baseUrl, 'https://override.example.com');
    });
  });

  group('artifactDownloadUrl', () {
    test('with empty baseUrl returns relative web URL', () {
      final client = ApiClient(baseUrl: '');

      final url = client.artifactDownloadUrl('folder/测试 a.txt');

      expect(url, '/api/files/download?path=folder%2F%E6%B5%8B%E8%AF%95+a.txt');
    });

    test('with non-empty baseUrl returns full URL', () {
      final client = ApiClient(baseUrl: 'https://api.example.com');

      final url = client.artifactDownloadUrl('folder/a b.txt');

      expect(
        url,
        'https://api.example.com/api/files/download?path=folder%2Fa+b.txt',
      );
    });
  });

  group('event type constants', () {
    test('match backend event names', () {
      expect(
        ApiClient.eventStartPlanning,
        'workflow.v2.command.start_planning',
      );
      expect(ApiClient.eventSubmitPlan, 'workflow.v2.command.submit_plan');
      expect(ApiClient.eventApprovePlan, 'workflow.v2.command.approve_plan');
      expect(ApiClient.eventRejectPlan, 'workflow.v2.command.reject_plan');
      expect(ApiClient.eventStopWorkflow, 'workflow.v2.command.stop');
      expect(ApiClient.eventCancelWorkflow, 'workflow.v2.command.cancel');
      expect(ApiClient.eventResumeWorkflow, 'workflow.v2.command.resume');
      expect(ApiClient.eventSelectCandidate,
          'workflow.v2.command.select_candidate');
      expect(ApiClient.eventApproveAssembly,
          'workflow.v2.command.approve_assembly');
      expect(
          ApiClient.eventRejectAssembly, 'workflow.v2.command.reject_assembly');
      expect(ApiClient.eventRollbackWorkflow, 'workflow.v2.command.rollback');

      expect(ApiClient.eventNodeProgress, 'workflow.v2.command.node_progress');
      expect(ApiClient.eventCompleteCandidate,
          'workflow.v2.command.complete_candidate');
      expect(
          ApiClient.eventRegenerateNode, 'workflow.v2.command.regenerate_node');
    });
  });

  group('_extractErrorMessage via taskAction/_postAction', () {
    test('403 + detail map uses no-permission message', () async {
      final dio = MockDio();
      final client = ApiClient(dio: dio);
      final requestOptions = RequestOptions(path: '/api/task-action');

      when(() => dio.post<dynamic>(any(), data: any(named: 'data'))).thenThrow(
        DioException(
          requestOptions: requestOptions,
          response: Response<dynamic>(
            requestOptions: requestOptions,
            statusCode: 403,
            data: <String, dynamic>{'detail': '当前角色不允许'},
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      final result = await client.taskAction('task-1', 'approve', 'ok');

      expect(result.ok, isFalse);
      expect(result.error, contains('当前角色无权限执行该动作'));
      expect(result.message, contains('当前角色无权限执行该动作'));
    });

    test('422 + detail list uses validation-failed message', () async {
      final dio = MockDio();
      final client = ApiClient(dio: dio);
      final requestOptions = RequestOptions(path: '/api/task-action');

      when(() => dio.post<dynamic>(any(), data: any(named: 'data'))).thenThrow(
        DioException(
          requestOptions: requestOptions,
          response: Response<dynamic>(
            requestOptions: requestOptions,
            statusCode: 422,
            data: <String, dynamic>{
              'detail': <Map<String, dynamic>>[
                <String, dynamic>{
                  'loc': <String>['body', 'action'],
                  'msg': 'field required',
                  'type': 'value_error.missing',
                },
              ],
            },
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      final result = await client.taskAction('task-1', 'approve', 'ok');

      expect(result.ok, isFalse);
      expect(result.error, contains('参数校验失败'));
    });

    test('no response data falls back to generic error', () async {
      final dio = MockDio();
      final client = ApiClient(dio: dio);
      final requestOptions = RequestOptions(path: '/api/task-action');

      when(() => dio.post<dynamic>(any(), data: any(named: 'data'))).thenThrow(
        DioException(
          requestOptions: requestOptions,
          type: DioExceptionType.unknown,
        ),
      );

      final result = await client.taskAction('task-1', 'approve', 'ok');

      expect(result.ok, isFalse);
      expect(result.error, isNotNull);
      expect(result.error, isNotEmpty);
      expect(result.error, isNot(contains('参数校验失败')));
      expect(result.error, isNot(contains('当前角色无权限执行该动作')));
    });
  });

  group('workflow review command payload', () {
    test('approveWorkflowRevision defaults actor to zhongshu', () async {
      final dio = MockDio();
      final client = ApiClient(dio: dio);

      when(() => dio.post<dynamic>(any(), data: any(named: 'data'))).thenAnswer(
        (_) async => Response<dynamic>(
          requestOptions: RequestOptions(path: '/api/workflows/wf-1/commands'),
          data: <String, dynamic>{'ok': true, 'entryId': 'stream-1'},
        ),
      );

      final result = await client.approveWorkflowRevision(
        'wf-1',
        revisionId: 'rev-1',
      );

      expect(result.ok, isTrue);
      final captured = verify(
        () => dio.post<dynamic>(
          '/api/workflows/wf-1/commands',
          data: captureAny(named: 'data'),
        ),
      ).captured.single as Map<String, dynamic>;
      expect(captured['eventType'], ApiClient.eventApprovePlan);
      final payload = captured['payload'] as Map<String, dynamic>;
      expect(payload['revision_id'], 'rev-1');
      expect(payload['actor'], 'zhongshu');
    });

    test('rejectWorkflowRevision keeps explicit actor override', () async {
      final dio = MockDio();
      final client = ApiClient(dio: dio);

      when(() => dio.post<dynamic>(any(), data: any(named: 'data'))).thenAnswer(
        (_) async => Response<dynamic>(
          requestOptions: RequestOptions(path: '/api/workflows/wf-2/commands'),
          data: <String, dynamic>{'ok': true, 'entryId': 'stream-2'},
        ),
      );

      final result = await client.rejectWorkflowRevision(
        'wf-2',
        revisionId: 'rev-2',
        actor: 'emperor',
        comment: 'needs revision',
      );

      expect(result.ok, isTrue);
      final captured = verify(
        () => dio.post<dynamic>(
          '/api/workflows/wf-2/commands',
          data: captureAny(named: 'data'),
        ),
      ).captured.single as Map<String, dynamic>;
      expect(captured['eventType'], ApiClient.eventRejectPlan);
      final payload = captured['payload'] as Map<String, dynamic>;
      expect(payload['revision_id'], 'rev-2');
      expect(payload['actor'], 'emperor');
      expect(payload['comment'], 'needs revision');
    });
  });
}
