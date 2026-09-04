import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/tenant_mode.dart';
import 'package:flutter/material.dart';

/// DEMO01-only research evaluation gate. Not a demo-mode security switch.
class ResearchEvaluationOverlay extends StatefulWidget {
  const ResearchEvaluationOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<ResearchEvaluationOverlay> createState() =>
      _ResearchEvaluationOverlayState();
}

class _ResearchEvaluationOverlayState extends State<ResearchEvaluationOverlay> {
  bool _checked = false;

  @override
  Widget build(BuildContext context) {
    final appState = sl<AppState>();
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final show = appState.session?.isDemo == true &&
            !appState.researchEvalAcknowledged;
        return Stack(
          children: [
            widget.child,
            if (show)
              Positioned.fill(
                child: Material(
                  color: Colors.black54,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Research evaluation',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.6,
                                    color: Color(0xFF6B7280),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  TenantModeCopy.researchTitle,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  TenantModeCopy.researchVoluntary,
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1.4,
                                    color: Color(0xFF4B5563),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                CheckboxListTile(
                                  value: _checked,
                                  contentPadding: EdgeInsets.zero,
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                  onChanged: (value) {
                                    setState(() => _checked = value == true);
                                  },
                                  title: const Text(
                                    TenantModeCopy.researchAttestation,
                                    style: TextStyle(fontSize: 13, height: 1.35),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: FilledButton(
                                    onPressed: _checked
                                        ? () {
                                            appState
                                                .acknowledgeResearchEvaluation();
                                            setState(() => _checked = false);
                                          }
                                        : null,
                                    child: const Text('Continue'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
