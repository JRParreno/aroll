import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/enum/state_enum.dart';
import 'package:aroll_mobile/domain/entities/attendance_record.dart';
import 'package:aroll_mobile/presentation/attendance/bloc/attendance_bloc/attendance_bloc.dart';
import 'package:aroll_mobile/presentation/attendance/bloc/attendance_bloc/attendance_event.dart';
import 'package:aroll_mobile/presentation/attendance/bloc/attendance_bloc/attendance_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  late final AttendanceBloc _bloc;

  @override
  void initState() {
    super.initState();
    _bloc = sl<AttendanceBloc>()..add(const FetchAttendanceEvent());
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _bloc.close();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    if (_scrollController.offset < max - 200) return;

    final state = _bloc.state;
    if (state is! SuccessAttendanceState) return;
    if (!state.data.hasMore || state.status == StateEnum.loadingMore) return;

    _bloc.add(const NextPageAttendanceEvent());
  }

  void _onSearch(String value) {
    _bloc
      ..add(const ResetAttendanceEvent())
      ..add(FetchAttendanceEvent(search: value.trim().isEmpty ? null : value));
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _bloc,
      child: Scaffold(
        appBar: AppBar(title: const Text('Attendance history')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search employee…',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      _onSearch('');
                    },
                  ),
                ),
                onSubmitted: _onSearch,
              ),
            ),
            Expanded(
              child: BlocConsumer<AttendanceBloc, AttendanceState>(
                listener: (context, state) {
                  if (state is ErrorAttendanceState) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(state.message)),
                    );
                  }
                },
                builder: (context, state) {
                  if (state is LoadingAttendanceState ||
                      state is InitialAttendanceState) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (state is ErrorAttendanceState && state.message.isNotEmpty) {
                    return Center(child: Text(state.message));
                  }

                  if (state is! SuccessAttendanceState) {
                    return const SizedBox.shrink();
                  }

                  final records = state.data.items;
                  if (records.isEmpty) {
                    return const Center(child: Text('No records found'));
                  }

                  final loadingMore =
                      state.status == StateEnum.loadingMore;

                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: records.length + (loadingMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= records.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }
                      return _AttendanceTile(record: records[index]);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttendanceTile extends StatelessWidget {
  const _AttendanceTile({required this.record});

  final AttendanceRecord record;

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('MMM d, yyyy • HH:mm').format(record.recordedAt);
    final isIn = record.type == AttendanceType.clockIn;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isIn ? Colors.green.shade100 : Colors.orange.shade100,
          child: Icon(
            isIn ? Icons.login : Icons.logout,
            color: isIn ? Colors.green.shade800 : Colors.orange.shade800,
          ),
        ),
        title: Text(record.employeeName),
        subtitle: Text('$time\n${record.locationLabel}'),
        isThreeLine: true,
        trailing: Text(
          isIn ? 'IN' : 'OUT',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isIn ? Colors.green.shade700 : Colors.orange.shade700,
          ),
        ),
      ),
    );
  }
}
