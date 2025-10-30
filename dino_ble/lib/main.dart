import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:terx_dino/trex_widget.dart';
import 'package:terx_dino/trex_game.dart';

void main() {
  debugPrint("App: Starting Flutter Dino BLE...");
  runApp(const MyApp());
}

/// The root widget of the application.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint("MyApp: Building MaterialApp...");
    return MaterialApp(
      debugShowCheckedModeBanner: false, // Hides the DEBUG banner in release mode
      theme: ThemeData(
        primaryColor: Colors.black, // Consistent theme with a black primary color
      ),
      home: BluetoothConnector(), // Main screen to handle Bluetooth connection
    );
  }
}

/// Handles Bluetooth scanning, connection, and game launch.
class BluetoothConnector extends StatefulWidget {
  const BluetoothConnector({super.key});

  @override
  State<BluetoothConnector> createState() => _BluetoothConnectorState();
}

class _BluetoothConnectorState extends State<BluetoothConnector> {
  final _ble = FlutterReactiveBle(); // BLE instance to handle scanning and connections
  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<ConnectionStateUpdate>? _connectSub;
  StreamSubscription<List<int>>? _notifySub;

  bool _found = false; // Tracks whether the target device has been found
  bool _connected = false; // Tracks connection status

  @override
  void initState() {
    super.initState();
    debugPrint("BluetoothConnector: Initializing... Requesting permissions.");
    _requestPermissions().then((granted) {
      if (granted) {
        debugPrint("BluetoothConnector: Permissions granted. Starting BLE scan...");
        _scanSub = _ble.scanForDevices(withServices: []).listen(_onScanUpdate);
      } else {
        debugPrint("BluetoothConnector: Permissions not granted. Cannot scan for devices.");
      }
    });
  }

  /// Requests necessary Bluetooth permissions (e.g., location).
  Future<bool> _requestPermissions() async {
    final status = await Permission.location.request();
    return status.isGranted;
  }

  @override
  void dispose() {
    debugPrint("BluetoothConnector: Cleaning up subscriptions...");
    _notifySub?.cancel();
    _connectSub?.cancel();
    _scanSub?.cancel();
    super.dispose();
  }

  /// Handles device discovery during scanning.
  void _onScanUpdate(DiscoveredDevice d) {
    debugPrint("BluetoothConnector: Found device -> ${d.name} (${d.id})");
    // Check if the discovered device is the one we're looking for
    if (d.name == 'DinoController' && !_found) {
      debugPrint("BluetoothConnector: Target device found! Stopping scan and connecting...");
      _found = true; // Mark the device as found
      // Stop scanning to save resources
      _scanSub?.cancel();
      _scanSub = null;
      // Cancel any existing connection attempt before starting a new one
      _connectSub?.cancel();
      // Attempt to connect to the found device
      _connectSub = _ble.connectToDevice(
        id: d.id,
        connectionTimeout: const Duration(seconds: 10),
        servicesWithCharacteristicsToDiscover: {
          Uuid.parse("00002A57-0000-1000-8000-00805F9B34FB"): [
            Uuid.parse("00002902-0000-1000-8000-00805F9B34FB")
          ]
        },
      ).listen((update) {
        debugPrint("BluetoothConnector: Connection state -> ${update.connectionState}");
        if (update.connectionState == DeviceConnectionState.connected) {
          debugPrint("BluetoothConnector: Successfully connected to device.");
          _onConnected(d.id);
        } else if (update.connectionState == DeviceConnectionState.disconnected) {
          debugPrint("BluetoothConnector: Device disconnected.");
          // Clean up active subscriptions
          _notifySub?.cancel();
          _connectSub?.cancel();
          if (mounted) {
            setState(() => _connected = false);
          }
          // Allow scanning again if needed
          _found = false;
        }
      });
    }
  }

  /// Handles logic after successful connection.
  void _onConnected(String deviceId) {
    debugPrint("BluetoothConnector: Connected to device -> $deviceId");
    final characteristic = QualifiedCharacteristic(
      deviceId: deviceId,
      serviceId: Uuid.parse('00002A57-0000-1000-8000-00805F9B34FB'),
      characteristicId: Uuid.parse('00002902-0000-1000-8000-00805F9B34FB'),
    );
    // Cancel previous notifications before subscribing
    _notifySub?.cancel();
    debugPrint("BluetoothConnector: Subscribing to characteristic...");
    _notifySub = _ble.subscribeToCharacteristic(characteristic).listen((bytes) {
      if (bytes.isNotEmpty) {
        final int value = bytes[0];
        debugPrint("BluetoothConnector: Data received -> $value");
        if (value == 1) {
          debugPrint("BluetoothConnector: Triggering the jump...");
          TRexGame.instance?.triggerJump();
        }
      } else {
        debugPrint("BluetoothConnector: No data received!");
      }
    });

    if (mounted) {
      setState(() => _connected = true);
    }

    // Show dialog after connection
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint("BluetoothConnector: Showing connection dialog...");
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Bluetooth Connected"),
          content: const Text("You can now play the game!"),
          actions: [
            TextButton(
              onPressed: () {
                debugPrint("BluetoothConnector: Launching game...");
                SystemChrome.setPreferredOrientations([
                  DeviceOrientation.landscapeLeft,
                  DeviceOrientation.landscapeRight,
                ]);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => TerxWidget()),
                );
              },
              child: const Text("Start Game"),
            ),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    debugPrint("BluetoothConnector: Building UI...");
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(40), // Reduced AppBar height
        child: AppBar(
          title: const Text(
            "Dino BLE Game",
            style: TextStyle(color: Colors.white, fontSize: 16), // Smaller font for better UI
          ),
          centerTitle: true,
          backgroundColor: Colors.black,
        ),
      ),
      body: Container(
        color: Colors.white,
        child: Center(
          child: _connected
              ? const Text(
            "Connected! Launching game...",
            style: TextStyle(color: Colors.black),
          )
              : const CircularProgressIndicator(
            color: Colors.black,
          ),
        ),
      ),
    );
  }
}
