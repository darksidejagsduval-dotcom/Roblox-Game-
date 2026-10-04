# Warren's Home Run Derby

A Roblox home run derby. Two scripts build everything in code: the stadium, the
ROBO-PITCHER 4000, the crowd, the shop, and the screen buttons.

| Script | Where it goes in Studio | File here |
| --- | --- | --- |
| `BaseballServer` (Script) | ServerScriptService | `src/server/BaseballServer.server.luau` |
| `BaseballClient` (LocalScript) | StarterPlayer > StarterPlayerScripts | `src/client/BaseballClient.client.luau` |

## Install

**Copy and paste (easiest):** open a new Baseplate place in Roblox Studio, then paste each
file into the place in the table above. Script 1 must be a **Script**; script 2 must be a
**LocalScript**.

**Rojo:** `rojo serve` with `default.project.json` puts the scripts in the same places
(inside folders named `Server` and `Client`).

To save baseballs and bats: publish the game, then Home > Game Settings > Security >
turn on "Enable Studio Access to API Services".

## Version 4

- Bigger field, 1.33x (1 stud = 1.5 ft): 330 ft down the lines, 400 ft to center. Hits fly
  1.155x faster, so home runs are just as easy as in version 3.
- Outfield bleachers full of fans. Home runs land in the crowd, with a glowing ring and the distance.
- ROBO-PITCHER 4000: an arm that winds up and whips the ball over the top, plus a screen
  that shows the pitch type and MPH. Seven pitches, including a knuckleball that wobbles.
- Full-body swing: load, stride, hip turn, back-foot pivot, both hands on the bat (R15 avatars).
  You can also paste a Toolbox animation ID into `SWING_ANIMATION_ID` in the client script.
- Works on computer, phone/tablet, and console. A badge shows which one the game detected.
  - Computer: click / Space / F swing, E shop, Q leave the box
  - Phone/tablet: big SWING button (or tap), SHOP and LEAVE BOX buttons
  - Console: R2 or A swing, Y shop, B leave the box
- Timing meter, strike zone, exit velocity and launch angle, golden balls (3x baseballs),
  home run streaks, round summary, a longest-home-run board, confetti, and a sunny-afternoon sky.

Settings (pitch speeds, rewards, shop items, crowd size, night game) are at the top of each script.

## Still to come

Base running, fielders who catch the ball, and a 2-player mode where a friend pitches.
