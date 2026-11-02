import '../../imports/imports.dart';
import '../../data/models/booking.dart';
import '../../data/repositories/booking_repository.dart';
import '../auth/bloc/session_bloc.dart';
import 'booking_details_cubit.dart';
import 'views/booking_details_view.dart';

class BookingDetailsPage extends StatelessWidget {
  const BookingDetailsPage({
    super.key,
    required this.bookingId,
    required this.role,
  });
  final String bookingId;
  final UserRole role;

  @override
  Widget build(BuildContext context) => BlocBuilder<SessionBloc, SessionState>(
        buildWhen: (previous, next) => previous.user?.id != next.user?.id,
        builder: (context, session) {
          final user = session.user;
          if (user == null) return const SizedBox.shrink();
          return BlocProvider(
            key: ValueKey('booking-detail:${user.id}:$bookingId:${role.name}'),
            create: (_) => BookingDetailsCubit(
                repository: context.read<BookingRepository>(),
                userId: user.id,
                role: role,
                bookingId: bookingId)
              ..load(),
            child: _DetailsBinding(role: role),
          );
        },
      );
}

class _DetailsBinding extends StatefulWidget {
  const _DetailsBinding({required this.role});
  final UserRole role;
  @override
  State<_DetailsBinding> createState() => _DetailsBindingState();
}

class _DetailsBindingState extends State<_DetailsBinding> {
  bool _confirming = false;

  void _back() {
    if (context.read<BookingDetailsCubit>().state.isBusy) return;
    if (context.canPop()) {
      context.pop();
    } else if (widget.role == UserRole.landlord) {
      context.goNamed('landlordBookings');
    } else {
      context.goNamed('discovery', queryParameters: {'tab': 'requests'});
    }
  }

  Future<void> _confirm(BookingAction action) async {
    final cubit = context.read<BookingDetailsCubit>();
    if (_confirming || !cubit.state.canAct(action)) return;
    _confirming = true;
    final acceptedCancellation = action == BookingAction.cancel &&
        cubit.state.booking?.status == BookingStatus.accepted;
    final confirmed = await context.showAppDialog<bool>(
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: Text('bookings.confirm.${action.name}_title'.tr()),
        content: Text((acceptedCancellation
                ? 'bookings.confirm.cancel_accepted_body'
                : 'bookings.confirm.${action.name}_body')
            .tr()),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text('bookings.go_back'.tr())),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(action.translationKey.tr())),
        ],
      ),
    );
    _confirming = false;
    if (mounted && (confirmed ?? false)) await cubit.act(action);
  }

  Future<void> _property() async {
    final cubit = context.read<BookingDetailsCubit>();
    final booking = cubit.state.booking;
    if (booking?.listing == null || cubit.state.isBusy) return;
    await context.pushNamed(
        widget.role == UserRole.landlord ? 'listingEdit' : 'listingDetails',
        pathParameters: {'listingId': booking!.listingId});
    if (mounted) await cubit.load();
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<BookingDetailsCubit, BookingDetailsState>(
        builder: (context, state) {
          final cubit = context.read<BookingDetailsCubit>();
          return PopScope(
            canPop: !state.isBusy,
            child: BookingDetailsView(
                state: state,
                role: widget.role,
                onBack: _back,
                onReload: cubit.load,
                onRetryAction: cubit.retryAction,
                onAction: _confirm,
                onProperty: _property),
          );
        },
      );
}
