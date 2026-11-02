import '../../imports/imports.dart';
import '../../data/models/geo_point.dart';
import '../../data/models/listing.dart';
import '../../data/models/university.dart';
import '../../data/repositories/listing_repository.dart';
import '../../data/repositories/university_repository.dart';
import '../auth/bloc/session_bloc.dart';
import 'listing_editor_cubit.dart';
import 'views/listing_editor_view.dart';

class PropertyLocationArguments {
  const PropertyLocationArguments(
      {this.location, this.universities = const []});
  final GeoPoint? location;
  final List<University> universities;
}

class ListingEditorPage extends StatelessWidget {
  const ListingEditorPage({super.key, this.listingId});
  final String? listingId;

  @override
  Widget build(BuildContext context) => BlocBuilder<SessionBloc, SessionState>(
        buildWhen: (previous, next) => previous.user?.id != next.user?.id,
        builder: (context, session) {
          final user = session.user;
          if (user == null) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          return BlocProvider(
            key: ValueKey('editor:${user.id}:$listingId'),
            create: (_) => ListingEditorCubit(
              repository: context.read<ListingRepository>(),
              universities: context.read<UniversityRepository>(),
              userId: user.id,
              listingId: listingId,
            )..load(),
            child: const _ListingEditorBinding(),
          );
        },
      );
}

class _ListingEditorBinding extends StatefulWidget {
  const _ListingEditorBinding();
  @override
  State<_ListingEditorBinding> createState() => _ListingEditorBindingState();
}

class _ListingEditorBindingState extends State<_ListingEditorBinding> {
  bool _askingToLeave = false;

  Future<bool> _allowLeave() async {
    final cubit = context.read<ListingEditorCubit>();
    if (cubit.state.isSaving || _askingToLeave) return false;
    if (!cubit.state.isDirty) return true;
    _askingToLeave = true;
    final discard = await context.showAppDialog<bool>(
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: Text('profile.discard_title'.tr()),
        content: Text('profile.discard_body'.tr()),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text('profile.keep_editing'.tr())),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text('profile.discard'.tr())),
        ],
      ),
    );
    _askingToLeave = false;
    if (!mounted || discard != true) return false;
    cubit.discard();
    return true;
  }

  Future<void> _leave() async {
    if (!await _allowLeave() || !mounted) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.goNamed('landlord');
    }
  }

  Future<void> _reload() async {
    if (await _allowLeave() && mounted) {
      await context.read<ListingEditorCubit>().load(discard: true);
    }
  }

  Future<void> _pickLocation() async {
    final cubit = context.read<ListingEditorCubit>();
    FocusScope.of(context).unfocus();
    final point = await context.pushNamed<GeoPoint>(
      'propertyLocation',
      extra: PropertyLocationArguments(
          location: cubit.state.draft.location,
          universities: cubit.state.universities),
    );
    if (mounted && point != null) cubit.change(location: point);
  }

  Future<void> _publish() async {
    final cubit = context.read<ListingEditorCubit>();
    if (!cubit.state.canChangeStatus) return;
    final confirmed = await context.showAppDialog<bool>(
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: Text('listings.editor.publish_title'.tr()),
        content: Text('listings.editor.publish_notice'.tr()),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text('listings.cancel'.tr())),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text('listings.editor.publish'.tr())),
        ],
      ),
    );
    if (mounted && (confirmed ?? false)) {
      await cubit.setStatus(ListingStatus.published);
    }
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<ListingEditorCubit, ListingEditorState>(
        builder: (context, state) {
          final cubit = context.read<ListingEditorCubit>();
          return PopScope(
            canPop: !state.isDirty && !state.isSaving,
            onPopInvokedWithResult: (didPop, result) {
              if (!didPop) _leave();
            },
            child: ListingEditorView(
              state: state,
              onChange: cubit.change,
              onBack: _leave,
              onReload: _reload,
              onPickLocation: _pickLocation,
              onSave: () {
                FocusScope.of(context).unfocus();
                cubit.save();
              },
              onPublish: _publish,
              onDraft: () => cubit.setStatus(ListingStatus.draft),
              onArchive: () => cubit.setStatus(ListingStatus.archived),
              onRefreshRoutes: cubit.refreshRoutes,
            ),
          );
        },
      );
}
