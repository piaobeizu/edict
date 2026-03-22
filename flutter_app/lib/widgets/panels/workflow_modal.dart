import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/ui_provider.dart';
import '../common/common.dart';
import '../mobile/workflow_detail_screen.dart';

class WorkflowModalHost extends ConsumerStatefulWidget {
  const WorkflowModalHost({super.key});

  @override
  ConsumerState<WorkflowModalHost> createState() => _WorkflowModalHostState();
}

class _WorkflowModalHostState extends ConsumerState<WorkflowModalHost> {
  bool _showing = false;
  ProviderSubscription<String?>? _modalSub;

  @override
  void initState() {
    super.initState();
    _modalSub =
        ref.listenManual<String?>(modalWorkflowIdProvider, (previous, next) {
      if (next != null && !_showing) {
        _open(next);
        return;
      }
      if (next == null &&
          _showing &&
          Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    });
  }

  @override
  void dispose() {
    _modalSub?.close();
    super.dispose();
  }

  Future<void> _open(String workflowId) async {
    _showing = true;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'workflow-modal',
      barrierColor: Colors.black54,
      pageBuilder: (_, __, ___) => _WorkflowModalView(workflowId: workflowId),
    );
    _showing = false;
    if (mounted) {
      ref.read(modalWorkflowIdProvider.notifier).state = null;
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _WorkflowModalView extends ConsumerWidget {
  const _WorkflowModalView({required this.workflowId});

  final String workflowId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modalBody = Material(
      color: Colors.black54,
      child: Center(
        child: Container(
          width: MediaQuery.sizeOf(context).width * 0.88,
          height: MediaQuery.sizeOf(context).height * 0.9,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Container(
                color: const Color(0xFFF8FAFC),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Workflow 详情',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        ref.read(modalWorkflowIdProvider.notifier).state = null;
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: kIsWeb
                    ? SafeSelectionArea(
                        child: WorkflowDetailScreen(
                          workflowId: workflowId,
                          showAppBar: false,
                        ),
                      )
                    : WorkflowDetailScreen(
                        workflowId: workflowId,
                        showAppBar: false,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
    return modalBody;
  }
}
