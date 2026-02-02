/// Carpal Tunnel Syndrome Physical Therapy App
/// 
/// A Flutter application for guided wrist flexion exercises that integrates
/// with a Python-based hand tracking backend. Designed for rehabilitation
/// and physical therapy with emphasis on stability, accessibility, and
/// medical-appropriate UX.
/// 
/// Architecture:
/// - Material Design 3 with custom medical-friendly theme
/// - ValueNotifier-based state management for real-time sensor updates
/// - Websocket communication with Python backend
/// - Multi-screen onboarding and exercise flow
/// - Graceful error handling and offline states

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ============================================================================
// MAIN ENTRY POINT
// ============================================================================

void main() {
  // Ensure Flutter binding is initialized before running app
  WidgetsFlutterBinding.ensureInitialized();
  
  // Lock orientation to portrait for consistent therapy experience
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  // Set system UI overlay style (status bar, navigation bar)
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xFFF8F9FA),
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  
  runApp(const CarpalTunnelTherapyApp());
}

// ============================================================================
// ROOT APPLICATION WIDGET
// ============================================================================

/// Root widget that configures the MaterialApp with medical-appropriate theming
class CarpalTunnelTherapyApp extends StatelessWidget {
  const CarpalTunnelTherapyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wrist Flexion Therapy',
      debugShowCheckedModeBanner: false,
      
      // Theme configured for medical/therapeutic context:
      // - Calm, professional colors (soft blues and greens)
      // - High contrast for accessibility
      // - Large touch targets
      // - Clear, readable typography
      theme: ThemeData(
        useMaterial3: true,
        
        // Primary color: Calm teal-blue (trust, medical, calming)
        primaryColor: const Color(0xFF2D6A7D),
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
        
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF2D6A7D),
          secondary: Color(0xFF4A9D8F),
          tertiary: Color(0xFF7AB8A8),
          surface: Colors.white,
          error: Color(0xFFE07A5F),
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: Color(0xFF2C3E50),
          onError: Colors.white,
        ),
        
        // Typography: Clear, readable, medical-appropriate
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w600,
            color: Color(0xFF2C3E50),
            height: 1.2,
          ),
          displayMedium: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            color: Color(0xFF2C3E50),
            height: 1.2,
          ),
          headlineMedium: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w500,
            color: Color(0xFF2C3E50),
          ),
          titleLarge: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w500,
            color: Color(0xFF2C3E50),
          ),
          bodyLarge: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w400,
            color: Color(0xFF34495E),
            height: 1.5,
          ),
          bodyMedium: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w400,
            color: Color(0xFF34495E),
            height: 1.5,
          ),
          labelLarge: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        
        // Elevated button style: Large, clear, easy to tap
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(200, 56),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 2,
          ),
        ),
        
        // Card style: Soft, elevated, medical-clean
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          color: Colors.white,
        ),
      ),
      
      // Start with onboarding/home screen
      home: const HomeScreen(),
    );
  }
}

// ============================================================================
// DATA MODELS
// ============================================================================

/// Represents the real-time state received from Python backend
class ExerciseData {
  final double currentAngle;          // Current wrist flexion angle in degrees
  final double targetAngleForward;    // Target angle for forward flexion
  final double targetAngleBackward;   // Target angle for backward extension
  final int repetitionsCompleted;     // Reps completed this session
  final int repetitionsLastSession;   // Reps from previous session (soft goal)
  final bool isForwardDirection;      // True = forward flexion, False = backward
  final bool isArmed;                 // Whether system is ready for next rep
  final String? warningMessage;       // Warning text (hand drift, alignment, etc)
  final bool hasLeveledUp;            // Whether user just leveled up
  
  const ExerciseData({
    required this.currentAngle,
    required this.targetAngleForward,
    required this.targetAngleBackward,
    required this.repetitionsCompleted,
    required this.repetitionsLastSession,
    required this.isForwardDirection,
    required this.isArmed,
    this.warningMessage,
    this.hasLeveledUp = false,
  });
  
  /// Default/empty state when no data available
  factory ExerciseData.empty() {
    return const ExerciseData(
      currentAngle: 0.0,
      targetAngleForward: 30.0,
      targetAngleBackward: 15.0,
      repetitionsCompleted: 0,
      repetitionsLastSession: 0,
      isForwardDirection: true,
      isArmed: true,
    );
  }
  
  /// Parse from JSON received from Python backend
  /// 
  /// Expected JSON structure:
  /// {
  ///   "angle": 45.5,
  ///   "target_forward": 30,
  ///   "target_backward": 15,
  ///   "reps": 3,
  ///   "reps_last": 8,
  ///   "direction": "forward",
  ///   "armed": true,
  ///   "warning": "Keep your hand straight",
  ///   "level_up": false
  /// }
  factory ExerciseData.fromJson(Map<String, dynamic> json) {
    return ExerciseData(
      currentAngle: (json['angle'] ?? 0.0).toDouble(),
      targetAngleForward: (json['target_forward'] ?? 30.0).toDouble(),
      targetAngleBackward: (json['target_backward'] ?? 15.0).toDouble(),
      repetitionsCompleted: json['reps'] ?? 0,
      repetitionsLastSession: json['reps_last'] ?? 0,
      isForwardDirection: json['direction'] == 'forward',
      isArmed: json['armed'] ?? true,
      warningMessage: json['warning'],
      hasLeveledUp: json['level_up'] ?? false,
    );
  }
  
  /// Get current target angle based on direction
  double get currentTarget => isForwardDirection ? targetAngleForward : targetAngleBackward;
  
  /// Get direction as human-readable string
  String get directionText => isForwardDirection ? 'Forward' : 'Backward';
}

/// Represents connection state with Python backend
enum ConnectionState {
  disconnected,   // Not connected, initial state
  connecting,     // Attempting to connect
  connected,      // Successfully connected and receiving data
  error,          // Connection error occurred
}

// ============================================================================
// BACKEND COMMUNICATION SERVICE
// ============================================================================

/// Manages websocket connection to Python backend and real-time data updates
/// 
/// This service:
/// - Establishes websocket connection to Python server
/// - Parses incoming JSON exercise data
/// - Notifies listeners of state changes
/// - Handles reconnection on failure
/// - Provides graceful degradation if backend unavailable
class BackendService {
  // WebSocket connection instance (null when disconnected)
  WebSocket? _socket;
  
  // Connection state notifier
  final ValueNotifier<ConnectionState> connectionState = 
      ValueNotifier(ConnectionState.disconnected);
  
  // Latest exercise data notifier
  final ValueNotifier<ExerciseData> exerciseData = 
      ValueNotifier(ExerciseData.empty());
  
  // Reconnection timer
  Timer? _reconnectTimer;
  
  // Python backend websocket server address
  // ASSUMPTION: Python script runs a websocket server on localhost:8765
  // User must start Python script before launching Flutter app
  static const String _serverAddress = 'ws://localhost:8765';
  
  /// Connect to Python backend websocket server
  Future<void> connect() async {
    if (connectionState.value == ConnectionState.connecting || 
        connectionState.value == ConnectionState.connected) {
      return; // Already connecting or connected
    }
    
    connectionState.value = ConnectionState.connecting;
    
    try {
      // Attempt websocket connection with 5 second timeout
      _socket = await WebSocket.connect(_serverAddress)
          .timeout(const Duration(seconds: 5));
      
      connectionState.value = ConnectionState.connected;
      
      // Listen to incoming data stream
      _socket!.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDisconnect,
        cancelOnError: false,
      );
      
    } catch (e) {
      connectionState.value = ConnectionState.error;
      _scheduleReconnect();
    }
  }
  
  /// Handle incoming message from Python backend
  void _handleMessage(dynamic message) {
    try {
      // Parse JSON message
      final Map<String, dynamic> data = jsonDecode(message as String);
      
      // Update exercise data
      exerciseData.value = ExerciseData.fromJson(data);
      
    } catch (e) {
      // Invalid JSON - log but don't crash
      debugPrint('Error parsing message from backend: $e');
    }
  }
  
  /// Handle connection error
  void _handleError(dynamic error) {
    debugPrint('Backend connection error: $error');
    connectionState.value = ConnectionState.error;
    _scheduleReconnect();
  }
  
  /// Handle connection closed
  void _handleDisconnect() {
    debugPrint('Backend connection closed');
    connectionState.value = ConnectionState.disconnected;
    _socket = null;
    _scheduleReconnect();
  }
  
  /// Schedule automatic reconnection attempt
  void _scheduleReconnect() {
    // Cancel any existing reconnect timer
    _reconnectTimer?.cancel();
    
    // Try to reconnect after 3 seconds
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (connectionState.value != ConnectionState.connected) {
        connect();
      }
    });
  }
  
  /// Send command to Python backend (e.g., level up, toggle direction)
  void sendCommand(String command) {
    if (_socket != null && connectionState.value == ConnectionState.connected) {
      _socket!.add(jsonEncode({'command': command}));
    }
  }
  
  /// Clean up resources
  void dispose() {
    _reconnectTimer?.cancel();
    _socket?.close();
    connectionState.dispose();
    exerciseData.dispose();
  }
}

// ============================================================================
// HOME SCREEN (Entry Point / Onboarding)
// ============================================================================

/// Home screen with welcome message and navigation to onboarding or exercise
class HomeScreen extends StatelessWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // App icon/logo
              Icon(
                Icons.healing_rounded,
                size: 80,
                color: Theme.of(context).colorScheme.primary,
              ),
              
              const SizedBox(height: 32),
              
              // Title
              Text(
                'Wrist Flexion\nTherapy',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displayLarge,
              ),
              
              const SizedBox(height: 16),
              
              // Subtitle
              Text(
                'Guided exercises for carpal tunnel syndrome recovery',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
              
              const SizedBox(height: 48),
              
              // Continue to onboarding button
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const OnboardingFlow()),
                  );
                },
                child: const Text('Begin'),
              ),
              
              const SizedBox(height: 16),
              
              // Skip to exercise (for returning users)
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ExerciseScreen()),
                  );
                },
                child: const Text('Skip to Exercise'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// ONBOARDING FLOW
// ============================================================================

/// Multi-step onboarding flow that guides users through baseline calibration
/// 
/// Based on the TODO in Python file:
/// 1. Welcome screen
/// 2. Instructions for forward flexion test
/// 3. Forward flexion baseline measurement
/// 4. Instructions for backward extension test
/// 5. Backward extension baseline measurement
/// 6. Completion and transition to exercise
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({Key? key}) : super(key: key);

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  
  // Backend service for receiving angle data during calibration
  final BackendService _backendService = BackendService();
  
  @override
  void initState() {
    super.initState();
    // Connect to backend when onboarding starts
    _backendService.connect();
  }
  
  @override
  void dispose() {
    _pageController.dispose();
    _backendService.dispose();
    super.dispose();
  }
  
  void _nextPage() {
    if (_currentPage < 6) {
      _pageController.animateToPage(
        _currentPage + 1,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    } else {
      // Onboarding complete - navigate to exercise
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const ExerciseScreen()),
      );
    }
  }
  
  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.animateToPage(
        _currentPage - 1,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: _currentPage > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _previousPage,
              )
            : null,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Progress indicator
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: LinearProgressIndicator(
                value: (_currentPage + 1) / 7,
                backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).colorScheme.primary,
                ),
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            
            // Page content
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(), // Disable swipe
                onPageChanged: (page) => setState(() => _currentPage = page),
                children: [
                  _buildWelcomePage(),
                  _buildInstructionPage(
                    title: 'Let\'s Begin',
                    description: 'When you click on NEXT you will start the introduction to training to strengthen your muscles and aid in your carpal tunnel recovery process.',
                  ),
                  _buildInstructionPage(
                    title: 'Forward Flexion Test',
                    description: 'Hold hand in ___ position and move hand ___ way',
                    showImage: true,
                  ),
                  _buildMeasurementPage(isForward: true),
                  _buildInstructionPage(
                    title: 'Backward Extension Test',
                    description: 'Now that you know how to do the task we will calculate your baseline repetitions and angle of wrist flexion and you will begin your journey towards recovery.',
                  ),
                  _buildMeasurementPage(isForward: false),
                  _buildCompletionPage(),
                ],
              ),
            ),
            
            // Navigation buttons
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_currentPage > 0)
                    TextButton(
                      onPressed: _previousPage,
                      child: const Text('PREVIOUS'),
                    )
                  else
                    const SizedBox.shrink(),
                  
                  ElevatedButton(
                    onPressed: _nextPage,
                    child: Text(_currentPage == 6 ? 'BEGIN' : 'NEXT'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildWelcomePage() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Friendly greeting with date
          Text(
            'Hi! How are you doing today?',
            style: Theme.of(context).textTheme.displayMedium,
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 24),
          
          // Calendar widget showing current date
          _buildCalendarWidget(),
          
          const SizedBox(height: 32),
          
          // Journey progress placeholder
          Text(
            'Your Journey',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          _buildJourneyProgress(),
        ],
      ),
    );
  }
  
  Widget _buildCalendarWidget() {
    final now = DateTime.now();
    final monthNames = ['January', 'February', 'March', 'April', 'May', 'June',
                       'July', 'August', 'September', 'October', 'November', 'December'];
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              '${monthNames[now.month - 1]} ${now.year}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            // Simple calendar grid (current month)
            _buildSimpleCalendar(now),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSimpleCalendar(DateTime date) {
    // Days of week header
    final daysOfWeek = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    
    // Calculate first day of month and number of days
    final firstDay = DateTime(date.year, date.month, 1);
    final lastDay = DateTime(date.year, date.month + 1, 0);
    final daysInMonth = lastDay.day;
    final startWeekday = firstDay.weekday % 7; // Sunday = 0
    
    return Column(
      children: [
        // Header row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: daysOfWeek.map((day) => SizedBox(
            width: 32,
            child: Text(
              day,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          )).toList(),
        ),
        const SizedBox(height: 8),
        // Calendar grid
        ...List.generate(6, (weekIndex) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(7, (dayIndex) {
              final dayNumber = weekIndex * 7 + dayIndex - startWeekday + 1;
              final isCurrentDay = dayNumber == date.day;
              final isValidDay = dayNumber > 0 && dayNumber <= daysInMonth;
              
              return SizedBox(
                width: 32,
                height: 32,
                child: isValidDay
                    ? Container(
                        decoration: BoxDecoration(
                          color: isCurrentDay
                              ? Theme.of(context).colorScheme.primary
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '$dayNumber',
                          style: TextStyle(
                            color: isCurrentDay ? Colors.white : null,
                            fontWeight: isCurrentDay ? FontWeight.w600 : null,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              );
            }),
          );
        }),
      ],
    );
  }
  
  Widget _buildJourneyProgress() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'To-do List:',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text('Complete baseline calibration'),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildInstructionPage({
    required String title,
    required String description,
    bool showImage = false,
  }) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.displayMedium,
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 32),
          
          if (showImage)
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.image_outlined,
                      size: 60,
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '*IMAGE OF\nEXERCISE\nSTEPS *',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          
          if (showImage) const SizedBox(height: 32),
          
          Text(
            description,
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
  
  Widget _buildMeasurementPage({required bool isForward}) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Baseline Measurement',
            style: Theme.of(context).textTheme.displayMedium,
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 24),
          
          Text(
            isForward
                ? 'Now that you know how to do the task we will record where you are right now. Flex your wrist to the maximum of your abilities for 2 seconds 5 times.'
                : 'After completing this task we will calculate your baseline repetitions and angle of wrist flexion and you will begin your journey towards recovery.',
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 48),
          
          // Live angle visualization during calibration
          ValueListenableBuilder<ExerciseData>(
            valueListenable: _backendService.exerciseData,
            builder: (context, data, _) {
              return _CalibrationVisualizer(
                currentAngle: data.currentAngle,
                isForward: isForward,
              );
            },
          ),
          
          const SizedBox(height: 24),
          
          // Instructions
          Text(
            'Hold position for 2 seconds',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildCompletionPage() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.celebration_rounded,
            size: 80,
            color: Theme.of(context).colorScheme.primary,
          ),
          
          const SizedBox(height: 32),
          
          Text(
            'You have just completed your baseline testing! Congratulations on beginning your journey towards recovery!',
            style: Theme.of(context).textTheme.displayMedium,
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 48),
          
          // Ready message
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              'Click BEGIN when you are ready to complete the baseline measurement activity.',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// CALIBRATION VISUALIZER WIDGET
// ============================================================================

/// Visual feedback during baseline calibration showing current wrist angle
class _CalibrationVisualizer extends StatelessWidget {
  final double currentAngle;
  final bool isForward;
  
  const _CalibrationVisualizer({
    required this.currentAngle,
    required this.isForward,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      height: 200,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Hand icon placeholder
          Icon(
            Icons.back_hand_outlined,
            size: 60,
            color: Theme.of(context).colorScheme.primary,
          ),
          
          const SizedBox(height: 16),
          
          // Current angle display
          Text(
            '${currentAngle.toStringAsFixed(1)}°',
            style: Theme.of(context).textTheme.displayLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          
          const SizedBox(height: 8),
          
          Text(
            isForward ? 'Forward Flexion' : 'Backward Extension',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// EXERCISE SCREEN (Main Training Interface)
// ============================================================================

/// Main exercise screen with real-time feedback and rep counting
/// 
/// This screen:
/// - Connects to Python backend via websocket
/// - Displays live wrist angle visualization
/// - Shows target angle indicators
/// - Counts repetitions
/// - Provides audio/visual feedback on successful reps
/// - Handles direction switching and level ups
/// - Shows warnings for improper form
class ExerciseScreen extends StatefulWidget {
  const ExerciseScreen({Key? key}) : super(key: key);

  @override
  State<ExerciseScreen> createState() => _ExerciseScreenState();
}

class _ExerciseScreenState extends State<ExerciseScreen> with TickerProviderStateMixin {
  final BackendService _backendService = BackendService();
  
  // Animation controllers for smooth transitions
  late AnimationController _repAnimationController;
  late AnimationController _levelUpAnimationController;
  
  // Track level up message display
  bool _showLevelUpMessage = false;
  Timer? _levelUpMessageTimer;
  
  @override
  void initState() {
    super.initState();
    
    // Initialize animation controllers
    _repAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    
    _levelUpAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    
    // Connect to backend
    _backendService.connect();
    
    // Listen for level up events
    _backendService.exerciseData.addListener(_handleExerciseDataUpdate);
  }
  
  void _handleExerciseDataUpdate() {
    final data = _backendService.exerciseData.value;
    
    // Trigger rep animation when new rep is detected
    // (This would be indicated by rep count increase - we'd need to track previous value)
    
    // Show level up message when detected
    if (data.hasLeveledUp && !_showLevelUpMessage) {
      setState(() => _showLevelUpMessage = true);
      _levelUpAnimationController.forward(from: 0);
      
      // Hide message after 2 seconds
      _levelUpMessageTimer?.cancel();
      _levelUpMessageTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() => _showLevelUpMessage = false);
        }
      });
    }
  }
  
  @override
  void dispose() {
    _repAnimationController.dispose();
    _levelUpAnimationController.dispose();
    _levelUpMessageTimer?.cancel();
    _backendService.exerciseData.removeListener(_handleExerciseDataUpdate);
    _backendService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wrist Flexion Exercise'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        actions: [
          // Connection status indicator
          ValueListenableBuilder<ConnectionState>(
            valueListenable: _backendService.connectionState,
            builder: (context, state, _) {
              return Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: Center(
                  child: _ConnectionStatusIndicator(state: state),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ValueListenableBuilder<ConnectionState>(
          valueListenable: _backendService.connectionState,
          builder: (context, connectionState, _) {
            // Show appropriate UI based on connection state
            if (connectionState == ConnectionState.disconnected ||
                connectionState == ConnectionState.connecting) {
              return _buildConnectingState();
            } else if (connectionState == ConnectionState.error) {
              return _buildErrorState();
            }
            
            // Connected - show exercise interface
            return ValueListenableBuilder<ExerciseData>(
              valueListenable: _backendService.exerciseData,
              builder: (context, data, _) {
                return _buildExerciseInterface(data);
              },
            );
          },
        ),
      ),
    );
  }
  
  Widget _buildConnectingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(
            'Connecting to camera...',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          Text(
            'Make sure the Python tracking program is running',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
  
  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 80,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 24),
            Text(
              'Connection Failed',
              style: Theme.of(context).textTheme.displayMedium,
            ),
            const SizedBox(height: 16),
            Text(
              'Unable to connect to the hand tracking system.\n\n'
              'Please ensure:\n'
              '• Python tracking program is running\n'
              '• Camera is connected and accessible\n'
              '• Websocket server is on port 8765',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => _backendService.connect(),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry Connection'),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildExerciseInterface(ExerciseData data) {
    return Stack(
      children: [
        Column(
          children: [
            // Warning message area (hand drift, alignment issues)
            if (data.warningMessage != null)
              _buildWarningBanner(data.warningMessage!),
            
            // Main exercise area
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    // Current direction and target
                    _buildDirectionIndicator(data),
                    
                    const SizedBox(height: 32),
                    
                    // Angle visualizer (main focal point)
                    _buildAngleVisualizer(data),
                    
                    const SizedBox(height: 32),
                    
                    // Rep counter
                    _buildRepCounter(data),
                    
                    const SizedBox(height: 32),
                    
                    // Target angles for both directions
                    _buildTargetAnglesInfo(data),
                  ],
                ),
              ),
            ),
            
            // Control buttons
            _buildControlButtons(data),
          ],
        ),
        
        // Level up overlay message
        if (_showLevelUpMessage)
          _buildLevelUpOverlay(data),
      ],
    );
  }
  
  Widget _buildWarningBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error.withOpacity(0.1),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.error.withOpacity(0.3),
            width: 2,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDirectionIndicator(ExerciseData data) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            data.isForwardDirection
                ? Icons.arrow_downward_rounded
                : Icons.arrow_upward_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Text(
            '${data.directionText} Flexion',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildAngleVisualizer(ExerciseData data) {
    // Calculate progress toward target (0-1)
    final progress = (data.currentAngle / data.currentTarget).clamp(0.0, 1.0);
    
    // Determine if in target zone
    final isInTargetZone = (data.currentAngle - data.currentTarget).abs() <= 0.75;
    
    return Card(
      elevation: 4,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32.0),
        child: Column(
          children: [
            // Current angle display (large, primary focus)
            Text(
              '${data.currentAngle.toStringAsFixed(1)}°',
              style: Theme.of(context).textTheme.displayLarge?.copyWith(
                fontSize: 64,
                fontWeight: FontWeight.w700,
                color: isInTargetZone
                    ? Theme.of(context).colorScheme.secondary
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
            
            const SizedBox(height: 8),
            
            Text(
              'Current Angle',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            
            const SizedBox(height: 32),
            
            // Visual progress bar
            _buildProgressBar(progress, isInTargetZone),
            
            const SizedBox(height: 16),
            
            // Target angle indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '0° (Neutral)',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  'Target: ${data.currentTarget.toStringAsFixed(0)}°',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildProgressBar(double progress, bool isInTargetZone) {
    return SizedBox(
      height: 24,
      child: Stack(
        children: [
          // Background track
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          
          // Progress fill
          FractionallySizedBox(
            widthFactor: progress,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isInTargetZone
                      ? [
                          Theme.of(context).colorScheme.secondary,
                          Theme.of(context).colorScheme.tertiary,
                        ]
                      : [
                          Theme.of(context).colorScheme.primary,
                          Theme.of(context).colorScheme.primary.withOpacity(0.7),
                        ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          
          // Target zone indicator (vertical line at target)
          Positioned(
            left: MediaQuery.of(context).size.width * 0.7 - 64, // Approximate target position
            child: Container(
              width: 3,
              height: 24,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildRepCounter(ExerciseData data) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Text(
              'Repetitions',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            
            const SizedBox(height: 16),
            
            // Current reps (large display)
            Text(
              '${data.repetitionsCompleted}',
              style: Theme.of(context).textTheme.displayLarge?.copyWith(
                fontSize: 72,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            
            // Last session comparison (if available)
            if (data.repetitionsLastSession > 0) ...[
              const SizedBox(height: 8),
              Text(
                'Last session: ${data.repetitionsLastSession}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ],
            
            // Progress toward level up
            if (data.repetitionsCompleted > 0) ...[
              const SizedBox(height: 24),
              _buildLevelUpProgress(data.repetitionsCompleted),
            ],
          ],
        ),
      ),
    );
  }
  
  Widget _buildLevelUpProgress(int currentReps) {
    const repsNeeded = 5; // From Python: NUM_REPS_TO_LEVEL_UP
    final progress = (currentReps % repsNeeded) / repsNeeded;
    
    return Column(
      children: [
        LinearProgressIndicator(
          value: progress,
          backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
          valueColor: AlwaysStoppedAnimation<Color>(
            Theme.of(context).colorScheme.secondary,
          ),
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
        ),
        const SizedBox(height: 8),
        Text(
          '${currentReps % repsNeeded}/$repsNeeded reps to level up',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.secondary,
          ),
        ),
      ],
    );
  }
  
  Widget _buildTargetAnglesInfo(ExerciseData data) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Target Angles',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildAngleInfoChip(
                    label: 'Forward',
                    angle: data.targetAngleForward,
                    isActive: data.isForwardDirection,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildAngleInfoChip(
                    label: 'Backward',
                    angle: data.targetAngleBackward,
                    isActive: !data.isForwardDirection,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildAngleInfoChip({
    required String label,
    required double angle,
    required bool isActive,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isActive
            ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
            : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isActive
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: isActive
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${angle.toStringAsFixed(0)}°',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: isActive
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildControlButtons(ExerciseData data) {
    return Container(
      padding: const EdgeInsets.all(24.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Toggle direction button
          OutlinedButton.icon(
            onPressed: () => _backendService.sendCommand('toggle_direction'),
            icon: Icon(
              data.isForwardDirection
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
            ),
            label: Text('Switch to ${data.isForwardDirection ? "Backward" : "Forward"}'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Level up button
          ElevatedButton.icon(
            onPressed: () => _backendService.sendCommand('level_up'),
            icon: const Icon(Icons.trending_up_rounded),
            label: const Text('Level Up'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
          
          const SizedBox(height: 12),
          
          // End session button
          TextButton(
            onPressed: () => _showEndSessionDialog(),
            child: const Text('End Session'),
          ),
        ],
      ),
    );
  }
  
  Widget _buildLevelUpOverlay(ExerciseData data) {
    return Positioned.fill(
      child: FadeTransition(
        opacity: _levelUpAnimationController,
        child: Container(
          color: Colors.black.withOpacity(0.7),
          child: Center(
            child: ScaleTransition(
              scale: CurvedAnimation(
                parent: _levelUpAnimationController,
                curve: Curves.elasticOut,
              ),
              child: Container(
                margin: const EdgeInsets.all(48),
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.celebration_rounded,
                      size: 64,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Level Up!',
                      style: Theme.of(context).textTheme.displayMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'New ${data.directionText} target: ${data.currentTarget.toStringAsFixed(0)}°',
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  void _showEndSessionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End Session?'),
        content: const Text(
          'Are you sure you want to end this exercise session? '
          'Your progress will be saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              _backendService.sendCommand('quit');
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Return to home
            },
            child: const Text('End Session'),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// CONNECTION STATUS INDICATOR
// ============================================================================

/// Small widget showing connection status with appropriate icon and color
class _ConnectionStatusIndicator extends StatelessWidget {
  final ConnectionState state;
  
  const _ConnectionStatusIndicator({required this.state});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;
    
    switch (state) {
      case ConnectionState.disconnected:
        icon = Icons.cloud_off_rounded;
        color = Colors.grey;
        break;
      case ConnectionState.connecting:
        icon = Icons.cloud_sync_rounded;
        color = Colors.orange;
        break;
      case ConnectionState.connected:
        icon = Icons.cloud_done_rounded;
        color = Colors.green;
        break;
      case ConnectionState.error:
        icon = Icons.error_rounded;
        color = Colors.red;
        break;
    }
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 4),
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }
}