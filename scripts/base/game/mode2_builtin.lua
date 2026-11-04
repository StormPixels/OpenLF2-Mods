-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- The layout blocks of LF2 Darkfiren's data/mode/mode2.dat (the 8P widescreen mode, 1018 wide): the menu positions, the
-- option panel, the time and cost lists and the soldiers of Battle mode, nothing else. ui_modes uses it when the game's
-- own mode2.dat cannot be read, so the "wide 1018" layout still works (and says so on the options page).
return [==[
<battle>
id: 30
id: 31
id: 33
id: 34
id: 39
id: 32
id: 35
id: 36
id: 37
<battle_end>
<misc>
battle_offset1: 140
battle_offset2: 114
text_y1: 110
text_y2: 128
background_small: 1
allow_defense: 1
music_x: 323
music_y: 3
hexf: 14186330
hexb: 10501922
frame_x: 531
frame_y: 4
small_x: 538
small_y: 11
respond: 5
pic: sprite\UI\MENU_CLIP2b.bmp
bound: 1
<misc_end>
<menu_control>
pic: sprite\UI\CHARMENU.bmp
start_x: 40
start_y: 33
face_x: 147
face_y: 94
name_x: 177
name_y: 219
fighter_x: 177
fighter_y: 241
team_x: 167
team_y: 263
centerx: 153
centery: 212
cost_x: 180
cost_y: 77
team_cmb_x: 147
team_cmb_y: 94
team1_cmb: sprite\UI\cb\t1.bmp
team2_cmb: sprite\UI\cb\t2.bmp
team3_cmb: sprite\UI\cb\t3.bmp
team4_cmb: sprite\UI\cb\t4.bmp
team5_cmb: sprite\UI\cb\t5.bmp
hidden: 1
transform: 1
respond: 0
row: 4
bound: 1
<menu_control_end>
<menu_small>
layer: 1        #fight
   small: sprite\UI\menu_small\b1.bmp    respond: 0   transparency: 1    x:  3     y: 3   h: 34
   head: sprite\UI\menu_small\n1.bmp
layer_end
layer: 2           #reset all
   small: sprite\UI\menu_small\b2.bmp    respond: 0   transparency: 1     x:  3     h: 24
   head: sprite\UI\menu_small\n2.bmp
layer_end
layer: 3        #reset random
   small: sprite\UI\menu_small\b3.bmp    respond: 0   transparency: 1   x:  3     h: 25       dx: 264   dy: 64
   smallb: sprite\UI\menu_small\m3b.bmp
   head: sprite\UI\menu_small\n3.bmp
layer_end
layer: 4        #background-stage
   small: sprite\UI\menu_small\b4.bmp    respond: 0   transparency: 1   x:  3        h: 25        dx: 174   dy: 91    next:  107  hex: 16751515
   head:  sprite\UI\menu_small\n4.bmp
   smallb: sprite\UI\menu_small\b4b.bmp
   smallc: sprite\UI\menu_small\n4b.bmp
  mode: 0
  mode: 1
  mode: 2
  mode: 3
  mode: 4
  mode: 5
layer_end
layer: 5        #difficulty
   small: sprite\UI\menu_small\b5.bmp    respond: 0  transparency: 1  x:  3      h: 23      dx:  174   dy:  4    dvx:  271   dvy: 37       hidden: 0
   head: sprite\UI\menu_small\n5.bmp
  mode: 0
  mode: 1
  mode: 2
  mode: 3
  mode: 4
  mode: 5
layer_end
layer: 6        #more-options
   small: sprite\UI\menu_small\b6d.bmp    respond: 0  transparency: 1  x:  3      h: 23     dx:  999   dy:  999    hidden: 0
   head: sprite\UI\menu_small\n6d.bmp
   smallb: sprite\UI\menu_small\b6e.bmp
   smallc: sprite\UI\menu_small\n6e.bmp
   smalld: sprite\UI\menu_small\m9b.bmp
  mode: 0
  mode: 1
  mode: 2
  mode: 3
  mode: 4
  mode: 5
layer_end
layer: 7        #bgmode
   small: sprite\UI\menu_small\b7.bmp    respond: 0  transparency: 1  x:  3       h: 26       dx: 174   dy: 5          hex: 16751515       hidden: 1  kind: 1
   smallb:  sprite\UI\menu_small\b7b.bmp
   smallc:  sprite\UI\menu_small\b7c.bmp
   head: sprite\UI\menu_small\n7.bmp
  mode: 0
  mode: 1
  mode: 2
  mode: 3
  mode: 4
  mode: 5
layer_end
layer: 8       #time
   small: sprite\UI\menu_small\b8.bmp    respond: 0  transparency: 1   x:  3      h: 26      dx: 174   dy: 5    dvx: 178     hex: 16751515     kind: 1
   smallb: sprite\UI\menu_small\b8b.bmp
   head: sprite\UI\menu_small\n8.bmp
  mode: 0
  mode: 1
  mode: 2
  mode: 3
  mode: 4
  mode: 5
layer_end
layer: 9       #costmode+cost-random
   small: sprite\UI\menu_small\b9.bmp    respond: 0  transparency: 1  x:  3    h: 25     dvx: 171   dx: 248  dy: 5    dvy: 5   hex: 16751515     kind: 1
   smallb: sprite\UI\menu_small\m9b.bmp
   head: sprite\UI\menu_small\n9.bmp
  mode: 0
  mode: 1
  mode: 2
  mode: 3
  mode: 4
  mode: 5
layer_end
layer: 10        #drop+transform+cost-random
   small: sprite\UI\menu_small\n10.bmp    respond: 0  transparency: 1  x:  3    h: 29    dy: 8   dx: 65    dvx: 151    next: 276       kind: 1
   smallb: sprite\UI\menu_small\n10b.bmp
   smallc: sprite\UI\menu_small\n10c.bmp
   smalld: sprite\UI\menu_small\b10b.bmp
   smallp: sprite\UI\menu_small\m9b.bmp
   head: sprite\UI\menu_small\b10.bmp
  mode: 0
  mode: 1
  mode: 2
  mode: 3
  mode: 4
  mode: 5
layer_end
layer: 11      #tumode
   small: sprite\UI\menu_small\b11.bmp    respond: 0   transparency: 1    x:  3      h: 21    dx:  271   fy:  17  hidden: 0     caughtact: 1  kind: 1
   head: sprite\UI\menu_small\n11.bmp
  mode: 0
  mode: 1
  mode: 2
  mode: 3
  mode: 4
  mode: 5
layer_end
layer: 12       #exit
   small: sprite\UI\menu_small\b12.bmp    respond: 0  transparency: 1    x:  3     h: 36
   head: sprite\UI\menu_small\n12.bmp
layer_end
<menu_small_end>
<mode>
layer: 1       #easy
    name: Easy   hex: 16751515
layer_end
layer: 2       #normal
    name: Normal   hex: 16751515
layer_end
layer: 3       #diificult
    name: Difficult    hex: 16751515
layer_end
layer: 4       #crazy
    name: CRAZY!    hex: 16751515
layer_end
layer: 5       #dummy
     name: dummy   hex: 16751515
layer_end
layer: 6       #hitlag1
     name:  _-1_  hex: 13158600
layer_end
layer: 7       #hitlag2
     name:  _-2_   hex: 13158600
layer_end
layer: 8       #hitlag3
     name:  _-3_  hex: 13158600
layer_end
layer: 9       #hitlag4
     name:  _-4_   hex: 13158600
layer_end
layer: 10       #hitlag5
     name:  _-5_  hex: 255
layer_end
layer: 11       #1tu
     name: 1tu   hex: 13158600
layer_end
layer: 12       #2tu
     name: 2tu   hex: 16751515
layer_end
<mode_end>
<grid_char>
pic: sprite\UI\grid\BOX_CHAR.bmp
small: sprite\UI\grid\RFACE_SMALL.bmp
pic_x: 760
pic_y: 45
start_x: 770
start_y: 60
rect: 16777215
row: 5
centerx: 45
centery: 66
h: 45
w: 40
name: 1
human_x: 12
human_y: 46
com_x: 7
com_y: 46
respond: 1
<grid_end>
<grid_stage>
pic: sprite\UI\grid\BOX_BGMODE.bmp
pic_x: 1
pic_y: 1
start_x: 30
start_y: 10
rect: 16777215
w: 212
h: 109
state: 2
row: 3
centerx: 260
centery: 135
next: 0
wait: 0
action: 540
effect: -540
name: 2
cover: 1
name_x: 25
name_y: 110
facing: 1
respond: 3
<grid_end>
<grid_bg>
pic: sprite\UI\grid\BOX_STAGE.bmp
small: sprite\UI\grid\BG_GRID_RANDOM.bmp
start_x: 25
start_y: 180
pic_x: 1
pic_y: 140
rect: 16777215
w: 212
h: 109
state: 1
row: 0
centerx: 260
centery: 0
next: 780
wait: -780
action: 0
effect: 0
name: 2
cover: 1
name_x: 25
name_y: 110
facing: 1
respond: 3
<grid_end>
<grid_bg_mode>
pic: sprite\UI\grid\BOX_BG.bmp
start_x: 220
start_y: 15
pic_x: 180
pic_y: 3
rect: 16777215
w: 212
h: 109
centerx: 0
centery: 135
row: 1
state: 2
next: 0
wait: 0
action: 540
effect: -540
name: 2
cover: 0
name_x: 250
name_y: 40
facing: 1
respond: 1
<grid_end>
<cost>
bound: 1
kind: 125
y: 38
dy: 54
team: 1
mode: 0
mode: 1
mode: 2
mode: 3
mode: 4
mode: 5
respond: 200
respond: 300
respond: 500
respond: 700
respond: 900
respond: 1200
respond: 1500
respond: 1800
respond: 2250
respond: 2500
respond: 5000
respond: 6000
respond: 8000
respond: 9999
cost: 25
id: 0
id: 3
cost_end:
cost: 50
id: 30
id: 31
id: 32
id: 33
id: 34
id: 35
id: 36
cost_end:
cost: 75
id: 37
id: 39
cost_end:
cost: 100
id: 1
id: 2
id: 4
id: 5
id: 6
id: 7
id: 8
id: 9
id: 10
id: 11
cost_end:
cost: 200
id: 38
id: 50
cost_end:
cost: 300
id: 51
id: 52
id: 53
id: 54
cost_end:
cost: 500
id: 55
id: 56
id: 57
id: 58
id: 59
cost_end:
random:
id: 1
id: 2
id: 4
id: 5
id: 6
id: 7
id: 8
id: 9
id: 10
id: 11
random_end:
random:
id: 30
id: 31
random_end:
random:
id: 38
id: 50
id: 51
id: 52
random_end:
<cost_end>
<time>
type: 3
time: 15
time: 30
time: 60
time: 90
time: 120
time: 150
time: 240
time: 165
time: 180
time: 195
time: 210
time: 225
time: 240
time: 265
time: 280
time: 600
time: 1200
time: 1500
time: 1800
time: 2100
time: 2500
time: 5000
<time_end>
]==]
