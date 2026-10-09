part of 'coup_game.dart';

/// One card in front of a player. Revealed cards are lost influence.
class Influence {
  const Influence(this.character, {this.revealed = false});

  final Character character;
  final bool revealed;
}

/// A player's coins and cards. Only [CoupGame] can change them.
class Player {
  Player._(this.id, {required int coins, required List<Character> hand})
    : _coins = coins,
      _influences = [for (final c in hand) Influence(c)];

  Player._restore(this.id, this._coins, this._influences);

  final String id;
  int _coins;
  final List<Influence> _influences;

  int get coins => _coins;
  List<Influence> get influences => List.unmodifiable(_influences);

  List<Character> get hiddenCharacters => [
    for (final i in _influences)
      if (!i.revealed) i.character,
  ];

  bool get isAlive => _influences.any((i) => !i.revealed);
  bool hasHidden(Character character) => hiddenCharacters.contains(character);

  void _reveal(Character character) {
    final index = _hiddenIndexOf(character);
    _influences[index] = Influence(character, revealed: true);
  }

  void _swapHidden(Character from, Character to) {
    _influences[_hiddenIndexOf(from)] = Influence(to);
  }

  void _replaceHidden(List<Character> characters) {
    _influences
      ..removeWhere((i) => !i.revealed)
      ..addAll(characters.map(Influence.new));
  }

  int _hiddenIndexOf(Character character) =>
      _influences.indexWhere((i) => !i.revealed && i.character == character);
}
