import '../../imports/imports.dart';
import '../../data/repositories/listing_repository.dart';
import '../../data/repositories/university_repository.dart';
import '../auth/bloc/session_bloc.dart';
import 'property_details_cubit.dart';
import 'views/property_details_view.dart';

class PropertyDetailsPage extends StatelessWidget {
  const PropertyDetailsPage(
      {super.key, required this.listingId, this.universityId});
  final String listingId;
  final int? universityId;
  @override
  Widget build(BuildContext context) => BlocBuilder<SessionBloc, SessionState>(
        buildWhen: (previous, next) => previous.user?.id != next.user?.id,
        builder: (context, session) {
          final user = session.user;
          if (user == null) return const SizedBox.shrink();
          return BlocProvider(
            key: ValueKey('detail:${user.id}:$listingId:$universityId'),
            create: (_) => PropertyDetailsCubit(
                listings: context.read<ListingRepository>(),
                universities: context.read<UniversityRepository>(),
                userId: user.id,
                listingId: listingId,
                universityId: universityId)
              ..load(),
            child: const _DetailsBinding(),
          );
        },
      );
}

class _DetailsBinding extends StatelessWidget {
  const _DetailsBinding();

  Future<void> _request(BuildContext context) async {
    final cubit = context.read<PropertyDetailsCubit>();
    final listing = cubit.state.listing;
    if (listing == null || !cubit.state.canRequest) return;
    await context
        .pushNamed('bookingRequest', pathParameters: {'listingId': listing.id});
    if (context.mounted) await cubit.load();
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<PropertyDetailsCubit, PropertyDetailsState>(
        builder: (context, state) => PropertyDetailsView(
          state: state,
          onRetry: context.read<PropertyDetailsCubit>().load,
          onRequest: () => _request(context),
          onBack: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.goNamed('discovery');
            }
          },
        ),
      );
}
