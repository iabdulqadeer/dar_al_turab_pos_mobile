import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/providers/auth_providers.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/pos/presentation/edit_sale_screen.dart';
import '../../features/pos/presentation/pos_screen.dart';
import '../../features/printing/presentation/printer_settings_screen.dart';
import '../../features/profile/presentation/change_password_screen.dart';
import '../../features/profile/presentation/edit_profile_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/sales/presentation/sale_detail_screen.dart';
import '../../features/sales/presentation/sales_list_screen.dart';
import '../../features/splash/presentation/splash_screen.dart';
import '../widgets/app_shell.dart';

abstract final class Routes {
  static const splash = '/';
  static const login = '/login';

  // Bottom-navigation branches. Each is the root of its own stack.
  static const dashboard = '/dashboard';
  static const sales = '/sales';
  static const printer = '/printer';
  static const profile = '/profile';

  /// Pushed over the shell rather than being a tab — a sale in progress
  /// should not be interrupted by bottom-bar navigation.
  static const pos = '/pos';

  // Pushed on top of the profile branch.
  static const editProfile = '/profile/edit';
  static const changePassword = '/profile/password';
}

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  // Rebuilding the router on every auth change would drop navigation state,
  // so instead we expose auth as a Listenable that go_router refreshes on.
  final refresh = _AuthRefreshNotifier(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: Routes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: Routes.pos,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const PosScreen(),
      ),

      // Each branch keeps its own navigator, so a tab's stack and scroll
      // position survive switching away and back.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.dashboard,
                builder: (context, state) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.sales,
                builder: (context, state) => const SalesListScreen(),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (context, state) {
                      // A non-numeric id cannot match a sale; the server would
                      // answer 404 anyway, so fail fast with a clear message.
                      final id = int.tryParse(
                        state.pathParameters['id'] ?? '',
                      );
                      if (id == null) {
                        return const _InvalidRouteScreen(
                          message: 'That sale reference is not valid.',
                        );
                      }
                      return SaleDetailScreen(saleId: id);
                    },
                    routes: [
                      GoRoute(
                        path: 'edit',
                        // Pushed over the shell: an edit in progress should
                        // not be interrupted by bottom-bar navigation.
                        parentNavigatorKey: _rootNavigatorKey,
                        builder: (context, state) {
                          final id = int.tryParse(
                            state.pathParameters['id'] ?? '',
                          );
                          if (id == null) {
                            return const _InvalidRouteScreen(
                              message: 'That sale reference is not valid.',
                            );
                          }
                          return EditSaleScreen(saleId: id);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.printer,
                builder: (context, state) => const PrinterSettingsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.profile,
                builder: (context, state) => const ProfileScreen(),
                routes: [
                  GoRoute(
                    path: 'edit',
                    builder: (context, state) => const EditProfileScreen(),
                  ),
                  GoRoute(
                    path: 'password',
                    builder: (context, state) => const ChangePasswordScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final location = state.matchedLocation;

      // Session not yet restored: hold on splash so we never flash the login
      // screen at a user who already has a valid token.
      if (auth is AuthUnknown) {
        return location == Routes.splash ? null : Routes.splash;
      }

      final signedIn = auth is AuthSignedIn;

      if (!signedIn) {
        return location == Routes.login ? null : Routes.login;
      }

      if (location == Routes.login || location == Routes.splash) {
        return Routes.dashboard;
      }

      return null;
    },
  );
});

class _InvalidRouteScreen extends StatelessWidget {
  const _InvalidRouteScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(child: Text(message)),
    );
  }
}

/// Bridges Riverpod auth state to go_router's Listenable-based refresh.
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    _subscription = ref.listen<AuthState>(
      authControllerProvider,
      (previous, next) => notifyListeners(),
    );
  }

  late final ProviderSubscription<AuthState> _subscription;

  @override
  void dispose() {
    _subscription.close();
    super.dispose();
  }
}
