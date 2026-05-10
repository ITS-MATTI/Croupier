import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:google_fonts/google_fonts.dart'; 
import 'dart:async';
import 'dart:math' as math;

// --- COLORES GLOBALES DIRECTAMENTE AQUÍ (SIN CARPETAS) ---
const Color verdeNeon = Color(0xFF3CFF00); 
const Color naranjaTema = Color.fromARGB(255, 255, 136, 0); 
const Color turquesaTema = Color.fromARGB(255, 0, 255, 179); 

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
bool isGuestMode = false;
bool isOfflineGlobal = false; 

// --- EL ERROR ESTABA AQUÍ, FALTABA ESTA LÍNEA DE LA CLASE ---
class FichaPokerIcon extends StatelessWidget {
  final Color color;
  final double size;
  const FichaPokerIcon({super.key, required this.color, this.size = 14});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _FichaPainter(color),
    );
  }
}

class _FichaPainter extends CustomPainter {
  final Color color;
  _FichaPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.12
      ..strokeCap = StrokeCap.square;
    
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width * 0.44;
    final innerRadius = size.width * 0.22;
    
    canvas.drawCircle(center, outerRadius, strokePaint);
    strokePaint.strokeWidth = size.width * 0.08;
    canvas.drawCircle(center, innerRadius, strokePaint);
    canvas.drawCircle(center, size.width * 0.08, fillPaint);
    
    strokePaint.strokeWidth = size.width * 0.1;
    for (int i = 0; i < 8; i++) {
      final double angle = (i * math.pi) / 4;
      final p1 = Offset(
        center.dx + math.cos(angle) * innerRadius,
        center.dy + math.sin(angle) * innerRadius,
      );
      final p2 = Offset(
        center.dx + math.cos(angle) * outerRadius,
        center.dy + math.sin(angle) * outerRadius,
      );
      canvas.drawLine(p1, p2, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class FloatingLogo extends StatelessWidget {
  const FloatingLogo({super.key});
  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 20,
      left: 20,
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.35, 
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/logo.png', width: 70), 
              const SizedBox(height: 4), 
              const Text(
                "BY ANGEL",
                style: TextStyle(
                  color: naranjaTema, 
                  fontWeight: FontWeight.w900,
                  fontSize: 12, 
                  letterSpacing: 1.0, 
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NetworkToggleAction extends StatefulWidget {
  const NetworkToggleAction({super.key});
  @override
  State<NetworkToggleAction> createState() => _NetworkToggleActionState();
}

class _NetworkToggleActionState extends State<NetworkToggleAction> {
  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        isOfflineGlobal ? Icons.wifi_off : Icons.wifi, 
        color: isOfflineGlobal ? Colors.redAccent : verdeNeon
      ),
      tooltip: isOfflineGlobal ? "Modo Offline Activo" : "Modo Online Activo",
      onPressed: () async {
        if (isOfflineGlobal) {
          await FirebaseFirestore.instance.enableNetwork();
          setState(() { isOfflineGlobal = false; });
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Conectado a la Nube (Online)", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, letterSpacing: 1)), backgroundColor: verdeNeon));
        } else {
          await FirebaseFirestore.instance.disableNetwork();
          setState(() { isOfflineGlobal = true; });
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Modo Offline Activo. Guardando localmente...", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1)), backgroundColor: Colors.redAccent));
        }
      },
    );
  }
}

Future<void> _registrarHistorial(String eventoId, String accion) async {
  try {
    await FirebaseFirestore.instance.collection('eventos').doc(eventoId).collection('historial').add({
      'accion': accion, 
      'fecha': DateTime.now()
    });
  } catch (e) { 
    print("Error guardando historial: $e"); 
  }
}

class EventTimerManager {
  static final Map<String, ValueNotifier<int>> times = {};
  static final Map<String, ValueNotifier<bool>> runnings = {};
  static final Map<String, Timer?> timers = {};
  static final Map<String, StreamSubscription?> listeners = {};

  static void initEvent(String eventoId) {
    if (!times.containsKey(eventoId)) {
      times[eventoId] = ValueNotifier<int>(1800); 
      runnings[eventoId] = ValueNotifier<bool>(false);
      
      listeners[eventoId] = FirebaseFirestore.instance.collection('eventos').doc(eventoId).snapshots().listen((doc) {
        if (!doc.exists || doc.data() == null) return;
        var data = doc.data() as Map<String, dynamic>;
        
        bool isRunning = data['timer_running'] ?? false;
        int remainingAtStart = data['timer_remaining'] ?? 1800;
        
        runnings[eventoId]!.value = isRunning;
        timers[eventoId]?.cancel(); 
        
        if (isRunning) {
          Timestamp? startTs = data['timer_start_time'];
          DateTime startTime = startTs != null ? startTs.toDate() : DateTime.now();
          _iniciarConteoLocal(eventoId, startTime, remainingAtStart, data['timer_duration'] ?? 1800);
        } else {
          times[eventoId]!.value = remainingAtStart; 
        }
      });
    }
  }

  static void _iniciarConteoLocal(String eventoId, DateTime startTime, int remainingAtStart, int duration) {
    timers[eventoId]?.cancel();
    timers[eventoId] = Timer.periodic(const Duration(seconds: 1), (timer) {
      int passedSeconds = DateTime.now().difference(startTime).inSeconds;
      int currentRemaining = remainingAtStart - passedSeconds;
      
      if (currentRemaining <= 0) {
        timer.cancel();
        times[eventoId]!.value = duration; 
        
        if (!kIsWeb) FlutterRingtonePlayer().playAlarm(looping: false, volume: 1.0); 
        
        if (!isGuestMode) {
          _proponerRelevoCircularPorEvento(eventoId); 
          FirebaseFirestore.instance.collection('eventos').doc(eventoId).set({
            'timer_running': true,
            'timer_start_time': FieldValue.serverTimestamp(),
            'timer_remaining': duration,
          }, SetOptions(merge: true));
        }
      } else {
        times[eventoId]!.value = currentRemaining;
        if (currentRemaining == 180 && !kIsWeb && !isGuestMode) {
          FlutterRingtonePlayer().playNotification(); 
        }
      }
    });
  }

  static void ajustarReloj(String eventoId, int segundos) async {
    if (isGuestMode) return;
    initEvent(eventoId);
    await FirebaseFirestore.instance.collection('eventos').doc(eventoId).set({
      'timer_running': false,
      'timer_remaining': segundos,
      'timer_duration': segundos,
    }, SetOptions(merge: true));
  }

  static void toggleTimer(String eventoId) async {
    if (isGuestMode) return; 
    initEvent(eventoId);
    
    var doc = await FirebaseFirestore.instance.collection('eventos').doc(eventoId).get();
    var data = doc.data() as Map<String, dynamic>? ?? {};
    
    bool isRunning = data['timer_running'] ?? false;

    if (isRunning) {
      int currentRemaining = times[eventoId]!.value;
      await FirebaseFirestore.instance.collection('eventos').doc(eventoId).set({
        'timer_running': false,
        'timer_remaining': currentRemaining,
      }, SetOptions(merge: true));
    } else {
      int remaining = data['timer_remaining'] ?? data['timer_duration'] ?? 1800;
      if (remaining <= 0) remaining = data['timer_duration'] ?? 1800;
      await FirebaseFirestore.instance.collection('eventos').doc(eventoId).set({
        'timer_running': true,
        'timer_start_time': FieldValue.serverTimestamp(),
        'timer_remaining': remaining,
        'timer_duration': data['timer_duration'] ?? 1800,
      }, SetOptions(merge: true));
    }
  }
}

Future<void> _proponerRelevoCircularPorEvento(String eventoId) async {
  BuildContext? ctx = navigatorKey.currentContext;
  if (ctx == null) return;
  try {
    var db = FirebaseFirestore.instance;
    var eventoDoc = await db.collection('eventos').doc(eventoId).get();
    String nombreDelEvento = 'Evento';
    List<String> dealersPermitidos = [];

    if (eventoDoc.exists && eventoDoc.data() != null) {
      var data = eventoDoc.data()!;
      nombreDelEvento = data['nombre']?.toString() ?? 'Evento';
      if (data.containsKey('dealers_ids')) dealersPermitidos = List<String>.from(data['dealers_ids']);
    }

    var dealersSnap = await db.collection('Dealers').get();
    var mesasSnap = await db.collection('eventos').doc(eventoId).collection('mesas').orderBy('orden').get();
    if(mesasSnap.docs.isEmpty) mesasSnap = await db.collection('eventos').doc(eventoId).collection('mesas').orderBy('creado').get();
    
    List<Map<String, dynamic>> mesasActivas = [];
    List<String> dealersTrabajandoIds = [];

    for (var mesa in mesasSnap.docs) {
      var d = mesa.data();
      if (d.containsKey('dealer_id') && d['dealer_id'] != null) {
        mesasActivas.add({
          'ref': mesa.reference, 
          'nombreMesa': d['nombre']?.toString() ?? 'Mesa',
          'dealerActualId': d['dealer_id'], 
          'dealerActualApodo': d['dealer_apodo']?.toString() ?? 'Dealer',
          'historial': d['dealers_pasados'] ?? [],
        });
        dealersTrabajandoIds.add(d['dealer_id']);
      }
    }

    if (mesasActivas.isEmpty) {
      _mostrarAlertaGlobal(ctx, "TIEMPO CUMPLIDO - $nombreDelEvento", "No hay dealers activos en este evento para rotar.");
      return;
    }

    List<DocumentSnapshot> poolRoster = dealersSnap.docs.where((d) => dealersPermitidos.contains(d.id)).toList();
    if (poolRoster.isEmpty) {
      _mostrarAlertaGlobal(ctx, "AVISO DE EVENTO", "No hay dealers en el 'Roster' para este evento. Ve a 'Asignar Participantes'.");
      return;
    }

    List<DocumentSnapshot> dealersDescansando = poolRoster.where((d) => !dealersTrabajandoIds.contains(d.id)).toList();
    dealersDescansando.shuffle(); 
    
    List<DocumentSnapshot> workingDealersDocs = [];
    for(var mesa in mesasActivas) {
       var dDoc = poolRoster.firstWhere((d) => d.id == mesa['dealerActualId'], orElse: () => poolRoster.first);
       workingDealersDocs.add(dDoc);
    }
    
    List<DocumentSnapshot> circulo = [...workingDealersDocs, ...dealersDescansando];
    
    if (circulo.length > 1) {
      DocumentSnapshot ultimo = circulo.removeLast();
      circulo.insert(0, ultimo);
    }

    List<Map<String, dynamic>> cambiosProgramados = [];
    String logRotaciones = "";
    String logHistorialBD = "ROTACIÓN MASIVA:\n";

    for (int i = 0; i < mesasActivas.length; i++) {
      var mesaInfo = mesasActivas[i];
      var dealerElegido = circulo[i];
      
      var ndData = dealerElegido.data() as Map<String, dynamic>;
      String nNombre = ndData['nombre']?.toString() ?? 'Crupier';
      String nApodo = ndData['apodo']?.toString() ?? ndData['nombre']?.toString() ?? 'Dealer';
      String nEmoji = ndData['emoji']?.toString() ?? '🤵';
      String nCiudad = ndData['ciudad']?.toString() ?? '';

      List<dynamic> historial = List.from(mesaInfo['historial']);
      historial.add(dealerElegido.id);

      cambiosProgramados.add({
        'ref': mesaInfo['ref'], 'nId': dealerElegido.id, 'nNombre': nNombre, 'nApodo': nApodo, 'nEmoji': nEmoji,
        'nCiudad': nCiudad, 'nHistorial': historial,
      });

      logRotaciones += "🔹 ${mesaInfo['nombreMesa']}:\nSale ${mesaInfo['dealerActualApodo']} ➔ Entra $nApodo\n\n";
      logHistorialBD += "- ${mesaInfo['nombreMesa']}: Entró $nApodo por ${mesaInfo['dealerActualApodo']}\n";
    }

    showDialog(
      context: ctx, barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1D26), 
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: verdeNeon, width: 2)),
          title: const Text("ROTACIÓN CIRCULAR 🔄", style: TextStyle(color: verdeNeon, fontWeight: FontWeight.w800, fontSize: 20, letterSpacing: 1.5), textAlign: TextAlign.center),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Rotación generada. ¿Aplicar cambios?\n(El reloj sigue corriendo)", style: TextStyle(color: naranjaTema, fontWeight: FontWeight.w500), textAlign: TextAlign.center),
                const SizedBox(height: 15),
                Text(logRotaciones, style: const TextStyle(color: naranjaTema, fontSize: 14, height: 1.5, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
              ],
            ),
          ),
          actionsAlignment: MainAxisAlignment.spaceEvenly,
          actions: [
            TextButton(
              onPressed: () {
                if(!kIsWeb) FlutterRingtonePlayer().stop();
                Navigator.pop(context);
              }, 
              child: const Text("NO, ESPERAR", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1))
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: verdeNeon),
              onPressed: () async {
                if(!kIsWeb) FlutterRingtonePlayer().stop();
                for (var c in cambiosProgramados) {
                  await (c['ref'] as DocumentReference).update({
                    'dealer_id': c['nId'], 'dealer_nombre': c['nNombre'], 'dealer_apodo': c['nApodo'], 'dealer_emoji': c['nEmoji'], 'dealer_ciudad': c['nCiudad'], 'dealers_pasados': c['nHistorial'],
                  });
                }
                await _registrarHistorial(eventoId, logHistorialBD);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text("SÍ, CONFIRMAR", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: 1)),
            )
          ],
        );
      },
    );
  } catch (e) { print(e); }
}

void _mostrarAlertaGlobal(BuildContext context, String titulo, String mensaje) {
  showDialog(
    context: context, barrierDismissible: false,
    builder: (context) {
      return AlertDialog(
        backgroundColor: const Color(0xFF1A1D26), 
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: verdeNeon, width: 2)),
        title: Text(titulo, style: const TextStyle(color: verdeNeon, fontWeight: FontWeight.w900, fontSize: 22, letterSpacing: 1.5), textAlign: TextAlign.center),
        content: Text(mensaje, style: const TextStyle(color: naranjaTema, fontSize: 14, height: 1.5, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: verdeNeon),
            onPressed: () {
              if(!kIsWeb) FlutterRingtonePlayer().stop();
              Navigator.pop(context);
            },
            child: const Text("ENTENDIDO", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: 1)),
          )
        ],
      );
    }
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyBzv8_-a-nmU3nwzYYfeXpumRHh-Rqr7Cg", 
        authDomain: "crupier.firebaseapp.com", 
        projectId: "crupier",
        storageBucket: "crupier.firebasestorage.app", 
        messagingSenderId: "17562599107", 
        appId: "1:17562599107:web:9dc13d939059826a4ca4e6", 
        measurementId: "G-5HRB7LZZJM"
      ),
    );
  } else {
    try { await Firebase.initializeApp(); } catch (e) { print("ERROR DE FIREBASE: $e"); }
  }
  runApp(const CroupierProApp());
}

class CroupierProApp extends StatelessWidget {
  const CroupierProApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey, debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B0D13), primaryColor: verdeNeon, appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF0B0D13), elevation: 0),
      ),
      home: const LoginScreen(), 
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  String _errorMsg = "";

  void _normalLogin() {
    if (_userController.text.trim() == "ANGEL" && _passController.text.trim() == "1984") {
      isGuestMode = false;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const MainTabScreen()));
    } else { setState(() { _errorMsg = "Credenciales incorrectas"; }); }
  }

  void _guestLogin() {
    isGuestMode = true; 
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const MainTabScreen()));
  }

  void _showSecretAdminDialog() {
    final TextEditingController secretController = TextEditingController();
    showDialog(
      context: context, 
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1D26), 
          title: const Text("ADMIN ACCESO", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900, letterSpacing: 1)),
          content: TextField(
            controller: secretController, obscureText: true, 
            style: const TextStyle(color: naranjaTema, fontWeight: FontWeight.w600), 
            decoration: InputDecoration(hintText: "Clave secreta...", hintStyle: TextStyle(color: naranjaTema.withOpacity(0.6)))
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCELAR", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () {
                if (secretController.text == "2862175587") {
                  isGuestMode = false;
                  Navigator.pop(ctx); 
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const MainTabScreen()));
                } else {
                  Navigator.pop(ctx);
                  setState(() { _errorMsg = "Acceso denegado"; });
                }
              }, 
              child: const Text("VERIFICAR", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1))
            )
          ],
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onDoubleTap: _showSecretAdminDialog, 
                    child: Column(
                      children: [
                        Container(
                          width: 140, height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle, color: Colors.black45, border: Border.all(color: verdeNeon, width: 3), 
                            image: const DecorationImage(image: AssetImage('assets/LOGO_SIMBOLOS_POKER.png'), fit: BoxFit.contain), 
                            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 15, spreadRadius: 2, offset: Offset(0, 5))]
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text("POKER MANAGER", style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: verdeNeon, letterSpacing: 3), textAlign: TextAlign.center),
                        const SizedBox(height: 5),
                        const Text("TOURNAMENT", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: naranjaTema, letterSpacing: 5), textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                  const SizedBox(height: 50),
                  TextField(controller: _userController, style: const TextStyle(color: naranjaTema, fontWeight: FontWeight.w600), decoration: InputDecoration(labelText: "Usuario", labelStyle: TextStyle(color: naranjaTema.withOpacity(0.6), fontWeight: FontWeight.w500), filled: true, fillColor: Colors.black45, prefixIcon: const Icon(Icons.person, color: verdeNeon), border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none))),
                  const SizedBox(height: 20),
                  TextField(controller: _passController, obscureText: true, style: const TextStyle(color: naranjaTema, fontWeight: FontWeight.w600), decoration: InputDecoration(labelText: "Contraseña", labelStyle: TextStyle(color: naranjaTema.withOpacity(0.6), fontWeight: FontWeight.w500), filled: true, fillColor: Colors.black45, prefixIcon: const Icon(Icons.lock, color: verdeNeon), border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none))),
                  const SizedBox(height: 10),
                  _errorMsg.isNotEmpty ? Text(_errorMsg, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w800, letterSpacing: 1)) : const SizedBox.shrink(),
                  const SizedBox(height: 30),
                  SizedBox(width: double.infinity, height: 50, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: verdeNeon, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), onPressed: _normalLogin, child: const Text("ENTRAR", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 2)))),
                  const SizedBox(height: 20),
                  TextButton(onPressed: _guestLogin, child: const Text("Ingresar como invitado", style: TextStyle(color: naranjaTema, fontSize: 16, decoration: TextDecoration.underline, fontWeight: FontWeight.w500))),
                ],
              ),
            ),
          ),
          const FloatingLogo(), 
        ],
      ),
    );
  }
}

class EventStatsBanner extends StatelessWidget {
  final String eventoId;
  const EventStatsBanner({super.key, required this.eventoId});

  Stream<Map<String, int>> _getEstadisticasDelEvento() async* {
    yield* FirebaseFirestore.instance.collection('eventos').doc(eventoId).snapshots().asyncMap((eventoSnap) async {
      var mesasSnap = await FirebaseFirestore.instance.collection('eventos').doc(eventoId).collection('mesas').get();
      int dealersEnUso = 0; int jugadoresSentados = 0; int totalDealersRoster = 0; int totalJugadoresRoster = 0;

      if (eventoSnap.exists && eventoSnap.data() != null) {
        var data = eventoSnap.data()!;
        if (data.containsKey('dealers_ids')) totalDealersRoster = (data['dealers_ids'] as List).length;
        if (data.containsKey('jugadores_ids')) totalJugadoresRoster = (data['jugadores_ids'] as List).length;
      }

      for (var mesa in mesasSnap.docs) {
        if (mesa.data().containsKey('dealer_id') && mesa.data()['dealer_id'] != null) dealersEnUso++;
        var jugadoresSnap = await mesa.reference.collection('jugadores_activos').get();
        jugadoresSentados += jugadoresSnap.docs.length;
      }

      return {'dealers_activos': dealersEnUso, 'jugadores_sentados': jugadoresSentados, 'dealers_roster': totalDealersRoster, 'jugadores_roster': totalJugadoresRoster};
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity, decoration: BoxDecoration(color: const Color(0xFF151921), border: Border(bottom: BorderSide(color: verdeNeon.withOpacity(0.3), width: 1))), padding: const EdgeInsets.symmetric(vertical: 10),
      child: StreamBuilder<Map<String, int>>(
        stream: _getEstadisticasDelEvento(),
        builder: (context, snapshot) {
          int jSentados = snapshot.hasData ? snapshot.data!['jugadores_sentados']! : 0;
          int jRoster = snapshot.hasData ? snapshot.data!['jugadores_roster']! : 0;
          int dActivos = snapshot.hasData ? snapshot.data!['dealers_activos']! : 0;
          int dRoster = snapshot.hasData ? snapshot.data!['dealers_roster']! : 0;

          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Row(children: [const Icon(Icons.event_seat, color: verdeNeon, size: 20), const SizedBox(width: 8), const Text("JUGADORES: ", style: TextStyle(color: naranjaTema, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1)), Text("$jSentados / $jRoster", style: const TextStyle(color: verdeNeon, fontWeight: FontWeight.w900, fontSize: 14))]),
              Container(width: 1, height: 25, color: verdeNeon.withOpacity(0.3)),
              Row(children: [const Icon(Icons.badge, color: verdeNeon, size: 20), const SizedBox(width: 8), const Text("DEALERS: ", style: TextStyle(color: naranjaTema, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1)), Text("$dActivos / $dRoster", style: const TextStyle(color: verdeNeon, fontWeight: FontWeight.w900, fontSize: 14))]),
            ],
          );
        },
      ),
    );
  }
}

class EventTimerBanner extends StatelessWidget {
  final String eventoId;
  const EventTimerBanner({super.key, required this.eventoId});

  void _abrirAjustesReloj(BuildContext context) {
    if (isGuestMode) return; 
    EventTimerManager.initEvent(eventoId);
    final minC = TextEditingController(text: (EventTimerManager.times[eventoId]!.value ~/ 60).toString());
    final secC = TextEditingController(text: (EventTimerManager.times[eventoId]!.value % 60).toString());

    showDialog(
      context: context, 
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1D26), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: verdeNeon, width: 2)),
          title: const Text("⚙️ Ajustar Reloj", style: TextStyle(color: verdeNeon, fontWeight: FontWeight.w800, letterSpacing: 1), textAlign: TextAlign.center),
          content: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(width: 70, child: TextField(controller: minC, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: "Min", labelStyle: TextStyle(color: naranjaTema.withOpacity(0.6))), style: const TextStyle(fontSize: 30, color: naranjaTema, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text(":", style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: naranjaTema))),
              SizedBox(width: 70, child: TextField(controller: secC, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: "Seg", labelStyle: TextStyle(color: naranjaTema.withOpacity(0.6))), style: const TextStyle(fontSize: 30, color: naranjaTema, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
            ],
          ),
          actionsAlignment: MainAxisAlignment.spaceEvenly,
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCELAR", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: verdeNeon),
              onPressed: () {
                int m = int.tryParse(minC.text) ?? 0; int s = int.tryParse(secC.text) ?? 0;
                EventTimerManager.ajustarReloj(eventoId, (m * 60) + s);
                Navigator.pop(context);
              }, child: const Text("APLICAR", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: 1)),
            ),
          ],
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    EventTimerManager.initEvent(eventoId);
    return ValueListenableBuilder<bool>(
      valueListenable: EventTimerManager.runnings[eventoId]!,
      builder: (context, running, child) {
        return Container(
          width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(color: running ? const Color(0xFF0E4D21) : Colors.black, border: const Border(top: BorderSide(color: verdeNeon, width: 2))),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              !isGuestMode ? IconButton(icon: Icon(running ? Icons.pause_circle_filled : Icons.play_circle_fill, color: verdeNeon, size: 35), onPressed: () => EventTimerManager.toggleTimer(eventoId)) : const SizedBox.shrink(),
              const SizedBox(width: 15),
              GestureDetector(
                onTap: () => _abrirAjustesReloj(context),
                child: ValueListenableBuilder<int>(
                  valueListenable: EventTimerManager.times[eventoId]!,
                  builder: (context, time, child) {
                    String m = (time ~/ 60).toString().padLeft(2, '0'); String s = (time % 60).toString().padLeft(2, '0');
                    Color colorReloj = (time <= 180 && time > 0) ? Colors.redAccent : naranjaTema;
                    return Text("$m:$s", style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: colorReloj, fontFamily: 'monospace', letterSpacing: 4));
                  },
                ),
              ),
              const SizedBox(width: 15),
            ],
          ),
        );
      }
    );
  }
}

class MainTabScreen extends StatefulWidget {
  const MainTabScreen({super.key});
  @override
  State<MainTabScreen> createState() => _MainTabScreenState();
}
class _MainTabScreenState extends State<MainTabScreen> {
  int _currentIndex = 0;
  final List<Widget> _pantallas = [const EventosScreen(), const JugadoresScreen(), const DealersScreen()];

  @override
  Widget build(BuildContext context) {
    if (isGuestMode) {
      return const Scaffold(body: SafeArea(child: EventosScreen()));
    }
    return Scaffold(
      body: SafeArea(child: _pantallas[_currentIndex]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex, selectedItemColor: verdeNeon, unselectedItemColor: naranjaTema.withOpacity(0.6), backgroundColor: const Color(0xFF1A1D26), type: BottomNavigationBarType.fixed,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.casino), label: "Eventos"),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: "Jugadores"),
          BottomNavigationBarItem(icon: Icon(Icons.style), label: "Dealers"),
        ],
      ),
    );
  }
}

class JugadoresScreen extends StatefulWidget {
  const JugadoresScreen({super.key});
  @override
  State<JugadoresScreen> createState() => _JugadoresScreenState();
}

class _JugadoresScreenState extends State<JugadoresScreen> {
  String _searchQuery = "";

  void _dialogFormJugador(BuildContext context, DocumentSnapshot? doc) {
    if (isGuestMode) return; 
    bool isEdit = doc != null; Map<String, dynamic> data = isEdit ? doc.data() as Map<String, dynamic> : {};
    
    final cedulaC = TextEditingController(text: data['cedula']?.toString() ?? "");
    final nombreC = TextEditingController(text: data['nombre']?.toString() ?? "");
    final apodoC = TextEditingController(text: data['apodo']?.toString() ?? "");
    final fichasC = TextEditingController(text: data['fichas']?.toString() ?? "0");
    final ciudadC = TextEditingController(text: data['ciudad']?.toString() ?? "");
    final celularC = TextEditingController(text: data['celular']?.toString() ?? "");
    final emojiC = TextEditingController(text: data['emoji']?.toString() ?? "👤");
    final clubC = TextEditingController(text: data['club']?.toString() ?? ""); 

    showDialog(
      context: context, 
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1D26), 
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: verdeNeon)),
          title: Text(isEdit ? "Editar Jugador" : "Nuevo Jugador", style: const TextStyle(color: verdeNeon, fontWeight: FontWeight.w800, letterSpacing: 1)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min, 
              children: [
                TextField(controller: cedulaC, decoration: InputDecoration(labelText: "Cédula", labelStyle: TextStyle(color: turquesaTema.withOpacity(0.8))), keyboardType: TextInputType.number, style: const TextStyle(color: turquesaTema, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                TextField(controller: emojiC, decoration: const InputDecoration(labelText: "Emoji (Ej: 🤠, 👽)", labelStyle: TextStyle(color: turquesaTema)), style: const TextStyle(color: naranjaTema, fontSize: 20)),
                const SizedBox(height: 10),
                TextField(controller: nombreC, decoration: InputDecoration(labelText: "Nombre Real", labelStyle: TextStyle(color: naranjaTema.withOpacity(0.6))), style: const TextStyle(color: naranjaTema, fontWeight: FontWeight.w600)),
                TextField(controller: apodoC, decoration: InputDecoration(labelText: "Apodo en Mesa", labelStyle: TextStyle(color: naranjaTema.withOpacity(0.6))), style: const TextStyle(color: naranjaTema, fontWeight: FontWeight.w600)),
                TextField(controller: clubC, decoration: InputDecoration(labelText: "Club / Equipo", labelStyle: TextStyle(color: turquesaTema.withOpacity(0.8))), style: const TextStyle(color: turquesaTema, fontWeight: FontWeight.w800)), 
                TextField(controller: celularC, decoration: InputDecoration(labelText: "Celular (Privado)", labelStyle: TextStyle(color: naranjaTema.withOpacity(0.6))), keyboardType: TextInputType.phone, style: const TextStyle(color: naranjaTema, fontWeight: FontWeight.w600)),
                TextField(controller: ciudadC, decoration: InputDecoration(labelText: "Ciudad / País", labelStyle: TextStyle(color: naranjaTema.withOpacity(0.6))), style: const TextStyle(color: naranjaTema, fontWeight: FontWeight.w600)),
                TextField(controller: fichasC, decoration: InputDecoration(labelText: "Puntos Base", labelStyle: TextStyle(color: naranjaTema.withOpacity(0.6))), keyboardType: TextInputType.number, style: const TextStyle(color: naranjaTema, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCELAR", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: verdeNeon),
              onPressed: () {
                var payload = {
                  'cedula': cedulaC.text.trim(),
                  'nombre': nombreC.text.trim(), 'apodo': apodoC.text.trim().isEmpty ? nombreC.text.trim() : apodoC.text.trim(),
                  'fichas': int.tryParse(fichasC.text) ?? 0, 'ciudad': ciudadC.text.trim(), 'celular': celularC.text.trim(),
                  'emoji': emojiC.text.trim().isEmpty ? "👤" : emojiC.text.trim(),
                  'club': clubC.text.trim().toUpperCase(), 
                };
                if (isEdit) doc!.reference.update(payload); else FirebaseFirestore.instance.collection('Jugadores').add(payload);
                Navigator.pop(context);
              }, 
              child: const Text("GUARDAR", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900)),
            ),
          ],
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("BASE DE DATOS: JUGADORES", style: TextStyle(color: verdeNeon, fontWeight: FontWeight.w900, letterSpacing: 1.5)), centerTitle: true,
        actions: [
          const NetworkToggleAction(),
          IconButton(icon: const Icon(Icons.refresh), tooltip: "Sincronizar", onPressed: () { setState(() {}); }),
          IconButton(icon: const Icon(Icons.logout, color: Colors.redAccent, size: 22), tooltip: "Cerrar Sesión", onPressed: () { isGuestMode = false; Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen())); }),
        ],
      ),
      floatingActionButton: isGuestMode ? null : FloatingActionButton(backgroundColor: verdeNeon, onPressed: () => _dialogFormJugador(context, null), child: const Icon(Icons.person_add, color: Colors.black)),
      body: Stack(
        children: [
          StreamBuilder(
            stream: FirebaseFirestore.instance.collection('Jugadores').snapshots(),
            builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: verdeNeon));
              int totalRegistrados = snapshot.data!.docs.length;
              var filteredDocs = snapshot.data!.docs.where((doc) {
                var data = doc.data() as Map<String, dynamic>;
                String n = (data['nombre']?.toString() ?? '').toLowerCase(); String a = (data['apodo']?.toString() ?? '').toLowerCase();
                String c = (data['club']?.toString() ?? '').toLowerCase();
                String ced = (data['cedula']?.toString() ?? '').toLowerCase();
                return n.contains(_searchQuery) || a.contains(_searchQuery) || c.contains(_searchQuery) || ced.contains(_searchQuery);
              }).toList();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(padding: const EdgeInsets.all(10), child: TextField(style: const TextStyle(color: naranjaTema, fontWeight: FontWeight.w500), decoration: InputDecoration(prefixIcon: const Icon(Icons.search, color: verdeNeon), hintText: "Buscar jugador, club o cédula...", filled: true, fillColor: Colors.black45, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)), onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()))),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 15), child: Text("Total registrados en BD: $totalRegistrados", style: const TextStyle(color: turquesaTema, fontWeight: FontWeight.bold))),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.only(left: 15, right: 15, bottom: 90), 
                      itemCount: filteredDocs.length,
                      itemBuilder: (context, index) {
                        var doc = filteredDocs[index];
                        var data = doc.data() as Map<String, dynamic>? ?? {};
                        String club = data['club']?.toString().trim() ?? '';
                        return Card(
                          color: Colors.black45, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: verdeNeon.withOpacity(0.3))),
                          child: ListTile(
                            leading: CircleAvatar(backgroundColor: verdeNeon.withOpacity(0.2), child: Text(data['emoji']?.toString() ?? '👤', style: const TextStyle(fontSize: 20))),
                            title: Text(data['nombre']?.toString() ?? 'Sin Nombre', style: const TextStyle(fontWeight: FontWeight.w800, color: naranjaTema, letterSpacing: 0.5)),
                            subtitle: RichText(
                              text: TextSpan(
                                style: const TextStyle(fontSize: 14, height: 1.5),
                                children: [
                                  TextSpan(text: "Apodo: ${data['apodo']?.toString() ?? '-'}\n", style: const TextStyle(color: turquesaTema, fontWeight: FontWeight.w600)),
                                  club.isNotEmpty ? TextSpan(text: "Club: $club\n", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w800)) : const TextSpan(),
                                  TextSpan(text: "Puntos: ${data['fichas']?.toString() ?? '0'} | Cel: ${data['celular']?.toString() ?? '-'} | Ciu: ${data['ciudad']?.toString() ?? '-'}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                                ],
                              ),
                            ),
                            isThreeLine: true,
                            trailing: isGuestMode ? null : Row(
                              mainAxisSize: MainAxisSize.min, 
                              children: [
                                IconButton(icon: const Icon(Icons.edit, color: naranjaTema), onPressed: () => _dialogFormJugador(context, doc)),
                                IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent), onPressed: () => doc.reference.delete()),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
          const FloatingLogo(), // MARCA DE AGUA
        ],
      ),
    );
  }
}

class DealersScreen extends StatefulWidget {
  const DealersScreen({super.key});
  @override
  State<DealersScreen> createState() => _DealersScreenState();
}

class _DealersScreenState extends State<DealersScreen> {
  String _searchQuery = "";

  void _dialogFormDealer(BuildContext context, DocumentSnapshot? doc) {
    if (isGuestMode) return;
    bool isEdit = doc != null; Map<String, dynamic> data = isEdit ? doc.data() as Map<String, dynamic> : {};
    
    final nombreC = TextEditingController(text: isEdit ? data['nombre']?.toString() : "");
    final apodoC = TextEditingController(text: isEdit ? data['apodo']?.toString() : "");
    final emojiC = TextEditingController(text: isEdit && data.containsKey('emoji') ? data['emoji'].toString() : "🤵");
    final celularC = TextEditingController(text: isEdit && data.containsKey('celular') ? data['celular'].toString() : "");
    final ciudadC = TextEditingController(text: isEdit && data.containsKey('ciudad') ? data['ciudad'].toString() : "");

    showDialog(
      context: context, 
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1D26), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: verdeNeon)),
          title: Text(isEdit ? "Editar Dealer" : "Registrar Dealer", style: const TextStyle(color: verdeNeon, fontWeight: FontWeight.w800, letterSpacing: 1)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min, 
              children: [
                Row(
                  children: [
                    ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: verdeNeon.withOpacity(0.1)), child: const Text("🤵", style: TextStyle(fontSize: 24)), onPressed: () => emojiC.text = "🤵"),
                    const SizedBox(width: 5),
                    ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: verdeNeon.withOpacity(0.1)), child: const Text("👩‍💼", style: TextStyle(fontSize: 24)), onPressed: () => emojiC.text = "👩‍💼"),
                    const SizedBox(width: 10),
                    Expanded(child: TextField(controller: emojiC, decoration: const InputDecoration(labelText: "Otro Emoji", labelStyle: TextStyle(color: turquesaTema, fontWeight: FontWeight.w600)), style: const TextStyle(color: naranjaTema, fontSize: 20))),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(controller: nombreC, decoration: InputDecoration(labelText: "Nombre del Crupier", labelStyle: TextStyle(color: naranjaTema.withOpacity(0.6))), style: const TextStyle(color: naranjaTema, fontWeight: FontWeight.w600)),
                TextField(controller: apodoC, decoration: InputDecoration(labelText: "Apodo", labelStyle: TextStyle(color: naranjaTema.withOpacity(0.6))), style: const TextStyle(color: naranjaTema, fontWeight: FontWeight.w600)),
                TextField(controller: celularC, decoration: InputDecoration(labelText: "Celular (Privado)", labelStyle: TextStyle(color: naranjaTema.withOpacity(0.6))), keyboardType: TextInputType.phone, style: const TextStyle(color: naranjaTema, fontWeight: FontWeight.w600)),
                TextField(controller: ciudadC, decoration: InputDecoration(labelText: "Ciudad / País", labelStyle: TextStyle(color: naranjaTema.withOpacity(0.6))), style: const TextStyle(color: naranjaTema, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCELAR", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: verdeNeon),
              onPressed: () {
                var payload = {
                  'nombre': nombreC.text.trim().isEmpty ? "Sin Nombre" : nombreC.text.trim(), 'apodo': apodoC.text.trim().isEmpty ? nombreC.text.trim() : apodoC.text.trim(),
                  'emoji': emojiC.text.trim().isEmpty ? "🤵" : emojiC.text.trim(), 'celular': celularC.text.trim(), 'ciudad': ciudadC.text.trim(),
                };
                if(isEdit) doc!.reference.update(payload); else FirebaseFirestore.instance.collection('Dealers').add(payload);
                Navigator.pop(context);
              }, child: const Text("GUARDAR", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900)),
            ),
          ],
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("BASE DE DATOS: DEALERS", style: TextStyle(color: verdeNeon, fontWeight: FontWeight.w900, letterSpacing: 1.5)), centerTitle: true,
        actions: [
          const NetworkToggleAction(),
          IconButton(icon: const Icon(Icons.refresh), tooltip: "Sincronizar y Refrescar", onPressed: () { setState(() {}); }),
          IconButton(icon: const Icon(Icons.logout, color: Colors.redAccent, size: 22), onPressed: () { isGuestMode = false; Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen())); }),
        ],
      ),
      floatingActionButton: isGuestMode ? null : FloatingActionButton(backgroundColor: verdeNeon, onPressed: () => _dialogFormDealer(context, null), child: const Icon(Icons.add_reaction, color: Colors.black)),
      body: Stack(
        children: [
          StreamBuilder(
            stream: FirebaseFirestore.instance.collection('Dealers').snapshots(),
            builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: verdeNeon));
              int totalRegistrados = snapshot.data!.docs.length;
              var filteredDocs = snapshot.data!.docs.where((doc) {
                var data = doc.data() as Map<String, dynamic>;
                String n = (data['nombre']?.toString() ?? '').toLowerCase(); String a = (data['apodo']?.toString() ?? '').toLowerCase();
                return n.contains(_searchQuery) || a.contains(_searchQuery);
              }).toList();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(padding: const EdgeInsets.all(10), child: TextField(style: const TextStyle(color: naranjaTema, fontWeight: FontWeight.w500), decoration: InputDecoration(prefixIcon: const Icon(Icons.search, color: verdeNeon), hintText: "Buscar dealer...", filled: true, fillColor: Colors.black45, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)), onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()))),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 15), child: Text("Total registrados en BD: $totalRegistrados", style: const TextStyle(color: turquesaTema, fontWeight: FontWeight.bold))),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.only(left: 15, right: 15, bottom: 90),
                      itemCount: filteredDocs.length,
                      itemBuilder: (context, index) {
                        var doc = filteredDocs[index];
                        var data = doc.data() as Map<String, dynamic>? ?? {};
                        return Card(
                          color: Colors.black45, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: verdeNeon.withOpacity(0.3))),
                          child: ListTile(
                            leading: CircleAvatar(backgroundColor: turquesaTema.withOpacity(0.15), child: Text(data['emoji']?.toString() ?? '🤵', style: const TextStyle(fontSize: 20))),
                            title: Text(data['nombre']?.toString() ?? 'Crupier', style: const TextStyle(fontWeight: FontWeight.w800, color: naranjaTema, letterSpacing: 0.5)),
                            subtitle: RichText(
                              text: TextSpan(
                                style: const TextStyle(fontSize: 14, height: 1.5),
                                children: [
                                  TextSpan(text: "Apodo: ${data['apodo']?.toString() ?? '-'}\n", style: const TextStyle(color: turquesaTema, fontWeight: FontWeight.w600)),
                                  TextSpan(text: "Cel: ${data['celular']?.toString() ?? '-'} | Ciu/País: ${data['ciudad']?.toString() ?? '-'}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                                ],
                              ),
                            ),
                            isThreeLine: true,
                            trailing: isGuestMode ? null : Row(
                              mainAxisSize: MainAxisSize.min, 
                              children: [
                                IconButton(icon: const Icon(Icons.edit, color: naranjaTema), onPressed: () => _dialogFormDealer(context, doc)),
                                IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent), onPressed: () => doc.reference.delete()),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
          const FloatingLogo(), // MARCA DE AGUA EN DEALERS
        ],
      ),
    );
  }
}

class EventosScreen extends StatefulWidget {
  const EventosScreen({super.key});
  @override
  State<EventosScreen> createState() => _EventosScreenState();
}
class _EventosScreenState extends State<EventosScreen> {
  String _searchQuery = "";

  void _dialogFormEvento(BuildContext context, {DocumentSnapshot? doc}) {
    bool isEdit = doc != null;
    final c = TextEditingController(text: isEdit ? doc.data().toString().contains('nombre') ? (doc.data() as Map)['nombre'] : "" : "");
    showDialog(
      context: context, 
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D26), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: verdeNeon)),
        title: Text(isEdit ? "Editar Nombre" : "Nuevo Evento", style: const TextStyle(color: verdeNeon, fontWeight: FontWeight.w800, letterSpacing: 1)),
        content: TextField(controller: c, style: const TextStyle(color: naranjaTema, fontWeight: FontWeight.w600), decoration: InputDecoration(hintText: "Nombre del Torneo", hintStyle: TextStyle(color: naranjaTema.withOpacity(0.6)))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCELAR", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: verdeNeon),
            onPressed: () {
              if(c.text.isNotEmpty) {
                if (isEdit) doc!.reference.update({'nombre': c.text.trim()});
                else FirebaseFirestore.instance.collection('eventos').add({'nombre': c.text.trim(), 'creado': DateTime.now(), 'jugadores_ids': [], 'dealers_ids': [], 'visible_invitados': false});
              }
              Navigator.pop(context);
            }, child: const Text("GUARDAR", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold))
          )
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    double anchoPantalla = MediaQuery.of(context).size.width;
    int numColumnas = anchoPantalla > 800 ? 3 : (anchoPantalla > 500 ? 2 : 1);

    return Scaffold(
      appBar: AppBar(
        title: const Text("SELECCIONA UN EVENTO", style: TextStyle(color: verdeNeon, fontWeight: FontWeight.w900, letterSpacing: 1.5)), centerTitle: true, 
        actions: [
          const NetworkToggleAction(),
          IconButton(icon: const Icon(Icons.refresh), tooltip: "Sincronizar y Refrescar", onPressed: () { setState(() {}); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("🔄 Pantalla actualizada y sincronizada", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), backgroundColor: Colors.green)); }),
          IconButton(icon: const Icon(Icons.logout, color: Colors.redAccent, size: 22), onPressed: () { isGuestMode = false; Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen())); }),
        ]
      ),
      body: Stack(
        children: [
          StreamBuilder(
            stream: FirebaseFirestore.instance.collection('eventos').orderBy('creado', descending: true).snapshots(),
            builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: verdeNeon));
              
              var filteredDocs = snapshot.data!.docs.where((doc) {
                var data = doc.data() as Map<String, dynamic>;
                bool isVisible = data['visible_invitados'] ?? false;
                if (isGuestMode && !isVisible) return false; 
                return (data['nombre']?.toString() ?? '').toLowerCase().contains(_searchQuery);
              }).toList();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(padding: const EdgeInsets.all(10), child: TextField(style: const TextStyle(color: naranjaTema, fontWeight: FontWeight.w500), decoration: InputDecoration(prefixIcon: const Icon(Icons.search, color: verdeNeon), hintText: "Buscar torneo o evento...", filled: true, fillColor: Colors.black45, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)), onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()))),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 15), child: Text("Eventos visibles: ${filteredDocs.length}", style: const TextStyle(color: turquesaTema, fontWeight: FontWeight.bold))),
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.only(bottom: 80, left: 15, right: 15, top: 10),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: numColumnas, childAspectRatio: 2.0, crossAxisSpacing: 15, mainAxisSpacing: 15),
                      itemCount: isGuestMode ? filteredDocs.length : filteredDocs.length + 1,
                      itemBuilder: (context, index) {
                        if (index == filteredDocs.length) {
                          return InkWell(
                            onTap: () => _dialogFormEvento(context, doc: null),
                            child: Container(decoration: BoxDecoration(color: verdeNeon.withOpacity(0.15), border: Border.all(color: verdeNeon), borderRadius: BorderRadius.circular(15)), child: const Icon(Icons.add, color: verdeNeon, size: 40)),
                          );
                        }
                        var doc = filteredDocs[index];
                        var data = doc.data() as Map<String, dynamic>? ?? {};
                        bool isVisible = data['visible_invitados'] ?? false;

                        return Card(
                          color: Colors.black45, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: verdeNeon, width: 1)),
                          child: Stack(
                            children: [
                              InkWell(
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => MesasScreen(eventoId: doc.id, nombreEvento: data['nombre']?.toString() ?? 'Evento'))),
                                child: Center(child: Text(data['nombre']?.toString() ?? 'Evento', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: naranjaTema, letterSpacing: 1))),
                              ),
                              !isGuestMode ? Positioned(top: 0, right: 0, child: Row(
                                children: [
                                  IconButton(
                                    icon: Icon(isVisible ? Icons.visibility : Icons.visibility_off, color: isVisible ? verdeNeon : Colors.grey, size: 20), 
                                    tooltip: isVisible ? "Visible para invitados" : "Oculto para invitados",
                                    onPressed: () => doc.reference.update({'visible_invitados': !isVisible})
                                  ),
                                  // --- AQUÍ ESTÁ EL BOTÓN DE RELOJ DIRECTOR ---
                                  IconButton(
                                    icon: const Icon(Icons.tv, color: Colors.amber, size: 20),
                                    tooltip: "Reloj Director",
                                    onPressed: () {
                                      Navigator.push(context, MaterialPageRoute(builder: (context) => RelojDirectorScreen(eventoId: doc.id, nombreEvento: data['nombre']?.toString() ?? 'Evento')));
                                    }
                                  ),
                                  IconButton(icon: const Icon(Icons.edit, color: turquesaTema, size: 20), onPressed: () => _dialogFormEvento(context, doc: doc)),
                                  IconButton(icon: const Icon(Icons.cancel, color: Colors.redAccent, size: 20), onPressed: () => doc.reference.delete()),
                                ],
                              )) : const SizedBox.shrink()
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
          const FloatingLogo(),
        ],
      ),
    );
  }
}

class HistorialEventoScreen extends StatelessWidget {
  final String eventoId; final String nombreEvento;
  const HistorialEventoScreen({super.key, required this.eventoId, required this.nombreEvento});

  void _borrarTodoElHistorial(BuildContext context) {
    showDialog(
      context: context, 
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1D26), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: Colors.redAccent)),
          title: const Text("⚠️ BORRAR HISTORIAL", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900, letterSpacing: 1)),
          content: const Text("¿Estás completamente seguro de que deseas eliminar TODOS los registros de este evento?", style: TextStyle(color: naranjaTema, fontWeight: FontWeight.w600)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCELAR", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () async {
                var snap = await FirebaseFirestore.instance.collection('eventos').doc(eventoId).collection('historial').get();
                for (var doc in snap.docs) { await doc.reference.delete(); }
                if (ctx.mounted) Navigator.pop(ctx);
              }, child: const Text("SÍ, BORRAR TODO", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900))
            )
          ],
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Historial: $nombreEvento", style: const TextStyle(color: verdeNeon, fontWeight: FontWeight.w900, letterSpacing: 1)), backgroundColor: const Color(0xFF0B0D13),
        actions: [
          !isGuestMode ? IconButton(icon: const Icon(Icons.delete_sweep, color: Colors.redAccent, size: 28), tooltip: "Borrar todo el historial", onPressed: () => _borrarTodoElHistorial(context)) : const SizedBox.shrink()
        ],
      ),
      body: StreamBuilder(
        stream: FirebaseFirestore.instance.collection('eventos').doc(eventoId).collection('historial').orderBy('fecha', descending: true).snapshots(),
        builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: verdeNeon));
          if (snapshot.data!.docs.isEmpty) return const Center(child: Text("Aún no hay registros en este evento.", style: TextStyle(color: naranjaTema, fontWeight: FontWeight.w600)));

          return ListView.builder(
            padding: const EdgeInsets.all(15),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              var doc = snapshot.data!.docs[index];
              var data = doc.data() as Map<String, dynamic>;
              DateTime fecha = (data['fecha'] as Timestamp).toDate();
              return Card(
                color: Colors.black45, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: verdeNeon.withOpacity(0.3))),
                child: ListTile(
                  leading: const Icon(Icons.history, color: turquesaTema),
                  title: Text(data['accion']?.toString() ?? '', style: const TextStyle(color: naranjaTema, fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: Text("${fecha.hour}:${fecha.minute.toString().padLeft(2, '0')}", style: TextStyle(color: naranjaTema.withOpacity(0.6), fontSize: 11, fontWeight: FontWeight.w500)),
                  trailing: isGuestMode ? null : IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent, size: 18), onPressed: () => doc.reference.delete()),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class EventRosterScreen extends StatefulWidget {
  final String eventoId; final String nombreEvento;
  const EventRosterScreen({super.key, required this.eventoId, required this.nombreEvento});
  @override
  State<EventRosterScreen> createState() => _EventRosterScreenState();
}
class _EventRosterScreenState extends State<EventRosterScreen> {
  List<String> _jugadoresSeleccionados = []; List<String> _dealersSeleccionados = []; String _searchQuery = "";

  @override
  void initState() { super.initState(); _cargarRoster(); }

  Future<void> _cargarRoster() async {
    var doc = await FirebaseFirestore.instance.collection('eventos').doc(widget.eventoId).get();
    var data = doc.data() as Map<String, dynamic>? ?? {};
    setState(() {
      if (data.containsKey('jugadores_ids')) _jugadoresSeleccionados = List<String>.from(data['jugadores_ids']);
      if (data.containsKey('dealers_ids')) _dealersSeleccionados = List<String>.from(data['dealers_ids']);
    });
  }

  Future<void> _guardarRoster() async {
    await FirebaseFirestore.instance.collection('eventos').doc(widget.eventoId).update({'jugadores_ids': _jugadoresSeleccionados, 'dealers_ids': _dealersSeleccionados});
    if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Participantes guardados exitosamente", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), backgroundColor: verdeNeon)); Navigator.pop(context); }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text("Asignar: ${widget.nombreEvento}", style: const TextStyle(color: verdeNeon, fontWeight: FontWeight.w900)),
          bottom: const TabBar(indicatorColor: verdeNeon, labelColor: verdeNeon, unselectedLabelColor: Colors.grey, labelStyle: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1), tabs: [Tab(text: "JUGADORES"), Tab(text: "DEALERS")]),
        ),
        floatingActionButton: FloatingActionButton.extended(backgroundColor: verdeNeon, onPressed: _guardarRoster, label: const Text("GUARDAR ROSTER", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: 1)), icon: const Icon(Icons.save, color: Colors.black)),
        body: Column(
          children: [
            Padding(padding: const EdgeInsets.all(10), child: TextField(style: const TextStyle(color: naranjaTema, fontWeight: FontWeight.w600), decoration: InputDecoration(prefixIcon: const Icon(Icons.search, color: verdeNeon), hintText: "Buscar por nombre o apodo...", filled: true, fillColor: Colors.black45, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)), onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()))),
            Expanded(
              child: TabBarView(
                children: [
                  StreamBuilder(
                    stream: FirebaseFirestore.instance.collection('Jugadores').snapshots(),
                    builder: (context, AsyncSnapshot<QuerySnapshot> snap) {
                      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                      var filtrados = snap.data!.docs.where((doc) {
                        var d = doc.data() as Map<String, dynamic>;
                        return (d['nombre']?.toString() ?? '').toLowerCase().contains(_searchQuery) || (d['apodo']?.toString() ?? '').toLowerCase().contains(_searchQuery);
                      }).toList();
                      return ListView.builder(
                        padding: const EdgeInsets.only(bottom: 90), 
                        itemCount: filtrados.length,
                        itemBuilder: (context, i) {
                          var doc = filtrados[i]; var data = doc.data() as Map<String, dynamic>;
                          String clubInfo = data.containsKey('club') && data['club'] != null && data['club'].toString().trim().isNotEmpty ? data['club'].toString().trim() : 'Sin Club';
                          String ciuInfo = data.containsKey('ciudad') && data['ciudad'] != null && data['ciudad'].toString().trim().isNotEmpty ? data['ciudad'].toString().trim() : 'Sin Ciudad';
                          return CheckboxListTile(
                            activeColor: verdeNeon, checkColor: Colors.black, 
                            title: Text(data['nombre']?.toString() ?? 'Socio', style: const TextStyle(color: naranjaTema, fontWeight: FontWeight.w800, letterSpacing: 0.5)), 
                            subtitle: Text("${data['apodo'] ?? ''} | Pts: ${data['fichas'] ?? 0}\n🛡️ $clubInfo | 📍 $ciuInfo", style: const TextStyle(color: turquesaTema, fontWeight: FontWeight.w600)),
                            value: _jugadoresSeleccionados.contains(doc.id),
                            onChanged: (bool? val) { setState(() { if (val == true) _jugadoresSeleccionados.add(doc.id); else _jugadoresSeleccionados.remove(doc.id); }); },
                          );
                        },
                      );
                    },
                  ),
                  StreamBuilder(
                    stream: FirebaseFirestore.instance.collection('Dealers').snapshots(),
                    builder: (context, AsyncSnapshot<QuerySnapshot> snap) {
                      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                      var filtrados = snap.data!.docs.where((doc) {
                        var d = doc.data() as Map<String, dynamic>;
                        return (d['nombre']?.toString() ?? '').toLowerCase().contains(_searchQuery) || (d['apodo']?.toString() ?? '').toLowerCase().contains(_searchQuery);
                      }).toList();
                      return ListView.builder(
                        padding: const EdgeInsets.only(bottom: 90),
                        itemCount: filtrados.length,
                        itemBuilder: (context, i) {
                          var doc = filtrados[i]; var data = doc.data() as Map<String, dynamic>;
                          return CheckboxListTile(
                            activeColor: verdeNeon, checkColor: Colors.black, title: Text(data['nombre']?.toString() ?? 'Dealer', style: const TextStyle(color: naranjaTema, fontWeight: FontWeight.w800, letterSpacing: 0.5)), subtitle: Text(data['apodo']?.toString() ?? '', style: const TextStyle(color: turquesaTema, fontWeight: FontWeight.w600)),
                            value: _dealersSeleccionados.contains(doc.id),
                            onChanged: (bool? val) { setState(() { if (val == true) _dealersSeleccionados.add(doc.id); else _dealersSeleccionados.remove(doc.id); }); },
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MesasScreen extends StatefulWidget {
  final String eventoId; final String nombreEvento;
  const MesasScreen({super.key, required this.eventoId, required this.nombreEvento});
  @override
  State<MesasScreen> createState() => _MesasScreenState();
}
class _MesasScreenState extends State<MesasScreen> {

  Future<void> _sincronizarTodoElEvento() async {
    var db = FirebaseFirestore.instance;
    var mesasSnap = await db.collection('eventos').doc(widget.eventoId).collection('mesas').get();
    int cont = 0;
    for (var mesaDoc in mesasSnap.docs) {
      var activosSnap = await mesaDoc.reference.collection('jugadores_activos').get();
      for (var jDoc in activosSnap.docs) {
        var jData = jDoc.data() as Map<String, dynamic>;
        if (jData['master_id'] != null) {
          var global = await db.collection('Jugadores').doc(jData['master_id']).get();
          if (global.exists) {
            var gData = global.data() as Map<String, dynamic>;
            await jDoc.reference.update({
              'nombre': gData['nombre'] ?? '', 'apodo': gData['apodo'] ?? '', 
              'fichas': gData['fichas'] ?? 0, 'emoji': gData['emoji'] ?? '👤', 'ciudad': gData['ciudad'] ?? '', 'club': gData['club'] ?? ''
            });
            cont++;
          }
        }
      }
    }
    setState(() {});
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("🔄 Sincronizados $cont jugadores con base global.", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), backgroundColor: Colors.green));
  }

  Future<void> _analizarBalanceo() async {
    var db = FirebaseFirestore.instance;
    var mesasSnap = await db.collection('eventos').doc(widget.eventoId).collection('mesas').get();
    int asientosVaciosGlobales = 0; List<Map<String, dynamic>> mesasInfo = [];

    for (var m in mesasSnap.docs) {
      var mData = m.data(); int aforo = mData['jugadores'] ?? 10;
      var actSnap = await m.reference.collection('jugadores_activos').get();
      int ocupados = actSnap.docs.length; int libres = aforo - ocupados;
      mesasInfo.add({'id': m.id, 'nombre': mData['nombre']?.toString() ?? 'Mesa', 'ocupados': ocupados, 'libres': libres});
      asientosVaciosGlobales += libres;
    }

    String sugerencias = "";
    for (var m in mesasInfo) {
      if (m['ocupados'] > 0) {
        int asientosLibresEnOtras = asientosVaciosGlobales - (m['libres'] as int);
        if (m['ocupados'] <= asientosLibresEnOtras) sugerencias += "La ${m['nombre']} tiene ${m['ocupados']} jugadores y pueden ser movidos a los espacios vacíos de las demás mesas.\n\n";
      }
    }
    if (sugerencias.isEmpty) sugerencias = "No hay mesas que puedan disolverse actualmente sin sobrepasar el aforo de las demás.";

    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1D26), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: verdeNeon)),
          title: const Text("⚖️ Sugerencias de Balanceo", style: TextStyle(color: verdeNeon, fontWeight: FontWeight.bold)),
          content: Text(sugerencias, style: const TextStyle(color: naranjaTema, fontSize: 14, fontWeight: FontWeight.bold)),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ENTENDIDO", style: TextStyle(color: verdeNeon, fontWeight: FontWeight.bold)))],
        )
      );
    }
  }

  Future<void> _distribuirJugadoresGlobal() async {
    if (isGuestMode) return;
    try {
      var db = FirebaseFirestore.instance;
      var eventoDoc = await db.collection('eventos').doc(widget.eventoId).get();
      List<String> rosterIds = [];
      if (eventoDoc.exists && eventoDoc.data() != null) {
        var eData = eventoDoc.data()!;
        if (eData.containsKey('jugadores_ids')) rosterIds = List<String>.from(eData['jugadores_ids']);
      }

      if (rosterIds.isEmpty) {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No hay jugadores en el Roster.", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: Colors.red));
        return;
      }

      var mesasSnap = await db.collection('eventos').doc(widget.eventoId).collection('mesas').orderBy('creado').get();

      if (mesasSnap.docs.isEmpty) {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No hay mesas creadas.", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: Colors.red));
        return;
      }

      List<String> jugadoresYaSentadosMasterIds = [];
      List<Map<String, dynamic>> infoSillasLibresGlobales = [];

      for (var mesaDoc in mesasSnap.docs) {
        var mData = mesaDoc.data(); int aforo = mData['jugadores'] ?? 10;
        var activosSnap = await mesaDoc.reference.collection('jugadores_activos').get();
        List<int> ocupados = [];
        
        for (var jDoc in activosSnap.docs) {
          int asiento = int.tryParse(jDoc.id) ?? -1;
          if (asiento != -1) ocupados.add(asiento);
          var jData = jDoc.data() as Map<String, dynamic>;
          if (jData.containsKey('master_id') && jData['master_id'] != null) jugadoresYaSentadosMasterIds.add(jData['master_id']);
        }
        for (int i = 0; i < aforo; i++) {
          if (!ocupados.contains(i)) infoSillasLibresGlobales.add({ 'mesa_ref': mesaDoc.reference, 'asiento': i, 'nombre_mesa': mData['nombre'] });
        }
      }

      List<String> faltanPorSentarIds = rosterIds.where((id) => !jugadoresYaSentadosMasterIds.contains(id)).toList();
      if (faltanPorSentarIds.isEmpty) {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Todos los jugadores del Roster ya están sentados.", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), backgroundColor: verdeNeon));
        return;
      }
      if (faltanPorSentarIds.length > infoSillasLibresGlobales.length) {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No hay suficientes sillas libres en las mesas para todos.", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: Colors.red));
        return;
      }

      var bdJugadores = await db.collection('Jugadores').get();
      List<DocumentSnapshot> faltanDocs = bdJugadores.docs.where((d) => faltanPorSentarIds.contains(d.id)).toList();
      
      Map<String, List<DocumentSnapshot>> porClub = {};
      for(var doc in faltanDocs) {
         String club = (doc.data() as Map)['club']?.toString().toUpperCase().trim() ?? 'SIN CLUB';
         if(club.isEmpty) club = 'SIN CLUB';
         if(!porClub.containsKey(club)) porClub[club] = [];
         porClub[club]!.add(doc);
      }
      
      List<String> ordenClubs = porClub.keys.toList();
      ordenClubs.sort((a, b) => porClub[b]!.length.compareTo(porClub[a]!.length)); 

      List<DocumentSnapshot> orderedPlayers = [];
      bool quedan = true;
      while(quedan) {
        quedan = false;
        for(String key in ordenClubs) {
          if(porClub[key]!.isNotEmpty) {
            orderedPlayers.add(porClub[key]!.removeAt(0));
            quedan = true;
          }
        }
      }

      Map<String, List<Map<String, dynamic>>> sillasPorMesa = {};
      for (var silla in infoSillasLibresGlobales) {
        String refId = (silla['mesa_ref'] as DocumentReference).id;
        if (!sillasPorMesa.containsKey(refId)) sillasPorMesa[refId] = [];
        sillasPorMesa[refId]!.add(silla);
      }

      List<Map<String, dynamic>> ordenDistribucion = [];
      bool haySillas = true;
      while (haySillas) {
        haySillas = false;
        for (var listaSillas in sillasPorMesa.values) {
          if (listaSillas.isNotEmpty) {
            ordenDistribucion.add(listaSillas.removeAt(0));
            haySillas = true;
          }
        }
      }

      int sentadosExitosos = 0;
      for (DocumentSnapshot pDoc in orderedPlayers) {
        if (ordenDistribucion.isEmpty) break;
        var jData = pDoc.data() as Map<String, dynamic>? ?? {};
        var sillaAsignada = ordenDistribucion.removeAt(0);

        await (sillaAsignada['mesa_ref'] as DocumentReference).collection('jugadores_activos').doc(sillaAsignada['asiento'].toString()).set({
          'nombre': jData['nombre']?.toString() ?? "Jugador", 'apodo': jData['apodo']?.toString() ?? "Jugador",
          'fichas': int.tryParse(jData['fichas']?.toString() ?? "0") ?? 0, 'emoji': jData['emoji']?.toString() ?? "👤", 
          'ciudad': jData['ciudad']?.toString() ?? "", 'club': jData['club']?.toString() ?? "", 'asiento': sillaAsignada['asiento'], 'master_id': pDoc.id
        });
        sentadosExitosos++;
      }

      await _registrarHistorial(widget.eventoId, "Se distribuyeron $sentadosExitosos jugadores equitativamente y filtrados por club.");
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("✅ $sentadosExitosos Jugadores repartidos con éxito.", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), backgroundColor: verdeNeon));

    } catch(e) { print(e); }
  }

  OverlayEntry? _eyeOverlay;
  void _showJugadoresOverlay(BuildContext context, DocumentReference mesaRef, String nombreMesa) {
    if (_eyeOverlay != null) return;
    
    _eyeOverlay = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(child: Container(color: Colors.black87)),
            Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.85, 
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1D26), 
                    borderRadius: BorderRadius.circular(15), 
                    border: Border.all(color: verdeNeon, width: 2), 
                    boxShadow: const [BoxShadow(color: Colors.black87, blurRadius: 15, spreadRadius: 2)]
                  ),
                  child: Stack(
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min, 
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Vista Rápida: $nombreMesa", style: const TextStyle(color: verdeNeon, fontWeight: FontWeight.w900, fontSize: 16)), 
                          const Divider(color: verdeNeon, thickness: 1),
                          FutureBuilder<DocumentSnapshot>(
                            future: mesaRef.get(),
                            builder: (ctx, mesaSnap) {
                              if (!mesaSnap.hasData) return const Text("Cargando...", style: TextStyle(color: verdeNeon));
                              var mData = mesaSnap.data!.data() as Map<String, dynamic>? ?? {};
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(mData['dealer_emoji']?.toString() ?? "🤵", style: const TextStyle(fontSize: 20)), 
                                      const SizedBox(width: 8),
                                      const Text("Dealer:", style: TextStyle(color: naranjaTema, fontSize: 14, fontWeight: FontWeight.w800)), 
                                      const SizedBox(width: 5),
                                      Expanded(
                                        child: RichText(
                                          text: TextSpan(
                                            style: const TextStyle(fontSize: 14),
                                            children: [
                                              TextSpan(text: "${mData['dealer_nombre']?.toString() ?? mData['dealer_apodo']?.toString() ?? 'SIN DEALER'} ", style: const TextStyle(color: naranjaTema, fontWeight: FontWeight.w800)),
                                              (mData['dealer_apodo'] != null && mData['dealer_apodo'] != (mData['dealer_nombre'] ?? '')) 
                                                ? TextSpan(text: '"${mData['dealer_apodo']}"', style: const TextStyle(color: turquesaTema, fontStyle: FontStyle.italic, fontWeight: FontWeight.w600)) 
                                                : const TextSpan()
                                            ]
                                          )
                                        )
                                      )
                                    ]
                                  ),
                                  (mData['dealer_ciudad'] != null && mData['dealer_ciudad'].toString().trim().isNotEmpty) 
                                    ? Padding(
                                        padding: const EdgeInsets.only(left: 28, top: 2), 
                                        child: Text("📍 ${mData['dealer_ciudad']}", style: TextStyle(color: turquesaTema.withOpacity(0.8), fontSize: 11, fontWeight: FontWeight.bold))
                                      ) 
                                    : const SizedBox.shrink()
                                ]
                              );
                            }
                          ),
                          const SizedBox(height: 10),
                          FutureBuilder<QuerySnapshot>(
                            future: mesaRef.collection('jugadores_activos').orderBy('asiento').get(),
                            builder: (ctx, snapshot) {
                              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                              if (snapshot.data!.docs.isEmpty) return Text("Mesa vacía", style: TextStyle(color: naranjaTema.withOpacity(0.5), fontWeight: FontWeight.w500));
                              return Column(
                                children: snapshot.data!.docs.map((jDoc) {
                                  var jData = jDoc.data() as Map<String, dynamic>;
                                  int numeroSilla = (int.tryParse(jDoc.id) ?? (jData['asiento'] ?? 0)) + 1;
                                  String jClub = jData['club']?.toString().trim() ?? '';
                                  String jCiudad = jData['ciudad']?.toString().trim() ?? '';
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 6),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            SizedBox(width: 20, child: Text("$numeroSilla.", style: const TextStyle(color: naranjaTema, fontSize: 13, fontWeight: FontWeight.w900))),
                                            Text(jData['emoji']?.toString() ?? "👤", style: const TextStyle(fontSize: 16)), 
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: RichText(
                                                text: TextSpan(
                                                  style: const TextStyle(fontSize: 14, height: 1.3),
                                                  children: [
                                                    TextSpan(text: "${jData['nombre']?.toString() ?? 'Jugador'} ", style: const TextStyle(color: naranjaTema, fontWeight: FontWeight.w800)),
                                                    TextSpan(text: '"${jData['apodo']?.toString() ?? ''}"', style: const TextStyle(color: turquesaTema, fontStyle: FontStyle.italic, fontWeight: FontWeight.w600))
                                                  ]
                                                )
                                              )
                                            ),
                                            Row(
                                              mainAxisSize: MainAxisSize.min, 
                                              children: [
                                                const FichaPokerIcon(color: verdeNeon, size: 14), 
                                                const SizedBox(width: 4), 
                                                Text("${jData['fichas']?.toString() ?? '0'}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14))
                                              ]
                                            )
                                          ]
                                        ),
                                        if (jClub.isNotEmpty || jCiudad.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(left: 28, top: 2),
                                            child: Text(
                                              "${jClub.isNotEmpty ? '🛡️ $jClub  ' : ''}${jCiudad.isNotEmpty ? '📍 $jCiudad' : ''}", 
                                              style: TextStyle(color: Colors.amber[400], fontSize: 10, fontWeight: FontWeight.w800)
                                            )
                                          )
                                      ]
                                    )
                                  );
                                }).toList()
                              );
                            }
                          )
                        ]
                      ),
                      Positioned(
                        top: -10, right: -10, 
                        child: IconButton(
                          icon: const Icon(Icons.close, color: Colors.redAccent, size: 28), 
                          onPressed: _hideJugadoresOverlay
                        )
                      )
                    ]
                  )
                )
              )
            )
          ]
        );
      }
    );
    Overlay.of(context).insert(_eyeOverlay!);
  }

  void _hideJugadoresOverlay() { _eyeOverlay?.remove(); _eyeOverlay = null; }
  @override void dispose() { _hideJugadoresOverlay(); super.dispose(); }

  void _mostrarDialogoMesa({DocumentSnapshot? docMesa, int sentados = 0}) {
    bool isEdit = docMesa != null; var data = isEdit ? docMesa!.data() as Map<String, dynamic> : {};
    final nameC = TextEditingController(text: isEdit ? data['nombre']?.toString() : "Mesa ${DateTime.now().minute}");
    double cant = isEdit ? (data['jugadores'] ?? 10).toDouble() : 10;
    double minCant = sentados > 2 ? sentados.toDouble() : 2;
    bool isMesaFinal = isEdit ? (data['is_mesa_final'] ?? false) : false;
    int numGanadores = isEdit ? (data['num_ganadores'] ?? 3) : 3;
    Map<String, dynamic> premiosData = isEdit ? (data['premios'] ?? {}) : {};
    Map<int, TextEditingController> premiosCtrls = {};
    for (int i = 1; i <= 10; i++) { premiosCtrls[i] = TextEditingController(text: premiosData[i.toString()]?.toString() ?? ""); }

    showDialog(
      context: context, 
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModal) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1A1D26), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: verdeNeon)),
              title: const Text("Configurar Mesa", style: TextStyle(color: verdeNeon, fontWeight: FontWeight.w900)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min, 
                  children: [
                    TextField(controller: nameC, style: const TextStyle(color: naranjaTema, fontWeight: FontWeight.bold), decoration: InputDecoration(labelText: "Nombre de Mesa", labelStyle: TextStyle(color: naranjaTema.withOpacity(0.6), fontWeight: FontWeight.bold))),
                    Slider(value: cant < minCant ? minCant : cant, min: minCant, max: 10, divisions: (10 - minCant).toInt(), label: cant.toInt().toString(), activeColor: verdeNeon, onChanged: (v) => setModal(() => cant = v)),
                    Text("${cant.toInt()} Jugadores Máximo", style: const TextStyle(color: verdeNeon, fontWeight: FontWeight.w900)),
                    isEdit ? Padding(padding: const EdgeInsets.only(top: 5), child: Text("(Hay $sentados sentados)", style: TextStyle(color: naranjaTema.withOpacity(0.6), fontSize: 12, fontWeight: FontWeight.bold))) : const SizedBox.shrink(),
                    const Divider(color: naranjaTema),
                    SwitchListTile(
                      title: const Text("👑 MESA FINAL", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.w900)),
                      subtitle: Text("Activar Podio y Premios", style: TextStyle(color: naranjaTema.withOpacity(0.6), fontSize: 11, fontWeight: FontWeight.bold)),
                      value: isMesaFinal, activeColor: Colors.amber, onChanged: (val) => setModal(() => isMesaFinal = val),
                    ),
                    ...(isMesaFinal ? [
                      Row(children: [ const Text("Ganadores:", style: TextStyle(color: naranjaTema, fontWeight: FontWeight.bold)), Expanded(child: Slider(value: numGanadores.toDouble(), min: 1, max: 10, divisions: 9, label: numGanadores.toString(), activeColor: Colors.amber, onChanged: (v) => setModal(() => numGanadores = v.toInt()))) ]),
                      ...List.generate(numGanadores, (index) {
                        int puesto = index + 1;
                        return Padding(
                          padding: const EdgeInsets.only(top: 8), 
                          child: TextField(
                            controller: premiosCtrls[puesto], 
                            style: const TextStyle(color: verdeNeon, fontWeight: FontWeight.bold), 
                            decoration: InputDecoration(
                              labelText: "Puntos $puestoº Puesto", 
                              labelStyle: TextStyle(color: verdeNeon.withOpacity(0.6), fontWeight: FontWeight.bold), 
                              prefixIcon: const Padding(padding: EdgeInsets.all(14), child: FichaPokerIcon(color: Colors.amber, size: 16)), 
                              filled: true, 
                              fillColor: Colors.black26, 
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none)
                            )
                          )
                        );
                      })
                    ] : <Widget>[])
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCELAR", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: verdeNeon), 
                  onPressed: () async {
                    Map<String, dynamic> premiosToSave = {};
                    if (isMesaFinal) for(int i=1; i<=numGanadores; i++) premiosToSave[i.toString()] = premiosCtrls[i]?.text ?? "";
                    if (isEdit) {
                      await docMesa!.reference.update({'nombre': nameC.text, 'jugadores': cant.toInt(), 'is_mesa_final': isMesaFinal, 'num_ganadores': numGanadores, 'premios': premiosToSave});
                    } else {
                      await FirebaseFirestore.instance.collection('eventos').doc(widget.eventoId).collection('mesas').add({'nombre': nameC.text, 'jugadores': cant.toInt(), 'creado': DateTime.now(), 'orden': DateTime.now().millisecondsSinceEpoch, 'is_mesa_final': isMesaFinal, 'num_ganadores': numGanadores, 'premios': premiosToSave});
                    }
                    if(context.mounted) Navigator.pop(context);
                  }, child: const Text("GUARDAR", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900)),
                )
              ],
            );
          }
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    double ancho = MediaQuery.of(context).size.width;
    int numColumnas = ancho > 800 ? 3 : (ancho > 600 ? 2 : 1);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.nombreEvento, style: const TextStyle(color: verdeNeon, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1.5), overflow: TextOverflow.ellipsis),
        actions: [
          const NetworkToggleAction(),
          IconButton(icon: const Icon(Icons.menu_book, color: turquesaTema), tooltip: "Ver Historial", onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => HistorialEventoScreen(eventoId: widget.eventoId, nombreEvento: widget.nombreEvento)))),
          IconButton(icon: const Icon(Icons.balance, color: turquesaTema), tooltip: "Verificar Balanceo", onPressed: () => _analizarBalanceo()),
          !isGuestMode ? IconButton(icon: const Icon(Icons.call_split, color: turquesaTema), tooltip: "Distribuir Jugadores", onPressed: _distribuirJugadoresGlobal) : const SizedBox.shrink(),
          !isGuestMode ? IconButton(icon: const Icon(Icons.group_add, color: verdeNeon), tooltip: "Asignar Roster", onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => EventRosterScreen(eventoId: widget.eventoId, nombreEvento: widget.nombreEvento)))) : const SizedBox.shrink(),
          IconButton(icon: const Icon(Icons.refresh, color: verdeNeon), tooltip: "Refrescar", onPressed: _sincronizarTodoElEvento),
        ],
      ),
      floatingActionButton: isGuestMode ? null : FloatingActionButton(backgroundColor: verdeNeon, onPressed: () => _mostrarDialogoMesa(), child: const Icon(Icons.add, color: Colors.black)),
      body: Stack(
        children: [
          Column(
            children: [
              EventTimerBanner(eventoId: widget.eventoId),
              EventStatsBanner(eventoId: widget.eventoId),
              Expanded(
                child: StreamBuilder(
                  stream: FirebaseFirestore.instance.collection('eventos').doc(widget.eventoId).collection('mesas').orderBy('creado').snapshots(),
                  builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: verdeNeon));
                    
                    var docsMesas = snapshot.data!.docs;

                    return GridView.builder(
                      padding: const EdgeInsets.only(bottom: 80, left: 15, right: 15, top: 15),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: numColumnas, childAspectRatio: 2.2, crossAxisSpacing: 10, mainAxisSpacing: 10),
                      itemCount: docsMesas.length,
                      itemBuilder: (context, index) {
                        var mesa = docsMesas[index];
                        var data = mesa.data() as Map<String, dynamic>? ?? {};
                        bool esMesaFinal = data['is_mesa_final'] ?? false;
                        
                        return StreamBuilder<QuerySnapshot>(
                          stream: mesa.reference.collection('jugadores_activos').snapshots(),
                          builder: (context, activosSnap) {
                            int sentados = activosSnap.hasData ? activosSnap.data!.docs.length : 0;
                            
                            return Card(
                              color: Colors.black45,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: esMesaFinal ? Colors.amber : verdeNeon, width: esMesaFinal ? 2 : 1)),
                              child: ListTile(
                                title: Row(
                                  children: [
                                    esMesaFinal ? const Padding(padding: EdgeInsets.only(right: 5), child: Icon(Icons.workspace_premium, color: Colors.amber, size: 20)) : const SizedBox.shrink(),
                                    Expanded(child: Text(data['nombre']?.toString() ?? 'Mesa', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: esMesaFinal ? Colors.amber : naranjaTema, letterSpacing: 1), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                  ],
                                ),
                                subtitle: Text("Aforo: ${data['jugadores'] ?? 10}  |  Sentados: $sentados", style: TextStyle(color: verdeNeon.withOpacity(0.8), fontWeight: FontWeight.w600)),
                                trailing: isGuestMode ? null : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(icon: const Icon(Icons.visibility, color: verdeNeon), onPressed: () => _showJugadoresOverlay(context, mesa.reference, data['nombre']?.toString() ?? 'Mesa')),
                                    IconButton(icon: Icon(Icons.edit, color: naranjaTema.withOpacity(0.6)), onPressed: () => _mostrarDialogoMesa(docMesa: mesa, sentados: sentados)),
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.redAccent), 
                                      onPressed: () async {
                                        var activos = await mesa.reference.collection('jugadores_activos').get();
                                        for (var doc in activos.docs) { await doc.reference.delete(); }
                                        var podio = await mesa.reference.collection('podio').get();
                                        for (var doc in podio.docs) { await doc.reference.delete(); }
                                        await mesa.reference.delete();
                                        await _registrarHistorial(widget.eventoId, "Mesa eliminada manualmente");
                                      }
                                    ),
                                  ],
                                ),
                                onTap: () {
                                  Navigator.push(context, MaterialPageRoute(builder: (context) => JuegoMesaScreen(eventoId: widget.eventoId, mesaId: mesa.id, aforoMesa: data['jugadores'] ?? 10, nombreMesa: data['nombre']?.toString() ?? 'Mesa')));
                                },
                              ),
                            );
                          }
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
          
          const FloatingLogo(), 
        ],
      )
    );
  }
}

class JuegoMesaScreen extends StatefulWidget {
  final String eventoId; final String mesaId; final int aforoMesa; final String nombreMesa;
  const JuegoMesaScreen({super.key, required this.eventoId, required this.mesaId, required this.aforoMesa, required this.nombreMesa});
  @override
  State<JuegoMesaScreen> createState() => _JuegoMesaScreenState();
}

class _JuegoMesaScreenState extends State<JuegoMesaScreen> {

  Future<void> _sincronizarMesaLocal() async {
    var db = FirebaseFirestore.instance;
    var mesaRef = db.collection('eventos').doc(widget.eventoId).collection('mesas').doc(widget.mesaId);
    var activosSnap = await mesaRef.collection('jugadores_activos').get();
    for (var doc in activosSnap.docs) {
      var d = doc.data() as Map<String, dynamic>;
      if (d['master_id'] != null) {
        var g = await db.collection('Jugadores').doc(d['master_id']).get();
        if (g.exists) {
          var gData = g.data() as Map<String, dynamic>;
          await doc.reference.update({
            'nombre': gData['nombre'], 'apodo': gData['apodo'], 
            'fichas': gData['fichas'], 'emoji': gData['emoji'], 'ciudad': gData['ciudad'], 'club': gData['club']
          });
        }
      }
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("🔄 Sillas sincronizadas con base global", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)), backgroundColor: Colors.green));
  }
  
  void _mostrarPodio() {
    showDialog(
      context: context,
      builder: (ctx) {
        var mesaRef = FirebaseFirestore.instance.collection('eventos').doc(widget.eventoId).collection('mesas').doc(widget.mesaId);
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1D26), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: Colors.amber)),
          title: const Row(children: [Icon(Icons.workspace_premium, color: Colors.amber), SizedBox(width: 10), Text("Podio Oficial", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.w900))]),
          content: SizedBox(
            width: double.maxFinite,
            child: StreamBuilder<QuerySnapshot>(
              stream: mesaRef.collection('podio').orderBy('puesto').snapshots(),
              builder: (context, snapshot) {
                if(!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                if(snapshot.data!.docs.isEmpty) return const Text("Aún no hay jugadores eliminados.", style: TextStyle(color: naranjaTema, fontWeight: FontWeight.w600));
                return SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: snapshot.data!.docs.map((doc) {
                      var data = doc.data() as Map<String, dynamic>;
                      Color colorPuesto = data['puesto'] == 1 ? Colors.amber : (data['puesto'] == 2 ? const Color(0xFFC0C0C0) : const Color(0xFFCD7F32));
                      return Card(
                        color: Colors.black45, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: colorPuesto)),
                        child: ListTile(
                          leading: CircleAvatar(backgroundColor: colorPuesto.withOpacity(0.2), child: Text("${data['puesto']}º", style: TextStyle(color: colorPuesto, fontWeight: FontWeight.w900))),
                          title: Text("${data['emoji']} ${data['apodo']}", style: const TextStyle(color: naranjaTema, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                          subtitle: Text(data['premio'].toString().isNotEmpty ? "Puntos: ${data['premio']}" : "Sin puntos asignados", style: const TextStyle(color: turquesaTema, fontSize: 12, fontWeight: FontWeight.w600)),
                          trailing: isGuestMode ? null : IconButton(
                            icon: const Icon(Icons.undo, color: Colors.redAccent),
                            tooltip: "Deshacer (Volver a sentar)",
                            onPressed: () async {
                              var activos = await mesaRef.collection('jugadores_activos').get();
                              List<int> ocupados = activos.docs.map((d) => int.tryParse(d.id) ?? -1).toList();
                              int asientoLibre = -1;
                              for(int i=0; i<widget.aforoMesa; i++) if(!ocupados.contains(i)) { asientoLibre = i; break; }
                              if (asientoLibre != -1) {
                                data.remove('puesto'); data.remove('premio'); data['asiento'] = asientoLibre;
                                await mesaRef.collection('jugadores_activos').doc(asientoLibre.toString()).set(data);
                                await doc.reference.delete();
                              } 
                            }
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                );
              }
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CERRAR", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)))]
        );
      }
    );
  }

  void _intentarLevantarJugador(String docId, Map<String, dynamic> jData, BuildContext parentContext) async {
    var mesaRef = FirebaseFirestore.instance.collection('eventos').doc(widget.eventoId).collection('mesas').doc(widget.mesaId);
    var mesaSnap = await mesaRef.get();
    var mData = mesaSnap.data() as Map<String, dynamic>? ?? {};

    bool isFinal = mData['is_mesa_final'] ?? false;
    int numGanadores = mData['num_ganadores'] ?? 0;
    Map<String, dynamic> premios = mData['premios'] ?? {};
    var activosSnap = await mesaRef.collection('jugadores_activos').get();
    int sentados = activosSnap.docs.length;

    if (isFinal && sentados <= numGanadores && sentados > 1) {
      int puesto = sentados;
      showDialog(
        context: parentContext,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1D26), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: Colors.amber)),
          title: Text("🏆 Podio: $puestoº Puesto", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w900)),
          content: Text("¿Seguro que quieres levantar a ${jData['apodo']}?\nIrá automáticamente al podio en el puesto $puesto.", style: const TextStyle(color: naranjaTema, fontWeight: FontWeight.bold)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCELAR", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
              onPressed: () async {
                Navigator.pop(ctx); Navigator.pop(parentContext); 
                jData['puesto'] = puesto; jData['premio'] = premios[puesto.toString()] ?? '';
                await mesaRef.collection('podio').doc(docId).set(jData);
                await mesaRef.collection('jugadores_activos').doc(docId).delete();
                if (sentados == 2) {
                  var lastActiveSnap = await mesaRef.collection('jugadores_activos').get();
                  if (lastActiveSnap.docs.isNotEmpty) {
                    var lastDoc = lastActiveSnap.docs.first; var lastData = lastDoc.data() as Map<String, dynamic>;
                    lastData['puesto'] = 1; lastData['premio'] = premios['1'] ?? '';
                    await mesaRef.collection('podio').doc(lastDoc.id).set(lastData);
                    await lastDoc.reference.delete();
                    if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("👑 ¡${lastData['apodo']?.toString()} ES EL CAMPEÓN!", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), backgroundColor: Colors.amber, duration: const Duration(seconds: 5)));
                  }
                }
              }, child: const Text("SÍ, AL PODIO", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900))
            )
          ]
        )
      );
    } else {
      await mesaRef.collection('jugadores_activos').doc(docId).delete();
      if(mounted) Navigator.pop(parentContext);
    }
  }

  Future<void> _sentarJugadorManual(int asientoIndex) async {
    if (isGuestMode) return;
    try {
      var db = FirebaseFirestore.instance;
      var eventoDoc = await db.collection('eventos').doc(widget.eventoId).get();
      List<String> rosterIds = [];
      if (eventoDoc.exists && eventoDoc.data() != null) {
        var eData = eventoDoc.data()!;
        if (eData.containsKey('jugadores_ids')) rosterIds = List<String>.from(eData['jugadores_ids']);
      }

      if (rosterIds.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No hay jugadores en el Roster de este evento.", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), backgroundColor: verdeNeon));
        return;
      }

      var mesasSnap = await db.collection('eventos').doc(widget.eventoId).collection('mesas').get();
      List<String> masterIdsSentados = [];
      for (var m in mesasSnap.docs) {
        var actSnap = await m.reference.collection('jugadores_activos').get();
        for (var doc in actSnap.docs) {
          var d = doc.data() as Map<String, dynamic>;
          if (d.containsKey('master_id') && d['master_id'] != null) masterIdsSentados.add(d['master_id']);
        }
      }

      List<String> disponiblesIds = rosterIds.where((id) => !masterIdsSentados.contains(id)).toList();
      if (disponiblesIds.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Todos los jugadores del roster ya están sentados.", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), backgroundColor: verdeNeon));
        return;
      }

      var jugSnap = await db.collection('Jugadores').get();
      List<DocumentSnapshot> disponiblesDocs = jugSnap.docs.where((doc) => disponiblesIds.contains(doc.id)).toList();

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1A1D26), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: verdeNeon)),
              title: const Text("Sentar Jugador", style: TextStyle(color: verdeNeon, fontWeight: FontWeight.w900)),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: disponiblesDocs.length,
                  itemBuilder: (c, i) {
                    var doc = disponiblesDocs[i];
                    var data = doc.data() as Map<String, dynamic>;
                    return ListTile(
                      leading: CircleAvatar(backgroundColor: Colors.white10, child: Text(data['emoji']?.toString() ?? '👤')),
                      title: Text(data['nombre']?.toString() ?? 'Jugador', style: const TextStyle(color: naranjaTema, fontWeight: FontWeight.bold)),
                      subtitle: Text(data['apodo']?.toString() ?? '', style: TextStyle(color: naranjaTema.withOpacity(0.6), fontWeight: FontWeight.bold)),
                      onTap: () async {
                        Navigator.pop(ctx);
                        await db.collection('eventos').doc(widget.eventoId).collection('mesas').doc(widget.mesaId).collection('jugadores_activos').doc(asientoIndex.toString()).set({
                          'nombre': data['nombre']?.toString() ?? "Jugador", 'apodo': data['apodo']?.toString() ?? "Jugador",
                          'fichas': int.tryParse(data['fichas']?.toString() ?? "0") ?? 0, 'emoji': data['emoji']?.toString() ?? "👤",
                          'ciudad': data['ciudad']?.toString() ?? "", 'club': data['club']?.toString() ?? "", 'asiento': asientoIndex, 'master_id': doc.id
                        });
                        await _registrarHistorial(widget.eventoId, "Se sentó manualmente a ${data['apodo']} en la silla ${asientoIndex + 1}.");
                      }
                    );
                  }
                )
              ),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCELAR", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)))]
            );
          }
        );
      }
    } catch(e) { print(e); }
  }

  void _editarDealerGlobal(String? dealerId, String nombreActual, String apodoActual) {
    if (isGuestMode || dealerId == null) return;
    final nombreC = TextEditingController(text: nombreActual);
    final apodoC = TextEditingController(text: apodoActual);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D26), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: verdeNeon)),
        title: const Text("EDITAR DEALER", style: TextStyle(color: verdeNeon, fontWeight: FontWeight.w900)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nombreC, decoration: const InputDecoration(labelText: "Nombre Real", labelStyle: TextStyle(color: Colors.white70)), style: const TextStyle(color: naranjaTema)),
            TextField(controller: apodoC, decoration: const InputDecoration(labelText: "Apodo", labelStyle: TextStyle(color: Colors.white70)), style: const TextStyle(color: naranjaTema)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCELAR", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: verdeNeon),
            onPressed: () async {
              await FirebaseFirestore.instance.collection('eventos').doc(widget.eventoId).collection('mesas').doc(widget.mesaId).update({
                'dealer_nombre': nombreC.text.trim(), 'dealer_apodo': apodoC.text.trim()
              });
              await FirebaseFirestore.instance.collection('Dealers').doc(dealerId).update({
                'nombre': nombreC.text.trim(), 'apodo': apodoC.text.trim()
              });
              if(mounted) {
                Navigator.pop(ctx); 
                Navigator.pop(context); 
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Dealer actualizado en Mesa y Nube.", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), backgroundColor: verdeNeon));
              }
            },
            child: const Text("ACTUALIZAR", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          )
        ],
      )
    );
  }

  void _seleccionarDealer() async {
    if (isGuestMode) return;
    try {
      var mesaDoc = await FirebaseFirestore.instance.collection('eventos').doc(widget.eventoId).collection('mesas').doc(widget.mesaId).get();
      var mesaData = mesaDoc.data() ?? {};
      String? dealerActualId = mesaData['dealer_id'];

      var eventoDoc = await FirebaseFirestore.instance.collection('eventos').doc(widget.eventoId).get();
      List<String> dPermitidos = [];
      if (eventoDoc.exists && eventoDoc.data() != null) {
        if ((eventoDoc.data()!).containsKey('dealers_ids')) dPermitidos = List<String>.from((eventoDoc.data()!)['dealers_ids']);
      }
      var dealersSnap = await FirebaseFirestore.instance.collection('Dealers').get();
      var mesasSnap = await FirebaseFirestore.instance.collection('eventos').doc(widget.eventoId).collection('mesas').get();
      List<String> dOcupados = [];
      for (var m in mesasSnap.docs) if (m.id != widget.mesaId) if ((m.data()).containsKey('dealer_id') && (m.data())['dealer_id'] != null) dOcupados.add((m.data())['dealer_id']);
      List<DocumentSnapshot> disponibles = dealersSnap.docs.where((d) => dPermitidos.contains(d.id) && !dOcupados.contains(d.id)).toList();
      
      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1A1D26), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: verdeNeon)),
            title: const Text("Asignar Crupier", style: TextStyle(color: verdeNeon, fontWeight: FontWeight.w900)),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true, itemCount: disponibles.length,
                itemBuilder: (context, i) {
                  var data = disponibles[i].data() as Map<String, dynamic>? ?? {};
                  return ListTile(
                    leading: CircleAvatar(backgroundColor: naranjaTema.withOpacity(0.1), child: Text(data['emoji']?.toString() ?? '🤵')),
                    title: Text(data['nombre']?.toString() ?? 'Sin Nombre', style: const TextStyle(color: naranjaTema, fontWeight: FontWeight.bold)),
                    onTap: () async {
                      await FirebaseFirestore.instance.collection('eventos').doc(widget.eventoId).collection('mesas').doc(widget.mesaId).update({
                        'dealer_id': disponibles[i].id, 'dealer_nombre': data['nombre']?.toString() ?? 'Crupier', 'dealer_apodo': data['apodo']?.toString() ?? data['nombre']?.toString() ?? 'Dealer',
                        'dealer_emoji': data['emoji']?.toString() ?? '🤵', 'dealer_ciudad': data['ciudad']?.toString() ?? '', 'dealers_pasados': FieldValue.arrayUnion([disponibles[i].id])
                      });
                      if(mounted) Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
            actions: [
              dealerActualId != null ? ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: naranjaTema),
                onPressed: () => _editarDealerGlobal(dealerActualId, mesaData['dealer_nombre'], mesaData['dealer_apodo']),
                child: const Text("EDITAR ACTUAL", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ) : const SizedBox.shrink(),
              TextButton(
                onPressed: () async {
                  await FirebaseFirestore.instance.collection('eventos').doc(widget.eventoId).collection('mesas').doc(widget.mesaId).update({'dealer_id': FieldValue.delete(), 'dealer_nombre': FieldValue.delete(), 'dealer_apodo': FieldValue.delete(), 'dealer_emoji': FieldValue.delete(), 'dealer_ciudad': FieldValue.delete()});
                  if(mounted) Navigator.pop(context);
                }, child: const Text("QUITAR", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        }
      );
    } catch (e) { print(e); }
  }

  void _abrirOpcionesJugador(int indexActual, Map<String, dynamic> data) async {
    if (isGuestMode) return;
    final nombreC = TextEditingController(text: data['nombre']?.toString() ?? "");
    final apodoC = TextEditingController(text: data['apodo']?.toString() ?? "");
    final fichasC = TextEditingController(text: data['fichas']?.toString() ?? "0");
    String docId = indexActual.toString();

    var mesasDisponiblesSnap = await FirebaseFirestore.instance.collection('eventos').doc(widget.eventoId).collection('mesas').get();
    var mesasDisponibles = mesasDisponiblesSnap.docs;
    String mesaSelId = widget.mesaId;

    var activosSnap = await FirebaseFirestore.instance.collection('eventos').doc(widget.eventoId).collection('mesas').doc(widget.mesaId).collection('jugadores_activos').get();
    List<int> ocupados = activosSnap.docs.map((d) => int.tryParse(d.id) ?? -1).toList();
    int asientoSel = indexActual;
    
    if (!mounted) return;

    showDialog(
      context: context, 
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1A1D26), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: verdeNeon)),
              title: Text("Opciones: ${data['apodo']}", style: const TextStyle(color: verdeNeon, fontWeight: FontWeight.w900)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(controller: nombreC, decoration: InputDecoration(labelText: "Nombre Real", labelStyle: TextStyle(color: naranjaTema.withOpacity(0.6), fontWeight: FontWeight.bold)), style: const TextStyle(color: naranjaTema, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    TextField(controller: apodoC, decoration: InputDecoration(labelText: "Apodo", labelStyle: TextStyle(color: naranjaTema.withOpacity(0.6), fontWeight: FontWeight.bold)), style: const TextStyle(color: naranjaTema, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    TextField(controller: fichasC, decoration: InputDecoration(labelText: "Puntos Totales", labelStyle: TextStyle(color: naranjaTema.withOpacity(0.6), fontWeight: FontWeight.bold)), keyboardType: TextInputType.number, style: const TextStyle(color: naranjaTema, fontWeight: FontWeight.bold)),
                    const Padding(padding: EdgeInsets.symmetric(vertical: 15), child: Divider(color: naranjaTema, thickness: 1)),
                    const Text("UBICACIÓN DEL JUGADOR", style: TextStyle(color: turquesaTema, fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: mesaSelId, dropdownColor: Colors.grey[900], style: const TextStyle(color: naranjaTema, fontWeight: FontWeight.bold), decoration: const InputDecoration(labelText: "Mesa Asignada", filled: true, fillColor: Colors.black26),
                      items: mesasDisponibles.map((m) => DropdownMenuItem(value: m.id, child: Text((m.data())['nombre']?.toString() ?? 'Mesa'))).toList(),
                      onChanged: (val) => setModalState(() => mesaSelId = val!),
                    ),
                    const SizedBox(height: 10),
                    mesaSelId == widget.mesaId ?
                      DropdownButtonFormField<int>(
                        value: asientoSel, dropdownColor: Colors.grey[900], style: const TextStyle(color: naranjaTema, fontWeight: FontWeight.bold), decoration: const InputDecoration(labelText: "Silla (Solo libres)", filled: true, fillColor: Colors.black26),
                        items: [
                          DropdownMenuItem(value: indexActual, child: Text("Silla ${indexActual + 1} (Actual)")),
                          ...List.generate(widget.aforoMesa, (i) => i).where((i) => !ocupados.contains(i)).map((i) => DropdownMenuItem(value: i, child: Text("Mover a Silla ${i + 1}")))
                        ],
                        onChanged: (val) => setModalState(() => asientoSel = val!),
                      ) : const SizedBox.shrink(),
                  ],
                ),
              ),
              actionsAlignment: MainAxisAlignment.spaceBetween,
              actions: [
                TextButton.icon(onPressed: () => _intentarLevantarJugador(docId, data, context), icon: const Icon(Icons.exit_to_app, color: Colors.redAccent), label: const Text("LEVANTAR", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCELAR", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: verdeNeon),
                      onPressed: () async {
                        Map<String, dynamic> updateData = {'nombre': nombreC.text, 'apodo': apodoC.text, 'fichas': int.tryParse(fichasC.text) ?? 0, 'master_id': data['master_id']};
                        if (data.containsKey('emoji')) updateData['emoji'] = data['emoji'];
                        if (data.containsKey('ciudad')) updateData['ciudad'] = data['ciudad'];
                        if (data.containsKey('club')) updateData['club'] = data['club'];

                        if (data['master_id'] != null) {
                          await FirebaseFirestore.instance.collection('Jugadores').doc(data['master_id']).update({
                            'nombre': nombreC.text.trim(),
                            'apodo': apodoC.text.trim(),
                            'fichas': int.tryParse(fichasC.text) ?? 0,
                          });
                        }

                        if (mesaSelId != widget.mesaId) { 
                          var oRef = FirebaseFirestore.instance.collection('eventos').doc(widget.eventoId).collection('mesas').doc(mesaSelId).collection('jugadores_activos');
                          List<int> oOcupadosSnap = (await oRef.get()).docs.map((d) => int.tryParse(d.id) ?? -1).toList();
                          int aforoO = ((await FirebaseFirestore.instance.collection('eventos').doc(widget.eventoId).collection('mesas').doc(mesaSelId).get()).data() as Map)['jugadores'] ?? 10;
                          int nLibre = -1;
                          for(int i=0; i<aforoO; i++) if(!oOcupadosSnap.contains(i)) { nLibre = i; break; }

                          if (nLibre != -1) {
                            updateData['asiento'] = nLibre;
                            await oRef.doc(nLibre.toString()).set(updateData);
                            await FirebaseFirestore.instance.collection('eventos').doc(widget.eventoId).collection('mesas').doc(widget.mesaId).collection('jugadores_activos').doc(docId).delete();
                          } else {
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Mesa destino llena.", style: TextStyle(fontWeight: FontWeight.bold))));
                          }
                        } else if (asientoSel != indexActual) {
                          updateData['asiento'] = asientoSel;
                          await FirebaseFirestore.instance.collection('eventos').doc(widget.eventoId).collection('mesas').doc(widget.mesaId).collection('jugadores_activos').doc(asientoSel.toString()).set(updateData);
                          await FirebaseFirestore.instance.collection('eventos').doc(widget.eventoId).collection('mesas').doc(widget.mesaId).collection('jugadores_activos').doc(docId).delete();
                        } else {
                          updateData['asiento'] = indexActual;
                          await FirebaseFirestore.instance.collection('eventos').doc(widget.eventoId).collection('mesas').doc(widget.mesaId).collection('jugadores_activos').doc(docId).update(updateData);
                        }
                        if (mounted) Navigator.pop(context);
                      }, child: const Text("GUARDAR", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    ),
                  ],
                )
              ],
            );
          }
        );
      }
    );
  }

  Future<void> _llenarFormaAleatoria() async {
    try {
      var eventoDoc = await FirebaseFirestore.instance.collection('eventos').doc(widget.eventoId).get();
      List<String> jugadoresPermitidos = []; List<String> dealersPermitidos = [];
      if (eventoDoc.exists && eventoDoc.data() != null) {
        var eData = eventoDoc.data()!;
        if (eData.containsKey('jugadores_ids')) jugadoresPermitidos = List<String>.from(eData['jugadores_ids']);
        if (eData.containsKey('dealers_ids')) dealersPermitidos = List<String>.from(eData['dealers_ids']);
      }
      if (jugadoresPermitidos.isEmpty) {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Agrega Jugadores al evento primero."), backgroundColor: Colors.red));
        return;
      }

      var mesasSnap = await FirebaseFirestore.instance.collection('eventos').doc(widget.eventoId).collection('mesas').get();
      var dealersSnap = await FirebaseFirestore.instance.collection('Dealers').get();
      var mesaActualDoc = await FirebaseFirestore.instance.collection('eventos').doc(widget.eventoId).collection('mesas').doc(widget.mesaId).get();
      
      if (mesaActualDoc.exists) {
        var mesaData = mesaActualDoc.data() as Map<String, dynamic>;
        if (!mesaData.containsKey('dealer_id') || mesaData['dealer_id'] == null) {
          List<String> dealersOcupados = [];
          for (var m in mesasSnap.docs) {
            if (m.id != widget.mesaId) {
              var d = m.data() as Map<String, dynamic>;
              if (d.containsKey('dealer_id') && d['dealer_id'] != null) dealersOcupados.add(d['dealer_id']);
            }
          }
          List<DocumentSnapshot> dealersDisponibles = dealersSnap.docs.where((d) => dealersPermitidos.contains(d.id) && !dealersOcupados.contains(d.id)).toList();
          if (dealersDisponibles.isNotEmpty) {
            dealersDisponibles.shuffle();
            var dealerElegido = dealersDisponibles.first;
            var dataDealer = dealerElegido.data() as Map<String, dynamic>? ?? {};
            await FirebaseFirestore.instance.collection('eventos').doc(widget.eventoId).collection('mesas').doc(widget.mesaId).update({
              'dealer_id': dealerElegido.id, 'dealer_nombre': dataDealer['nombre']?.toString() ?? 'Crupier', 'dealer_apodo': dataDealer['apodo']?.toString() ?? dataDealer['nombre']?.toString() ?? 'Dealer',
              'dealer_emoji': dataDealer['emoji']?.toString() ?? '🤵', 'dealer_ciudad': dataDealer['ciudad']?.toString() ?? '', 'dealers_pasados': FieldValue.arrayUnion([dealerElegido.id])
            });
          }
        }
      }

      final activosRef = FirebaseFirestore.instance.collection('eventos').doc(widget.eventoId).collection('mesas').doc(widget.mesaId).collection('jugadores_activos');
      var snapJugadores = await FirebaseFirestore.instance.collection('Jugadores').get();
      
      List<String> nombresOcupadosGlobal = [];
      for (var mesaDoc in mesasSnap.docs) {
        var mesaActivos = await mesaDoc.reference.collection('jugadores_activos').get();
        nombresOcupadosGlobal.addAll(mesaActivos.docs.map((d) {
           var data = d.data() as Map<String, dynamic>; return data.containsKey('nombre') ? data['nombre'].toString().toLowerCase().trim() : '';
        }));
      }

      List<DocumentSnapshot> candidatos = snapJugadores.docs.where((doc) {
        var d = doc.data() as Map<String, dynamic>? ?? {};
        String n = (d.containsKey('nombre') ? d['nombre'] : "").toString().toLowerCase().trim();
        return jugadoresPermitidos.contains(doc.id) && n.isNotEmpty && !nombresOcupadosGlobal.contains(n);
      }).toList();
      candidatos.shuffle();

      var snapMesaActual = await activosRef.get();
      List<int> asientosOcupados = snapMesaActual.docs.map((d) => int.tryParse(d.id) ?? -1).where((id) => id != -1).toList();
      
      List<int> asientosLibres = [];
      for (int i = 0; i < widget.aforoMesa; i++) if (!asientosOcupados.contains(i)) asientosLibres.add(i);
      asientosLibres.shuffle();

      int contador = 0;
      for (int asientoRandom in asientosLibres) {
        if (candidatos.isNotEmpty) {
          var elegido = candidatos.removeAt(0);
          var d = elegido.data() as Map<String, dynamic>? ?? {};
          await activosRef.doc(asientoRandom.toString()).set({
            'nombre': d['nombre']?.toString() ?? "Jugador", 'apodo': d['apodo']?.toString() ?? "Jugador", 'fichas': int.tryParse(d['fichas']?.toString() ?? "0") ?? 0,
            'emoji': d['emoji']?.toString() ?? "👤", 'ciudad': d['ciudad']?.toString() ?? "", 'club': d['club']?.toString() ?? "", 'asiento': asientoRandom, 'master_id': elegido.id
          });
          contador++;
        }
      }
      if (contador > 0) await _registrarHistorial(widget.eventoId, "Se llenó aleatorio ${widget.nombreMesa}");
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Mesa llenada con éxito.", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), backgroundColor: Colors.green));
    } catch (e) { print(e); }
  }

  Future<void> _disolverMesa() async {
    try {
      var db = FirebaseFirestore.instance;
      var misJugadoresSnap = await db.collection('eventos').doc(widget.eventoId).collection('mesas').doc(widget.mesaId).collection('jugadores_activos').get();
      if (misJugadoresSnap.docs.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("La mesa ya está vacía.", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), backgroundColor: verdeNeon));
        return;
      }

      List<QueryDocumentSnapshot> misJugadores = misJugadoresSnap.docs;
      var mesasSnap = await db.collection('eventos').doc(widget.eventoId).collection('mesas').get();
      List<Map<String, dynamic>> sillasLibresDisponibles = [];

      for (var m in mesasSnap.docs) {
        if (m.id != widget.mesaId) {
          var mData = m.data(); int aforoOtraMesa = mData['jugadores'] ?? 10;
          String nombreOtraMesa = mData['nombre']?.toString() ?? 'Otra Mesa';
          var activosSnap = await m.reference.collection('jugadores_activos').get();
          List<int> ocupadosOtraMesa = activosSnap.docs.map((d) => int.parse(d.id)).toList();
          for (int i = 0; i < aforoOtraMesa; i++) if (!ocupadosOtraMesa.contains(i)) sillasLibresDisponibles.add({'mesa_id': m.id, 'mesa_nombre': nombreOtraMesa, 'asiento': i});
        }
      }

      if (misJugadores.length > sillasLibresDisponibles.length) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF1A1D26), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: Colors.redAccent)),
              title: const Text("Error de Balanceo", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900)),
              content: Text("Tienes ${misJugadores.length} jugadores pero solo hay ${sillasLibresDisponibles.length} espacios vacíos.", style: const TextStyle(color: naranjaTema, fontWeight: FontWeight.bold)),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)))]
            )
          );
        }
        return;
      }

      sillasLibresDisponibles.shuffle();
      String reporteMigracion = "";
      
      var batch = db.batch(); 

      for (var jugadorDoc in misJugadores) {
        var jData = jugadorDoc.data() as Map<String, dynamic>;
        var destino = sillasLibresDisponibles.removeLast();
        
        jData['asiento'] = destino['asiento'];
        
        var nuevaSillaRef = db.collection('eventos').doc(widget.eventoId).collection('mesas').doc(destino['mesa_id']).collection('jugadores_activos').doc(destino['asiento'].toString());
        
        batch.set(nuevaSillaRef, jData);
        batch.delete(jugadorDoc.reference);
        reporteMigracion += "👤 ${jData['apodo']} ➔ ${destino['mesa_nombre']} (Silla ${(destino['asiento'] as int) + 1})\n";
      }

      var mesaActualRef = db.collection('eventos').doc(widget.eventoId).collection('mesas').doc(widget.mesaId);
      batch.update(mesaActualRef, {'dealer_id': FieldValue.delete(), 'dealer_nombre': FieldValue.delete(), 'dealer_apodo': FieldValue.delete(), 'dealer_emoji': FieldValue.delete(), 'dealer_ciudad': FieldValue.delete()});
      
      await batch.commit();
      await _registrarHistorial(widget.eventoId, "Se disolvió ${widget.nombreMesa} y se reubicó a los jugadores.");

      if (mounted) {
        showDialog(
          context: context, barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1A1D26), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: verdeNeon)),
            title: const Text("✅ Mesa Disuelta", style: TextStyle(color: verdeNeon, fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("Reporte:", style: TextStyle(color: naranjaTema, fontWeight: FontWeight.bold)), const SizedBox(height: 10), Text(reporteMigracion, style: const TextStyle(color: naranjaTema, fontSize: 13, fontWeight: FontWeight.bold)), const SizedBox(height: 15), const Text("¿Qué deseas hacer con esta mesa vacía?", style: TextStyle(color: verdeNeon, fontWeight: FontWeight.bold))])),
            actionsAlignment: MainAxisAlignment.spaceEvenly,
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("MANTENERLA", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                onPressed: () async {
                  await db.collection('eventos').doc(widget.eventoId).collection('mesas').doc(widget.mesaId).delete();
                  await _registrarHistorial(widget.eventoId, "Mesa eliminada.");
                  if(ctx.mounted) Navigator.pop(ctx); 
                  if(context.mounted) Navigator.pop(context);
                }, child: const Text("ELIMINARLA", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900))
              )
            ],
          )
        );
      }
    } catch (e) { print(e); }
  }

  @override
  Widget build(BuildContext context) {
    double ancho = MediaQuery.of(context).size.width;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.nombreMesa, style: const TextStyle(color: verdeNeon, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1.5), overflow: TextOverflow.ellipsis), backgroundColor: Colors.transparent, elevation: 0,
        actions: [
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('eventos').doc(widget.eventoId).collection('mesas').doc(widget.mesaId).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasData && (snapshot.data!.data() as Map?)?['is_mesa_final'] == true) {
                return IconButton(icon: const Icon(Icons.emoji_events, color: Colors.amber, size: 28), onPressed: _mostrarPodio);
              }
              return const SizedBox.shrink();
            }
          ),
          IconButton(icon: const Icon(Icons.refresh, color: turquesaTema), tooltip: "Sincronizar y Refrescar", onPressed: () {
            _sincronizarMesaLocal();
            setState(() {});
          })
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              EventTimerBanner(eventoId: widget.eventoId),
              Expanded(
                child: StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance.collection('eventos').doc(widget.eventoId).collection('mesas').doc(widget.mesaId).snapshots(),
                  builder: (context, mesaSnapshot) {
                    if (!mesaSnapshot.hasData) return const Center(child: CircularProgressIndicator(color: verdeNeon));
                    var datosMesa = mesaSnapshot.data!.data() as Map<String, dynamic>? ?? {};

                    return StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance.collection('eventos').doc(widget.eventoId).collection('mesas').doc(widget.mesaId).collection('jugadores_activos').snapshots(),
                      builder: (context, snapshot) {
                        Map<int, Map<String, dynamic>> ocupados = {};
                        if (snapshot.hasData) for (var d in snapshot.data!.docs) { int? id = int.tryParse(d.id); if (id != null) ocupados[id] = {...d.data() as Map<String, dynamic>? ?? {}, 'doc_id': d.id}; }
                        
                        return SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                child: Column(
                                  children: [
                                    GestureDetector(onTap: _seleccionarDealer, child: CircleAvatar(radius: 40, backgroundColor: naranjaTema.withOpacity(0.1), child: Text(datosMesa['dealer_emoji']?.toString() ?? "🤵", style: const TextStyle(fontSize: 40)))),
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 4), 
                                      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(15), border: Border.all(color: verdeNeon.withOpacity(0.5))), 
                                      child: Text((datosMesa['dealer_apodo']?.toString() ?? "SIN DEALER").toUpperCase(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: verdeNeon, letterSpacing: 1))
                                    ),
                                    (datosMesa['dealer_ciudad'] != null && datosMesa['dealer_ciudad'].toString().trim().isNotEmpty) 
                                      ? Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Text("📍 ${datosMesa['dealer_ciudad']}", style: TextStyle(color: turquesaTema.withOpacity(0.8), fontSize: 11, fontWeight: FontWeight.bold)),
                                        )
                                      : const SizedBox.shrink(),
                                  ],
                                ),
                              ),
                              Container(
                                width: double.infinity, height: 480,
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final double cx = constraints.maxWidth / 2; final double cy = constraints.maxHeight / 2;
                                    final double rx = constraints.maxWidth * 0.28; final double ry = constraints.maxHeight * 0.22;
                                    return Stack(
                                      clipBehavior: Clip.none, alignment: Alignment.center,
                                      children: [
                                        Container(
                                          width: rx * 2.2, height: ry * 2.4,
                                          decoration: BoxDecoration(color: const Color(0xFF072B14), borderRadius: BorderRadius.all(Radius.elliptical(rx * 2.2, ry * 2.4)), border: Border.all(color: turquesaTema, width: 4), boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 40)]),
                                          child: Center(
                                            child: Opacity(
                                              opacity: 1.0,
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    "The",
                                                    style: GoogleFonts.dancingScript(
                                                      fontSize: 22, 
                                                      fontWeight: FontWeight.bold, 
                                                      color: naranjaTema, 
                                                      height: 0.8,
                                                      shadows: [const Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(2, 2))]
                                                    )
                                                  ),
                                                  Text(
                                                    "Croupier",
                                                    style: GoogleFonts.dancingScript(
                                                      fontSize: 38, 
                                                      fontWeight: FontWeight.bold, 
                                                      color: naranjaTema, 
                                                      height: 0.8,
                                                      shadows: [const Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(2, 2))]
                                                    )
                                                  ),
                                                ],
                                              )
                                            )
                                          ),
                                        ),
                                        ...List.generate(widget.aforoMesa, (i) {
                                          double angle = (2 * math.pi / widget.aforoMesa) * i + (math.pi / 2);
                                          return Positioned(left: cx + (rx * 1.5) * math.cos(angle) - 70, top: cy + (ry * 1.5) * math.sin(angle) - 47.5, child: _buildSeat(i, ocupados[i]));
                                        }),
                                      ],
                                    );
                                  }
                                ),
                              ),
                              
                              !isGuestMode ? Padding(
                                padding: const EdgeInsets.only(bottom: 40, top: 10),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    ElevatedButton.icon(
                                      onPressed: _llenarFormaAleatoria, icon: const Icon(Icons.shuffle, color: Colors.black), label: const Text("LLENAR", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.black)),
                                      style: ElevatedButton.styleFrom(backgroundColor: verdeNeon, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15)),
                                    ),
                                    const SizedBox(width: 10),
                                    ElevatedButton.icon(
                                      onPressed: _disolverMesa, icon: const Icon(Icons.delete_sweep, color: naranjaTema), label: const Text("DISOLVER", style: TextStyle(fontWeight: FontWeight.w900, color: naranjaTema)),
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: naranjaTema, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15)),
                                    ),
                                  ],
                                ),
                              ) : const SizedBox.shrink(),
                            ],
                          ),
                        );
                      },
                    );
                  }
                ),
              ),
            ],
          ),
          
          const FloatingLogo(), 
        ],
      )
    );
  }

  Widget _buildSeat(int index, Map<String, dynamic>? data) {
    if (data == null) {
      return GestureDetector(
        onTap: () => isGuestMode ? null : _sentarJugadorManual(index),
        child: Container(
          width: 140, height: 65, 
          decoration: BoxDecoration(color: const Color(0xFF151921), borderRadius: BorderRadius.circular(10), border: Border.all(color: naranjaTema.withOpacity(0.3), width: 1.5)),
          child: Stack(
            children: [
              Positioned(top: 5, right: 5, child: CircleAvatar(radius: 10, backgroundColor: naranjaTema, child: Text("${index + 1}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.black)))),
              const Center(child: Text("LIBRE", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: naranjaTema, letterSpacing: 2))),
            ],
          ),
        ),
      );
    }

    final Map<String, dynamic> jugador = data;
    String jClub = jugador.containsKey('club') && jugador['club'] != null ? jugador['club'].toString().trim() : '';
    String jCiudad = jugador.containsKey('ciudad') && jugador['ciudad'] != null ? jugador['ciudad'].toString().trim() : '';

    return GestureDetector(
      onTap: () => isGuestMode ? null : _abrirOpcionesJugador(index, jugador),
      child: Container(
        width: 140, height: 95, 
        decoration: BoxDecoration(color: const Color(0xFF151921), borderRadius: BorderRadius.circular(10), border: Border.all(color: turquesaTema, width: 1.5)),
        child: Stack(
          children: [
            Positioned(top: 5, right: 5, child: CircleAvatar(radius: 10, backgroundColor: verdeNeon, child: Text("${index + 1}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.black)))),
            Padding(
              padding: const EdgeInsets.all(6.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(jugador['emoji']?.toString() ?? '👤', style: const TextStyle(fontSize: 13)), 
                      const SizedBox(width: 4), 
                      Expanded(child: Text(jugador['nombre']?.toString() ?? 'Jugador', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: naranjaTema), maxLines: 1, overflow: TextOverflow.ellipsis))
                    ]
                  ),
                  Text('"${jugador['apodo']?.toString() ?? ''}"', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: turquesaTema, fontStyle: FontStyle.italic), maxLines: 1, overflow: TextOverflow.ellipsis),
                  
                  if (jClub.isNotEmpty) Text("🛡️ $jClub", style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.amber[400]), maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (jCiudad.isNotEmpty) Text("📍 $jCiudad", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey[400]), maxLines: 1, overflow: TextOverflow.ellipsis),

                  const Spacer(),
                  Row(
                    mainAxisSize: MainAxisSize.min, 
                    mainAxisAlignment: MainAxisAlignment.center, 
                    children: [
                      const FichaPokerIcon(color: verdeNeon, size: 14), 
                      const SizedBox(width: 4), 
                      Text("${jugador['fichas'] ?? 0}", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.white))
                    ]
                  ),
                ],
              ),
            ),
          ],
        ), 
      ),
    );
  }
}

// --- PANTALLA: DIRECTOR DE TORNEO (RELOJ GIGANTE) ---
class RelojDirectorScreen extends StatefulWidget {
  final String eventoId;
  final String nombreEvento;

  const RelojDirectorScreen({
    super.key, 
    required this.eventoId, 
    required this.nombreEvento
  });

  @override
  State<RelojDirectorScreen> createState() => _RelojDirectorScreenState();
}

class _RelojDirectorScreenState extends State<RelojDirectorScreen> {
  
  void _editarNivel(Map<String, dynamic> datosActuales) {
    if (isGuestMode) return;

    final nivelC = TextEditingController(text: (datosActuales['nivel'] ?? 1).toString());
    final ciegaPequenaC = TextEditingController(text: (datosActuales['ciega_pequena'] ?? 100).toString());
    final ciegaGrandeC = TextEditingController(text: (datosActuales['ciega_grande'] ?? 200).toString());
    final anteC = TextEditingController(text: (datosActuales['ante'] ?? 0).toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: verdeNeon)),
        title: const Text("⚙️ Editar Nivel", style: TextStyle(color: verdeNeon, fontWeight: FontWeight.w900)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nivelC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Nivel Actual", labelStyle: TextStyle(color: turquesaTema)), style: const TextStyle(color: naranjaTema, fontWeight: FontWeight.bold)),
            TextField(controller: ciegaPequenaC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Ciega Pequeña (SB)", labelStyle: TextStyle(color: turquesaTema)), style: const TextStyle(color: naranjaTema, fontWeight: FontWeight.bold)),
            TextField(controller: ciegaGrandeC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Ciega Grande (BB)", labelStyle: TextStyle(color: turquesaTema)), style: const TextStyle(color: naranjaTema, fontWeight: FontWeight.bold)),
            TextField(controller: anteC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Ante", labelStyle: TextStyle(color: turquesaTema)), style: const TextStyle(color: naranjaTema, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCELAR", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: verdeNeon),
            onPressed: () async {
              await FirebaseFirestore.instance.collection('eventos').doc(widget.eventoId).set({
                'nivel': int.tryParse(nivelC.text) ?? 1,
                'ciega_pequena': int.tryParse(ciegaPequenaC.text) ?? 100,
                'ciega_grande': int.tryParse(ciegaGrandeC.text) ?? 200,
                'ante': int.tryParse(anteC.text) ?? 0,
              }, SetOptions(merge: true));
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text("GUARDAR", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          )
        ],
      )
    );
  }

  Stream<Map<String, int>> _getJugadoresVivos() async* {
    yield* FirebaseFirestore.instance.collection('eventos').doc(widget.eventoId).snapshots().asyncMap((eventoSnap) async {
      var mesasSnap = await FirebaseFirestore.instance.collection('eventos').doc(widget.eventoId).collection('mesas').get();
      int jugadoresSentados = 0; 
      int totalJugadoresRoster = 0;

      if (eventoSnap.exists && eventoSnap.data() != null) {
        var data = eventoSnap.data()!;
        if (data.containsKey('jugadores_ids')) totalJugadoresRoster = (data['jugadores_ids'] as List).length;
      }

      for (var mesa in mesasSnap.docs) {
        var jugadoresSnap = await mesa.reference.collection('jugadores_activos').get();
        jugadoresSentados += jugadoresSnap.docs.length;
      }

      return {'vivos': jugadoresSentados, 'total': totalJugadoresRoster};
    });
  }

  @override
  Widget build(BuildContext context) {
    EventTimerManager.initEvent(widget.eventoId);

    return Scaffold(
      backgroundColor: Colors.black, 
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          "DIRECTOR DE TORNEO - ${widget.nombreEvento}", 
          style: const TextStyle(color: turquesaTema, fontWeight: FontWeight.w900, letterSpacing: 2)
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: verdeNeon),
        actions: [
          !isGuestMode 
            ? ValueListenableBuilder<bool>(
                valueListenable: EventTimerManager.runnings[widget.eventoId]!,
                builder: (context, running, child) {
                  return IconButton(
                    icon: Icon(running ? Icons.pause_circle_filled : Icons.play_circle_fill, color: verdeNeon, size: 35), 
                    onPressed: () => EventTimerManager.toggleTimer(widget.eventoId)
                  );
                }
              )
            : const SizedBox.shrink(),
          const SizedBox(width: 15),
        ],
      ),
      floatingActionButton: isGuestMode ? null : FloatingActionButton.extended(
        backgroundColor: Colors.amber,
        onPressed: () async {
          var doc = await FirebaseFirestore.instance.collection('eventos').doc(widget.eventoId).get();
          _editarNivel(doc.data() as Map<String, dynamic>? ?? {});
        }, 
        label: const Text("EDITAR NIVEL", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900)),
        icon: const Icon(Icons.settings, color: Colors.black),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Expanded(
              flex: 2,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF0B0D13),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: verdeNeon, width: 3),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 20)]
                ),
                child: Center(
                  child: ValueListenableBuilder<int>(
                    valueListenable: EventTimerManager.times[widget.eventoId]!,
                    builder: (context, time, child) {
                      String m = (time ~/ 60).toString().padLeft(2, '0'); 
                      String s = (time % 60).toString().padLeft(2, '0');
                      Color colorReloj = (time <= 60 && time > 0) ? Colors.redAccent : verdeNeon;
                      return Text(
                        "$m:$s", 
                        style: TextStyle(fontSize: 180, fontWeight: FontWeight.w900, color: colorReloj, fontFamily: 'monospace', letterSpacing: 5),
                      );
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              flex: 1,
              child: StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance.collection('eventos').doc(widget.eventoId).snapshots(),
                builder: (context, snapshotEvento) {
                  var dataEvento = snapshotEvento.data?.data() as Map<String, dynamic>? ?? {};
                  
                  String nivelStr = (dataEvento['nivel'] ?? 1).toString();
                  String ciegasStr = "${dataEvento['ciega_pequena'] ?? 100} / ${dataEvento['ciega_grande'] ?? 200}";
                  String anteStr = (dataEvento['ante'] ?? 0).toString();

                  return Row(
                    children: [
                      _crearPanelInfo("NIVEL", nivelStr, colorEspecial: Colors.amber),
                      const SizedBox(width: 15),
                      _crearPanelInfo("CIEGAS", ciegasStr),
                      const SizedBox(width: 15),
                      _crearPanelInfo("ANTE", anteStr),
                      const SizedBox(width: 15),
                      Expanded(
                        child: StreamBuilder<Map<String, int>>(
                          stream: _getJugadoresVivos(),
                          builder: (context, snapshotJugadores) {
                            int vivos = snapshotJugadores.hasData ? snapshotJugadores.data!['vivos']! : 0;
                            int total = snapshotJugadores.hasData ? snapshotJugadores.data!['total']! : 0;
                            return _crearPanelInfoInterno("VIVOS / TOTAL", "$vivos / $total");
                          }
                        )
                      )
                    ],
                  );
                }
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _crearPanelInfo(String titulo, String valor, {Color? colorEspecial}) {
    return Expanded(child: _crearPanelInfoInterno(titulo, valor, colorEspecial: colorEspecial));
  }

  Widget _crearPanelInfoInterno(String titulo, String valor, {Color? colorEspecial}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: colorEspecial ?? turquesaTema.withOpacity(0.5), width: 2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(titulo, style: TextStyle(color: colorEspecial ?? turquesaTema, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2)),
          const SizedBox(height: 10),
          Text(valor, style: const TextStyle(color: Colors.white, fontSize: 35, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}