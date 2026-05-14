import 'package:flutter/material.dart';
import 'package:trazabox/constants/app_colors.dart';

// TODO: Integrar tester_red_shared cuando el paquete esté disponible
class MapaCalorScreen extends StatelessWidget {
  const MapaCalorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('Mapa de Calor'),
      ),
      body: const Center(
        child: Text(
          'Módulo Mapa de Calor\nno disponible en esta versión',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white54),
        ),
      ),
    );
  }
}
