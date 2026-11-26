# Chesstus

A board game hub built in Godot 4.7. Instead of a menu, you walk a king around a giant chess board. Step onto a game square to start that game with whoever is connected.

Everything is drawn at runtime, except the chess pieces.

## Games

| Square | Game  | Status |
|--------|-------|--------|
| **C**  | Chess | Playable: full rules except promotion choice (auto-queens) and automatic draws (50-move, repetition, insufficient material) |

## Controls

- **Hub:** arrow keys move your king (hold two arrows for diagonals). Black squares are walls.
- **Chess:** click a piece, then click a dot to move. **Esc** returns both players to the hub.

## Multiplayer

Two players, peer-to-peer over ENet on **UDP port 7777**. The host plays White and the joiner plays Black.

1. One player clicks **Host** in the hub's top-left corner.
2. The other enters the host's IP address and clicks **Join**.
3. Both kings appear in the hub. When either player steps on a game square, both players go to that game.

Over the internet, the host either forwards UDP 7777 on their router, or both players install [Tailscale](https://tailscale.com) and join using the host's `100.x.x.x` address. Allow Godot through Windows Firewall when asked.

Without a connection, chess is two players on one screen.

## Project layout

| File | Purpose |
|------|---------|
| `hub.gd` / `hub.tscn` | The hub board. Edit `MAP` to change the layout (`#` wall, `.` floor, `K` spawn, letters = games) and `GAMES` to register a game square |
| `net.gd` | `Net` autoload: host/join, scene changes for both players, hub king positions |
| `chess_rules.gd` | `ChessRules`: chess position and legal move generation, no UI |
| `chess.gd` / `chess.tscn` | Chess board UI. Moves are RPCs that each side checks for turn and legality |
| `test_chess_rules.gd` | Checks move generation against known move counts for standard test positions (perft) |
| `pieces/` | Chess piece SVGs |

## Adding a game

1. Make the scene, for example `checkers.tscn`.
2. Add its path to `SCENES` in `net.gd`.
3. Add an entry to `GAMES` in `hub.gd` and put its letter somewhere in `MAP`.

Send moves through an `@rpc("any_peer", "call_local", "reliable")` function that validates the sender and the move, as `chess.gd` does.

## Tests

```sh
godot --headless --path . -s test_chess_rules.gd
```

Prints `PASS` and exits 0 if the move counts match.

## Credits

Chess pieces by Colin M.L. Burnett ("Cburnett"), from Wikimedia Commons, used under the BSD license. See `pieces/CREDITS.txt`.
