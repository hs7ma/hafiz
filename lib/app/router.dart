import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/models/models.dart';
import '../data/repositories/demo_repository.dart';
import '../features/admin/admin_home_screen.dart';
import '../features/admin/teacher_profile_screen.dart';
import '../features/auth/mosque_register_screen.dart';
import '../features/auth/teacher_register_screen.dart';
import '../features/auth/welcome_screen.dart';
import '../features/mushaf/mushaf_screens.dart';
import '../features/student/student_screens.dart';
import '../features/teacher/students_manage_screen.dart';
import '../features/teacher/teacher_home_screen.dart';

String _homeFor(UserRole role) => switch (role) {
      UserRole.mosqueAdmin => '/admin',
      UserRole.teacher => '/teacher',
      UserRole.student => '/student',
    };

bool _isPublicAuthPath(String location) {
  return location == '/' ||
      location == '/welcome' ||
      location == '/register' ||
      location == '/register/status' ||
      location.startsWith('/register/') ||
      location == '/teacher/register';
}

final routerProvider = Provider<GoRouter>((ref) {
  final user = ref.watch(authControllerProvider);

  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SplashScreen()),
      GoRoute(
        path: '/welcome',
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const MosqueRegisterScreen(),
        routes: [
          GoRoute(
            path: 'status',
            builder: (context, state) => const MosqueRequestStatusScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/teacher/register',
        builder: (context, state) {
          final extra = state.extra;
          if (extra is! TeacherInviteData) {
            return const WelcomeScreen();
          }
          return TeacherRegisterScreen(invite: extra);
        },
      ),
      GoRoute(
        path: '/admin',
        builder: (context, state) => const AdminHomeScreen(),
        redirect: (context, state) {
          if (user == null || user.role != UserRole.mosqueAdmin) {
            return '/welcome';
          }
          return null;
        },
        routes: [
          GoRoute(
            path: 'teachers/:id',
            builder: (context, state) => TeacherProfileScreen(
              teacherId: state.pathParameters['id']!,
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/teacher',
        builder: (context, state) => const TeacherHomeScreen(),
        redirect: (context, state) {
          if (user == null || user.role != UserRole.teacher) {
            return '/welcome';
          }
          return null;
        },
      ),
      GoRoute(
        path: '/teacher/students',
        builder: (context, state) => const StudentsManageScreen(),
        redirect: (context, state) {
          if (user == null || user.role != UserRole.teacher) {
            return '/welcome';
          }
          return null;
        },
      ),
      ShellRoute(
        builder: (context, state, child) => StudentShell(child: child),
        routes: [
          GoRoute(
            path: '/student',
            builder: (context, state) => const StudentHomeScreen(),
          ),
          GoRoute(
            path: '/student/mushaf',
            builder: (context, state) => const MushafScreen(),
          ),
          GoRoute(
            path: '/student/mushaf/index',
            builder: (context, state) => const MushafIndexScreen(),
          ),
          GoRoute(
            path: '/student/progress',
            builder: (context, state) => const ProgressScreen(),
          ),
        ],
        redirect: (context, state) {
          if (user == null || user.role != UserRole.student) {
            return '/welcome';
          }
          return null;
        },
      ),
    ],
    redirect: (context, state) {
      final loc = state.matchedLocation;
      if (user == null && !_isPublicAuthPath(loc)) return '/welcome';
      if (user != null && (loc == '/welcome' || loc == '/')) {
        return _homeFor(user.role);
      }
      if (loc.startsWith('/admin') &&
          user != null &&
          user.role != UserRole.mosqueAdmin) {
        return _homeFor(user.role);
      }
      if (loc.startsWith('/teacher') &&
          user != null &&
          user.role != UserRole.teacher) {
        return _homeFor(user.role);
      }
      if (loc.startsWith('/student') &&
          user != null &&
          user.role != UserRole.student) {
        return _homeFor(user.role);
      }
      return null;
    },
  );
});
