# Chesstus

A board game hub built in Godot 4.7. Instead of a menu, you walk a king around a giant chess board. Step onto a game square to propose that game to everyone connected.

Everything is drawn at runtime, except the chess pieces.

## Games

| Square | Game  | Status |
|--------|-------|--------|
| **C**  | Chess | Playable: full rules except promotion choice (auto-queens) and automatic draws (50-move, repetition, insufficient material). Resign and draw offers supported. Pick **Fischer Random** in the vote popup for a shuffled back rank (one of the 960 starts, the same for both players); castle by moving the king onto its rook |
| **Z**  | Crazyhouse | Chess where captured pieces join your hand and can be dropped on any empty square instead of moving (pawns not on the first or last rank). Promoted pieces go back to hand as pawns. Shows as **C** on the hub; not on the hub map yet |
| **B**  | Baby Chess | 5x5, each side: 5 pawns, rook, knight, bishop, queen, king. Orthodox rules: castling (king two squares toward the rook), en passant, pawn double step when the path is clear. Shows as **C** on the hub |
| **S**  | Superchess | 4 armies; modes picked in the vote popup: **2 players** (light vs dark, move any piece of either army; stalemate draws), **3 players** (one person runs the light team), **4 players (teams)** (White + Yellow vs Black + Red, clockwise), **Free for all** (house rule: mated armies leave, last king wins). [Official rules](https://www.chessvariants.com/multiplayer.dir/superchess.html); pawns auto-queen |
| **J**  | Shogi | Full rules: drops, optional promotion (a popup asks; forced when the piece would be stuck), no two pawns on a file, no checkmate by pawn drop. No repetition or impasse rules yet. Kanji pieces, captured pieces wait on each side's stand. Shows as **S** on the hub |
| **M**  | Minishogi | Shogi on 5x5 with one of each piece and a one-rank promotion zone. Shows as **S** on the hub |
| **Q**  | Quoridor | 9x9, 2 players with 10 walls each, or 4 with 5 each (pick in the vote popup; the 4 start on all four edges and take turns clockwise). Full rules: straight and diagonal jumps, no jumping two pawns, and no wall may cut a pawn off its goal. With 4 players, whoever resigns leaves and the rest play on. Easy and Medium bots |

## Future games

Ideas, roughly in order of how much existing code they can reuse.

| Game | Players | Why it fits |
|------|---------|-------------|
| **Bughouse** | 4 | Two Crazyhouse boards, teammates hand each other captured pieces. Fills all four seats; the drop rules are already in `ChessRules` |
| **Atomic Chess** | 2 | Captures explode, wiping out every non-pawn piece next to them. Blow up the king to win |
| **Horde** | 2 | Black's normal army against 36 white pawns. A different starting FEN plus a win rule |
| **Capablanca Chess** | 2 | 10x8 board with two new pieces: the archbishop (bishop + knight) and the chancellor (rook + knight) |
| **Grand Chess** | 2 | 10x10 with the archbishop and chancellor. Square, so it fits `ChessRules` where Capablanca's 10x8 doesn't |
| **Duck Chess** | 2 | After each move you also move a shared duck that blocks a square. No check: you win by taking the king |
| **Chad** | 2 | Christian Freeling's 12x12 variant: each side has just a king and eight rooks. The king can't leave its 3x3 castle, and rooks become queens inside the enemy's castle |
| **Hexagonal Chess** | 2 | Gliński's chess on a 91-cell hex board. A fresh board shape to draw |
| **Judkins Shogi** | 2 | 6x6, adds a knight to Minishogi's army. Just a new starting position for `ShogiRules` |
| **Tori Shogi** | 2 | 7x7 shogi where every piece is a bird (phoenix, falcon, cranes, swallows). Same drop rules, new moves |
| **Chu Shogi** | 2 | 12x12, 46 pieces each and no drops. Its lion moves twice in one turn |
| **Dai Shogi** | 2 | 15x15 ancestor of Chu Shogi, 65 pieces each |
| **Tenjiku Shogi** | 2 | 16x16 with pieces that jump over whole lines of others. Long, wild games |
| **Xiangqi** | 2 | Chinese chess: river, palace, cannons that jump to capture |
| **Janggi** | 2 | Korean chess: palaces like Xiangqi but no river, and you may pass. Build it alongside Xiangqi |
| **Makruk** | 2 | Thai chess: chess with weaker queen and bishops, pawns start on the third rank. Mostly `ChessRules` with new pieces |
| **Checkers** | 2 | Simple rules, forced captures and multi-jumps. A good first game outside the chess family |
| **Go** | 2 | 9x9 or 13x13; capture by surrounding. Needs territory scoring at the end |
| **Reversi** | 2 | Flip discs by flanking them. Tiny rules, easy bot |
| **Mancala (Oware)** | 2 | Sow seeds around a ring of pits and capture by landing in the right count. A new board shape, tiny rules |
| **Backgammon** | 2 | Dice, racing your pieces home, hitting lone pieces. Brings luck to the hub |
| **Chinese Checkers** | 2-4 | Star board, hop chains. Uses all four player colors |
| **Four-player chess** | 4 | Modern 14x14 four-army chess (free for all with points). Shares the board shape with Superchess |

## Controls

- **Hub:** arrow keys move your king one square per press (hold one arrow and tap another for diagonals). Black squares are walls.
- **Chess:** click a piece, then click a dot to move. Resign or offer a draw with the buttons under the board. Once the game is over, **Back to hub** (or Esc) returns both players.
- **Crazyhouse:** same as chess. Click a piece in your hand (right of the board), then a square to drop it.
- **Shogi:** same as chess. Click a piece on your stand to drop it.
- **Quoridor:** click a dot to move your pawn. Hover a groove between squares to preview a wall, then click to place it.

## Multiplayer

Up to 4 players (White, Black, Yellow and Red kings), peer-to-peer over ENet on **UDP port 7777**. Set your name in the hub's top bar (it's remembered). Players not seated in a game watch it; anyone joining mid-game waits in the hub.

1. One player clicks **Host** in the hub's top-left corner.
2. The other enters the host's IP address and clicks **Join**.
3. Both kings appear in the hub. When either player steps on a game square, everyone gets a popup to pick who plays which seat and vote. The game starts when everyone presses Play; one Decline cancels it.

Over the internet, the host either forwards UDP 7777 on their router, or both players install [Tailscale](https://tailscale.com) and join using the host's `100.x.x.x` address. Allow Godot through Windows Firewall when asked.

Without a connection, chess is two players on one screen.

Any seat can be a bot: pick **Bot (Easy)** or **Bot (Medium)** in the seat dropdown of the vote popup. Bots run on the host and play through the same validated moves as people. Easy plays randomly but grabs captures; Medium searches 3 moves ahead in chess and Minishogi, 2 in shogi, and weighs team material and hanging pieces in Superchess.

## Project layout

| File | Purpose |
|------|---------|
| `hub.gd` / `hub.tscn` | The hub board. `GAMES` registers game squares |
| `hub_map.gd` | Hub layout (`#` wall, `.` floor, `K` spawn, letters = games). Edit by hand or with the map editor |
| `map_editor.gd` | In-game map editor: press **F1** in the hub. Only available when running from the Godot editor, offline |
| `net.gd` | `Net` autoload: host/join, scene changes for both players, hub king positions |
| `chess_rules.gd` | `ChessRules`: chess position and legal move generation for any n x n board (chess, Baby Chess), plus Fischer Random castling and Crazyhouse drops, no UI |
| `chess.gd` / `chess.tscn` | Chess board UI. Moves are RPCs that each side checks for turn and legality |
| `babychess.tscn` | Baby Chess: the chess scene with the 5x5 starting position (`ChessRules.BABY`) |
| `crazyhouse.tscn` | Crazyhouse: the chess scene with a FEN that has a hand (`ChessRules.HOUSE`) |
| `quoridor_rules.gd` / `quoridor.gd` / `quoridor.tscn` | Quoridor rules (`QuoridorRules`, 2 or 4 players) and board UI |
| `test_quoridor_rules.gd` | Quoridor checks: jumps, wall overlap and path blocking, 4 player turns and resigning, bots |
| `test_variants.gd` | Fischer Random (start positions, castling) and Crazyhouse (hands, drops, drop mate) checks |
| `shogi_rules.gd` / `shogi.gd` / `shogi.tscn` | Shogi rules (`ShogiRules`, any n x n board) and board UI |
| `minishogi.tscn` | Minishogi: the shogi scene with the 5x5 starting position (`ShogiRules.MINI`) |
| `superchess_rules.gd` / `superchess.gd` / `superchess.tscn` | Superchess rules (`SuperchessRules`) and board UI |
| `test_chess_rules.gd` | Checks move generation against known move counts for standard test positions (perft) |
| `test_superchess_rules.gd` | Rule checks for Superchess (point pawns, hole, castling swap, partner check, mates, promotion, en passant) |
| `bots.gd` | Bot move pickers (`Bots`) for chess (and its variants), Superchess, shogi and Quoridor, run on a worker thread via `Net.think` |
| `test_bots.gd` | Bot sanity checks (finds mate in one, takes free pieces, won't hang its queen, speed) |
| `test_shogi_rules.gd` | Shogi and Minishogi perft counts plus drop, promotion, nifu and uchifuzume checks |
| `pieces/` | Chess piece SVGs |

## Adding a game

1. Make the scene, for example `checkers.tscn`.
2. Add its path to `SCENES` in `net.gd`.
3. Add an entry to `GAMES` in `hub.gd`, then place its letter with the map editor (it appears as a brush) or by hand in `hub_map.gd`.

Send moves through an `@rpc("any_peer", "call_local", "reliable")` function that validates the sender and the move, as `chess.gd` does.

## Tests

```sh
godot --headless --path . -s test_chess_rules.gd  # also test_superchess_rules.gd, test_shogi_rules.gd, test_bots.gd, test_quoridor_rules.gd, test_variants.gd
```

Prints `PASS` and exits 0 if the move counts match.

## Credits

Chess pieces by Colin M.L. Burnett ("Cburnett"), from Wikimedia Commons, used under the BSD license. See `pieces/CREDITS.txt`.
