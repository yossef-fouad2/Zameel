import '../../imports/imports.dart';

class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({
    super.key,
    required this.title,
    this.titleWidget,
    this.actions,
    this.centerTitle = true,
    this.onPressed,
    this.isTransparent = false,
  });

  final String title;
  final Widget? titleWidget;
  final List<Widget>? actions;
  final VoidCallback? onPressed;
  final bool? centerTitle;
  final bool isTransparent;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final router = GoRouter.maybeOf(context);
    final navigator = Navigator.maybeOf(context);
    final canPop =
        (router?.canPop() ?? false) || (navigator?.canPop() ?? false);

    void handleBack() {
      if (onPressed != null) {
        onPressed!();
      } else if (router?.canPop() ?? false) {
        router!.pop();
      } else if (navigator?.canPop() ?? false) {
        navigator!.maybePop();
      }
    }

    return AppBar(
      centerTitle: centerTitle,
      automaticallyImplyLeading: false,
      elevation: 0,
      backgroundColor: isTransparent ? Colors.transparent : null,
      shadowColor: Colors.transparent,
      title: titleWidget ??
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.appBarTheme.titleTextStyle?.copyWith(
                  fontWeight: FontWeight.w600,
                ) ??
                theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
      leading: onPressed != null || canPop
          ? BackButton(onPressed: handleBack)
          : null,
      iconTheme: theme.appBarTheme.iconTheme,
      actions: actions ?? [],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
