import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'application/app_controller.dart';
import 'data/sqlite_database.dart';
import 'data/sqlite_event_repository.dart';
import 'infrastructure/notification_service.dart';
import 'network/api_client.dart';
import 'network/api_event_repository.dart';
import 'network/server_login_screen.dart';
import 'presentation/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('uk');
  Intl.defaultLocale='uk';
  const apiUrl=String.fromEnvironment('EVENT_REMINDER_API_URL');
  if (apiUrl.isNotEmpty) {
    runApp(ServerModeHost(apiUrl:apiUrl));
  } else {
    final app=AppController(SqliteEventRepository(AppDatabase()),NotificationService());
    runApp(EventReminderApp(controller:app));
    await app.initialize();
  }
}

class EventReminderApp extends StatelessWidget {
  final AppController controller;
  const EventReminderApp({super.key,required this.controller});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation:controller,
    builder:(ctx,_) {
      final mode=switch(controller.theme){
        'dark'=>ThemeMode.dark,'light'=>ThemeMode.light,_=>ThemeMode.system,
      };
      ThemeData theme(Brightness brightness) {
        final color=ColorScheme.fromSeed(seedColor:const Color(0xFF4C67DC),brightness:brightness);
        return ThemeData(useMaterial3:true,colorScheme:color,
          inputDecorationTheme:InputDecorationTheme(
            border:OutlineInputBorder(borderRadius:BorderRadius.circular(12)),
            contentPadding:const EdgeInsets.symmetric(horizontal:12,vertical:14)),
          cardTheme:CardThemeData(elevation:0,
            color:brightness==Brightness.light?Colors.white:color.surfaceContainerLow,
            shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16),
              side:BorderSide(color:color.outlineVariant.withValues(alpha:.4)))),
        );
      }
      return MaterialApp(
        title:'Мої події',debugShowCheckedModeBanner:false,
        locale:const Locale('uk'),supportedLocales:const [Locale('uk'),Locale('en')],
        localizationsDelegates:const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        // The three Flutter SDK delegates are all required for date/time pickers.
        theme:theme(Brightness.light),darkTheme:theme(Brightness.dark),themeMode:mode,
        home:AppShell(controller:controller),
      );
    });
}


/// The original Flutter application remains offline by default.
/// Setting EVENT_REMINDER_API_URL enables this login + remote REST repository.
class ServerModeHost extends StatefulWidget {
  const ServerModeHost({super.key,required this.apiUrl});
  final String apiUrl;
  @override State<ServerModeHost> createState()=>_ServerModeHostState();
}
class _ServerModeHostState extends State<ServerModeHost> {
  late final ApiClient api=ApiClient(widget.apiUrl);
  AppController? controller;
  Future<void> _openApp() async {
    final app=AppController(ApiEventRepository(api),NotificationService());
    await app.initialize();
    final error = app.error;
    if (error != null) {
      throw StateError(error);
    }
    if(mounted)setState(()=>controller=app);
  }
  @override Widget build(BuildContext context) {
    final app=controller;
    if(app!=null)return EventReminderApp(controller:app);
    return MaterialApp(debugShowCheckedModeBanner:false,title:'Мої події — вхід',
      theme:ThemeData(useMaterial3:true,colorSchemeSeed:const Color(0xFF637BEE)),
      darkTheme:ThemeData(useMaterial3:true,brightness:Brightness.dark,
        colorSchemeSeed:const Color(0xFF637BEE)),themeMode:ThemeMode.system,
      home:ServerLoginScreen(api:api,onAuthenticated:_openApp));
  }
}
