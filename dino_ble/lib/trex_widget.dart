import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import 'package:terx_dino/trex_game.dart';
import 'package:flutter/services.dart';

class TerxWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Locking screen orientation to landscape mode
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]).then((_) => debugPrint("Screen orientation set to landscape mode"));

    debugPrint("Building TerxWidget...");

    return Scaffold(
      body: Container(
        color: Colors.white, // White background for a clean UI
        child: Center(
          child: SizedBox.expand( // Ensures the game takes up the full screen
            child: GameWidget(game: TRexGame()), // Embeds the Flame game
          ),
        ),
      ),
    );
  }
}
