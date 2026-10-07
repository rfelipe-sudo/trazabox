import 'package:flutter/material.dart';

import 'package:trazabox/services/app_tecnico_open_service.dart';
import 'package:trazabox/services/sesion_dispositivo_service.dart';

/// Ruta legacy `/app-tecnico`: redirige al flujo directo desde Home (sin pantalla puente).
class AppTecnicoScreen extends StatefulWidget {
  const AppTecnicoScreen({super.key});

  @override
  State<AppTecnicoScreen> createState() => _AppTecnicoScreenState();
}

class _AppTecnicoScreenState extends State<AppTecnicoScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).pop();
      final homeCtx = trazaboxNavigatorKey.currentContext;
      if (homeCtx != null && homeCtx.mounted) {
        AppTecnicoOpenService.instance.openFromHome(homeCtx);
      }
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
