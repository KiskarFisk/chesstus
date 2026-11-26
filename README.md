# Chesstus

A board game hub built in Godot 4.7. Instead of a menu, you walk a king around a giant chess board. Step onto a game square to propose that game to everyone connected.

Everything is drawn at runtime, except the chess pieces.

## Games

| Square | Game  | Status |
|--------|-------|--------|
| **C**  | Chess | Playable: full rules except promotion choice (auto-queens) and automatic draws (50-move, repetition, insufficient material). Resign and draw offers supported |
| **B**  | Baby Chess | 5x5, each side: 5 pawns, rook, knight, bishop, queen, king. Orthodox rules: castling (king two squares toward the rook), en passant, pawn double step when the path is clear. Shows as **C** on the hub |
| **S**  | Superchess | 4 armies; modes picked in the vote popup: **2 players** (light vs dark, move any piece of either army; stalemate draws), **3 players** (one person runs the light team), **4 players (teams)** (White + Yellow vs Black + Red, clockwise), **Free for all** (house rule: mated armies leave, last king wins). [Official rules](https://www.chessvariants.com/multiplayer.dir/superchess.html); pawns auto-queen |

## Controls

- **Hub:** arrow keys move your king one square per press (hold one arrow and tap another for diagonals). Black squares are walls.
- **Chess:** click a piece, then click a dot to move. Resign or offer a draw with the buttons under the board. Once the game is over, **Back to hub** (or Esc) returns both players.

## Multiplayer

Up to 4 players (White, Black, Yellow and Red kings), peer-to-peer over ENet on **UDP port 7777**. Set your name in the hub's top bar (it's remembered). Players not seated in a game watch it; anyone joining mid-game waits in the hub.

1. One player clicks **Host** in the hub's top-left corner.
2. The other enters the host's IP address and clicks **Join**.
3. Both kings appear in the hub. When either player steps on a game square, everyone gets a popup to pick who plays which seat and vote. The game starts when everyone presses Play; one Decline cancels it.

Over the internet, the host either forwards UDP 7777 on their router, or both players install [Tailscale](https://tailscale.com) and join using the host's `100.x.x.x` address. Allow Godot through Windows Firewall when asked.

Without a connection, chess is two players on one screen.

Any seat can be a bot: pick **Bot (Easy)** or **Bot (Medium)** in the seat dropdown of the vote popup. Bots run on the host and play through the same validated moves as people. Easy plays randomly but grabs captures; Medium searches 3 moves ahead in chess and weighs team material and hanging pieces in Superchess.

## Project layout

| File | Purpose |
|------|---------|
| `hub.gd` / `hub.tscn` | The hub board. `GAMES` registers game squares |
| `hub_map.gd` | Hub layout (`#` wall, `.` floor, `K` spawn, letters = games). Edit by hand or with the map editor |
| `map_editor.gd` | In-game map editor: press **F1** in the hub. Only available when running from the Godot editor, offline |
| `net.gd` | `Net` autoload: host/join, scene changes for both players, hub king positions |
| `chess_rules.gd` | `ChessRules`: chess position and legal move generation for any n x n board (chess, Baby Chess), no UI |
| `chess.gd` / `chess.tscn` | Chess board UI. Moves are RPCs that each side checks for turn and legality |
| `babychess.tscn` | Baby Chess: the chess scene with the 5x5 starting position (`ChessRules.BABY`) |
| `superchess_rules.gd` / `superchess.gd` / `superchess.tscn` | Superchess rules (`SuperchessRules`) and board UI |
| `test_chess_rules.gd` | Checks move generation against known move counts for standard test positions (perft) |
| `test_superchess_rules.gd` | Rule checks for Superchess (point pawns, hole, castling swap, partner check, mates, promotion, en passant) |
| `bots.gd` | Bot move pickers (`Bots`) for chess and Superchess, run on a worker thread via `Net.think` |
| `test_bots.gd` | Bot sanity checks (finds mate in one, takes free pieces, won't hang its queen, speed) |
| `pieces/` | Chess piece SVGs |

## Adding a game

1. Make the scene, for example `checkers.tscn`.
2. Add its path to `SCENES` in `net.gd`.
3. Add an entry to `GAMES` in `hub.gd`, then place its letter with the map editor (it appears as a brush) or by hand in `hub_map.gd`.

Send moves through an `@rpc("any_peer", "call_local", "reliable")` function that validates the sender and the move, as `chess.gd` does.

## Tests

```sh
godot --headless --path . -s test_chess_rules.gd
```

Prints `PASS` and exits 0 if the move counts match.

## Credits

Chess pieces by Colin M.L. Burnett ("Cburnett"), from Wikimedia Commons, used under the BSD license. See `pieces/CREDITS.txt`.
