import '../../imports/imports.dart';
import '../../data/models/listing.dart';
import '../../data/repositories/listing_repository.dart';
import '../auth/bloc/session_bloc.dart';
import 'landlord_listings_cubit.dart';
import 'views/landlord_listings_view.dart';

class LandlordListingsPage extends StatelessWidget {
  const LandlordListingsPage({super.key});

  @override
  Widget build(BuildContext context) => BlocBuilder<SessionBloc, SessionState>(
        buildWhen: (previous, next) => previous.user != next.user,
        builder: (context, session) {
          final user = session.user;
          if (user == null) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          return BlocProvider(
            key: ValueKey('landlord:${user.id}'),
            create: (_) => LandlordListingsCubit(
                repository: context.read<ListingRepository>(), userId: user.id)
              ..load(),
            child: const _LandlordListingsBinding(),
          );
        },
      );
}

class _LandlordListingsBinding extends StatelessWidget {
  const _LandlordListingsBinding();

  Future<void> _edit(BuildContext context, [Listing? listing]) async {
    if (listing == null) {
      await context.pushNamed('listingCreate');
    } else {
      await context
          .pushNamed('listingEdit', pathParameters: {'listingId': listing.id});
    }
    if (context.mounted) await context.read<LandlordListingsCubit>().load();
  }

  Future<void> _requests(BuildContext context) async {
    await context.pushNamed('landlordBookings');
    if (context.mounted) await context.read<LandlordListingsCubit>().load();
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<LandlordListingsCubit, LandlordListingsState>(
        builder: (context, state) => LandlordListingsView(
          state: state,
          onCreate: () => _edit(context),
          onOpen: (listing) => _edit(context, listing),
          onAccount: () => context.pushNamed('account'),
          onRequests: () => _requests(context),
          onRefresh: () => context.read<LandlordListingsCubit>().load(),
          onLoadMore: () =>
              context.read<LandlordListingsCubit>().load(more: true),
        ),
      );
}
