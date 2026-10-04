# Warren's Home Run Derby

A Roblox home run derby. Four scripts build everything in code: the stadium, the
ROBO-PITCHER 4000, the crowd, the shop, the screen buttons, the swing, and the sprint.

| Script | Where it goes in Studio | File here |
| --- | --- | --- |
| 1. `BaseballServer` (Script) | ServerScriptService | `src/server/BaseballServer.server.luau` |
| 2. `BaseballClient` (LocalScript) | StarterPlayer > StarterPlayerScripts | `src/client/BaseballClient.client.luau` |
| 3. `SwingAnimation` (ModuleScript, name must match) | ReplicatedStorage | `src/shared/SwingAnimation.luau` |
| 4. `RunAnimation` (LocalScript) | StarterPlayer > StarterPlayerScripts | `src/client/RunAnimation.client.luau` |

## Install

**Open the game file (easiest):** open `HomeRunDerby.rbxlx` in Roblox Studio and press Play. All 4 scripts are already in place.

**Copy and paste:** open a new Baseplate place in Roblox Studio, then paste each
file into the place in the table above, as the kind of script the table says.

**Rojo:** `rojo serve` with `default.project.json` puts the scripts in the same places
(inside folders named `Server`, `Client`, and `Shared`; Script 2 finds `SwingAnimation` inside `Shared`).

To save baseballs and bats: publish the game, then Home > Game Settings > Security >
turn on "Enable Studio Access to API Services".

## Version 4

- Bigger field, 1.33x (1 stud = 1.5 ft): 330 ft down the lines, 400 ft to center. Hits fly
  1.155x faster, so home runs are just as easy as in version 3.
- Outfield bleachers full of fans. Home runs land in the crowd, with a glowing ring and the distance.
- ROBO-PITCHER 4000: an arm that winds up and whips the ball over the top, plus a screen
  that shows the pitch type and MPH. Seven pitches, including a knuckleball that wobbles.
- Full-body swing in its own script (SwingAnimation): load, stride, hip turn, back-foot pivot,
  both hands on the bat (R15 avatars). The poses are numbers at the top you can change. You can
  also paste a Toolbox animation ID into `SWING_ANIMATION_ID` in the client script.
- Sprint animation in its own script (RunAnimation): forward lean, knee drive, arms pumping, for
  every player. Made in code, so no animation ID or permissions are needed.
- Works on computer, phone/tablet, and console. A badge shows which one the game detected.
  - Computer: click / Space / F swing, E shop, Q leave the box
  - Phone/tablet: big SWING button (or tap), SHOP and LEAVE BOX buttons
  - Console: R2 or A swing, Y shop, B leave the box
- Timing meter, strike zone, exit velocity and launch angle, golden balls (3x baseballs),
  home run streaks, round summary, a longest-home-run board, confetti, and a sunny-afternoon sky.

Settings (pitch speeds, rewards, shop items, crowd size, night game) are at the top of each script.

## Still to come

Base running, fielders who catch the ball, and a 2-player mode where a friend pitches.
