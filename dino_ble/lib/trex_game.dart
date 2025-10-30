import 'dart:ui';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/flame.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flame/text.dart';
import 'package:flutter/material.dart' hide Image;
import 'package:flutter/services.dart';
import 'package:terx_dino/background/horizon.dart';
import 'package:terx_dino/game_over.dart';
import 'package:terx_dino/player.dart';

// Enum representing different game states
enum GameState { playing, intro, gameOver }

class TRexGame extends FlameGame with KeyboardEvents, TapCallbacks, HasCollisionDetection {
  // Singleton pattern: Ensures only one instance of the game exists
  static final TRexGame _instance = TRexGame._internal();
  factory TRexGame() => _instance;
  static TRexGame get instance => _instance;
  TRexGame._internal();

  // Game assets and UI elements
  late final Image spriteImage;
  late final Player player;
  late final Horizon horizon;
  late final GameOverPanel gameOverPanel;
  late final TextComponent scoreText;

  @override
  Color backgroundColor() => const Color(0xFFFFFFFF); // White background

  // Game score tracking
  int _score = 0;
  int _highScore = 0;

  int get score => _score;
  set score(int newScore) {
    _score = newScore;
    scoreText.text = '${scoreString(_score)}  HI ${scoreString(_highScore)}';
  }

  // Formats score as a five-digit string
  String scoreString(int score) => score.toString().padLeft(5, '0');

  // Distance tracking for scoring and game speed
  double _distanceTraveled = 0;

  @override
  Future<void> onLoad() async {
    debugPrint("Game loading assets...");

    // Load game sprite sheet
    spriteImage = await Flame.images.load('trex.png');

    // Initialize game objects
    player = Player();
    horizon = Horizon();
    gameOverPanel = GameOverPanel();

    // Add components to the game world
    add(horizon);
    add(player);
    add(gameOverPanel);

    // Load custom font for score display
    const chars = '0123456789HI ';
    final renderer = SpriteFontRenderer.fromFont(
      SpriteFont(
        source: spriteImage,
        size: 23,
        ascent: 23,
        glyphs: [
          for (var i = 0; i < chars.length; i++)
            Glyph(chars[i], left: 954.0 + 20 * i, top: 0, width: 20),
        ],
      ),
      letterSpacing: 2,
    );

    // Create score display
    add(
      scoreText = TextComponent(
        position: Vector2(30, 40),
        textRenderer: renderer,
      ),
    );

    score = 0; // Initialize score
    debugPrint("Game assets loaded successfully.");
  }

  // Tracks current game state
  GameState state = GameState.intro;

  // Game speed variables
  double currentSpeed = 0.0;
  double timePlaying = 0.0;
  final double acceleration = 10;
  final double maxSpeed = 1500.0;
  final double startSpeed = 400;

  bool get isPlaying => state == GameState.playing;
  bool get isGameOver => state == GameState.gameOver;
  bool get isIntro => state == GameState.intro;

  @override
  KeyEventResult onKeyEvent(
      KeyEvent event,
      Set<LogicalKeyboardKey> keysPressed,
      ) {
    if (keysPressed.contains(LogicalKeyboardKey.enter) ||
        keysPressed.contains(LogicalKeyboardKey.space)) {
      debugPrint("Key pressed: Jump action triggered");
      onAction();
    }
    return KeyEventResult.handled;
  }

  @override
  void onTapDown(TapDownEvent event) {
    debugPrint("Screen tapped: Jump action triggered");
    onAction();
  }

  // Handles user input for jumping or restarting the game
  void onAction() {
    if (isGameOver || isIntro) {
      debugPrint("Game is in ${state.toString()}, restarting...");
      restart();
      return;
    }
    debugPrint("Jumping at speed: $currentSpeed");
    player.jump(currentSpeed);
  }

  // Called by BLE trigger to make the dino jump
  void triggerJump() {
    debugPrint("triggerJump(): isPlaying is $isPlaying, state is $state");

    if (isIntro || isGameOver) {
      debugPrint("Starting game because it was not playing");
      restart();
    } else {
      debugPrint("Triggering jump...");
      player.jump(currentSpeed);
    }
  }

  // Handles game over state
  void gameOver() {
    debugPrint("Game Over! Final score: $_score");
    gameOverPanel.visible = true;
    state = GameState.gameOver;
    player.current = PlayerState.crashed;
    currentSpeed = 0.0;
  }

  // Resets the game to the initial state
  void restart() {
    debugPrint("Restarting game...");
    state = GameState.playing;
    player.reset();
    horizon.reset();
    currentSpeed = startSpeed;
    gameOverPanel.visible = false;
    timePlaying = 0.0;
    if (score > _highScore) {
      _highScore = score;
      debugPrint("New high score: $_highScore");
    }
    score = 0;
    _distanceTraveled = 0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (isGameOver) return;

    if (isPlaying) {
      timePlaying += dt;
      _distanceTraveled += dt * currentSpeed;
      score = _distanceTraveled ~/ 50; // Update score based on distance

      // Increase speed gradually up to max speed
      if (currentSpeed < maxSpeed) {
        currentSpeed += acceleration * dt;
      }
    }
  }
}
