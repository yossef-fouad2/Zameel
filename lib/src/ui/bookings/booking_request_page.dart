import '../../imports/imports.dart';
import '../../data/repositories/booking_repository.dart';
import '../../data/repositories/listing_repository.dart';
import '../auth/bloc/session_bloc.dart';
import 'booking_request_cubit.dart';
import 'views/booking_request_view.dart';

class BookingRequestPage extends StatelessWidget {
  const BookingRequestPage({super.key, required this.listingId});
  final String listingId;

  @override
  Widget build(BuildContext context) => BlocBuilder<SessionBloc, SessionState>(
        buildWhen: (previous, next) => previous.user?.id != next.user?.id,
        builder: (context, session) {
          final user = session.user;
          if (user == null) return const SizedBox.shrink();
          return BlocProvider(
            key: ValueKey('booking-request:${user.id}:$listingId'),
            create: (_) => BookingRequestCubit(
                bookings: context.read<BookingRepository>(),
                listings: context.read<ListingRepository>(),
                userId: user.id,
                listingId: listingId)
              ..load(),
            child: const _RequestBinding(),
          );
        },
      );
}

class _RequestBinding extends StatefulWidget {
  const _RequestBinding();
  @override
  State<_RequestBinding> createState() => _RequestBindingState();
}

class _RequestBindingState extends State<_RequestBinding> {
  bool _askingToLeave = false;

  Future<void> _leave() async {
    final cubit = context.read<BookingRequestCubit>();
    if (cubit.state.isSubmitting || _askingToLeave) return;
    if (cubit.state.isDirty) {
      _askingToLeave = true;
      final leave = await context.showAppDialog<bool>(
        builder: (dialogContext) => AlertDialog(
          scrollable: true,
          title: Text('bookings.request.leave_title'.tr()),
          content: Text((cubit.state.isUncertain
                  ? 'bookings.request.leave_uncertain'
                  : 'bookings.request.leave_draft')
              .tr()),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text('bookings.stay'.tr())),
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text('bookings.leave'.tr())),
          ],
        ),
      );
      _askingToLeave = false;
      if (!mounted || leave != true) return;
      cubit.discardDraft();
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.goNamed('discovery');
    }
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<BookingRequestCubit, BookingRequestState>(
        builder: (context, state) {
          final cubit = context.read<BookingRequestCubit>();
          return PopScope(
            canPop: !state.isDirty && !state.isSubmitting,
            onPopInvokedWithResult: (didPop, result) {
              if (!didPop) _leave();
            },
            child: BookingRequestView(
              state: state,
              onBack: _leave,
              onReload: cubit.load,
              onMessage: cubit.changeMessage,
              onRoomType: cubit.changeRoomType,
              onSubmit: () {
                FocusScope.of(context).unfocus();
                cubit.submit();
              },
              onViewRequest: () {
                final booking = cubit.state.booking;
                if (booking == null) return;
                context.pushReplacementNamed('studentBookingDetails',
                    pathParameters: {'bookingId': booking.id});
              },
            ),
          );
        },
      );
}
