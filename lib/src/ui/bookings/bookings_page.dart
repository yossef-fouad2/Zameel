import '../../imports/imports.dart';
import '../../data/models/booking.dart';
import '../../data/repositories/booking_repository.dart';
import '../auth/bloc/session_bloc.dart';
import 'bookings_cubit.dart';
import 'views/bookings_view.dart';

class LandlordBookingsPage extends StatelessWidget {
  const LandlordBookingsPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppTopBar(
            title: 'bookings.landlord.navigation'.tr(),
            centerTitle: false,
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.goNamed('landlord');
              }
            }),
        body: const SafeArea(child: BookingsInbox(role: UserRole.landlord)),
      );
}

class BookingsInbox extends StatelessWidget {
  const BookingsInbox({super.key, required this.role, this.isActive = true});
  final UserRole role;
  final bool isActive;

  @override
  Widget build(BuildContext context) => BlocBuilder<SessionBloc, SessionState>(
        buildWhen: (previous, next) => previous.user?.id != next.user?.id,
        builder: (context, session) {
          final user = session.user;
          if (user == null) return const SizedBox.shrink();
          return BlocProvider(
            key: ValueKey('bookings:${user.id}:${role.name}'),
            create: (_) => BookingsCubit(
                repository: context.read<BookingRepository>(),
                userId: user.id,
                role: role)
              ..load(),
            child: _InboxBinding(role: role, isActive: isActive),
          );
        },
      );
}

class _InboxBinding extends StatefulWidget {
  const _InboxBinding({required this.role, required this.isActive});
  final UserRole role;
  final bool isActive;
  @override
  State<_InboxBinding> createState() => _InboxBindingState();
}

class _InboxBindingState extends State<_InboxBinding>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant _InboxBinding oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      context.read<BookingsCubit>().load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        widget.isActive &&
        (ModalRoute.of(context)?.isCurrent ?? false)) {
      context.read<BookingsCubit>().load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _open(Booking booking) async {
    await context.pushNamed(
        widget.role == UserRole.student
            ? 'studentBookingDetails'
            : 'landlordBookingDetails',
        pathParameters: {'bookingId': booking.id});
    if (mounted) await context.read<BookingsCubit>().load();
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<BookingsCubit, BookingsState>(
        builder: (context, state) => BookingsView(
            state: state,
            role: widget.role,
            onRefresh: context.read<BookingsCubit>().load,
            onMore: () => context.read<BookingsCubit>().load(more: true),
            onFilter: context.read<BookingsCubit>().selectFilter,
            onOpen: _open),
      );
}
