-- DARK ROOM
-- Agent 28 (Wave 3) -- Minimalist sonar horror
-- One ping. One entity. One exit. Pure darkness.

local W, H = 160, 120
local TILE = 8
local COLS, ROWS = 20, 15
local SONAR_CD = 24
local SONAR_SPD = 2.2
local SONAR_MAX = 72
local MOVE_DLY = 5

-- 2-bit palette
local BLK, DRK, LIT, WHT = 0, 1, 2, 3

-- Tile types
local EMPTY, WALL, EXIT = 0, 1, 2

-- Channels
local CH_S, CH_A, CH_H, CH_F = 0, 1, 2, 3

-- State
local scene, frame, s
local px, py, move_t
local ex, ey, e_tx, e_ty, e_spd, e_chase, e_alert_x, e_alert_y
local e_accx, e_accy, e_step_t, e_patrol_t
local sonar_t, sonar_r, sonar_on, particles
local alive, room_num, room_map
local scare_fl, shake_t, shake_x, shake_y
local death_t, victory_t
local hb_rate, hb_t
local amb_drip, amb_creak
local title_t, title_idle, demo_on, demo_t, demo_step, demo_path
local paused

----------------------------------------------------------------
-- UTILS
----------------------------------------------------------------
local function dist(x1,y1,x2,y2)
  local dx,dy=x1-x2,y1-y2; return math.sqrt(dx*dx+dy*dy)
end
local function clamp(v,lo,hi)
  if v<lo then return lo end; if v>hi then return hi end; return v
end
local function lerp(a,b,t) return a+(b-a)*t end
local function tile(tx,ty)
  if ty<0 or ty>=ROWS or tx<0 or tx>=COLS then return WALL end
  return room_map[ty][tx]
end

----------------------------------------------------------------
-- ROOMS (minimalist: walls + exit)
----------------------------------------------------------------
local function make_border()
  local m={}
  for y=0,ROWS-1 do m[y]={}
    for x=0,COLS-1 do
      m[y][x]=(y==0 or y==ROWS-1 or x==0 or x==COLS-1) and WALL or EMPTY
    end
  end
  return m
end

local function room1()
  local m=make_border()
  -- Vertical wall with gap
  for y=1,10 do m[y][10]=WALL end
  -- Horizontal wall
  for x=10,15 do m[8][x]=WALL end
  -- Pillars
  m[4][4]=WALL; m[4][7]=WALL; m[10][5]=WALL; m[10][15]=WALL
  -- Exit
  m[13][18]=EXIT
  return m, 2, 7, 17, 3
end

local function room2()
  local m=make_border()
  -- Maze corridors
  for y=0,10 do m[y][5]=WALL end
  for y=4,14 do m[y][10]=WALL end
  for y=0,8 do m[y][15]=WALL end
  for x=5,10 do m[4][x]=WALL end
  for x=10,15 do m[10][x]=WALL end
  -- Exit
  m[13][17]=EXIT
  return m, 2, 12, 17, 2
end

local function room3()
  local m=make_border()
  -- Cross pattern
  for x=3,17 do m[7][x]=WALL end
  for y=2,12 do m[y][10]=WALL end
  -- Openings in cross
  m[7][6]=EMPTY; m[7][14]=EMPTY; m[5][10]=EMPTY; m[10][10]=EMPTY
  -- Corner pillars
  m[3][4]=WALL; m[11][4]=WALL; m[3][16]=WALL; m[11][16]=WALL
  -- Exit bottom center
  m[13][10]=EXIT
  return m, 2, 4, 17, 11
end

----------------------------------------------------------------
-- SOUNDS
----------------------------------------------------------------
local function sfx_ping()
  wave(CH_S,"sine"); tone(CH_S,1200,400,0.15)
end
local function sfx_step(alt)
  wave(CH_F,"triangle")
  tone(CH_F, alt and 80 or 70, alt and 60 or 50, 0.03)
end
local function sfx_bump()
  noise(CH_F,0.04)
end
local function sfx_exit()
  wave(CH_S,"sine"); tone(CH_S,400,1200,0.3)
  wave(CH_A,"sine"); tone(CH_A,600,1400,0.3)
end
local function sfx_entity_step(d)
  if d>15 then return end
  local t=clamp(1-d/15,0,1)
  wave(CH_F,"square")
  tone(CH_F, lerp(200,100,t), lerp(200,100,t)*0.8, lerp(0.01,0.04,t))
end
local function sfx_growl()
  wave(CH_A,"sawtooth"); tone(CH_A,45,35,0.12)
end
local function sfx_jumpscare()
  noise(CH_S,0.2); wave(CH_A,"sawtooth"); tone(CH_A,80,40,0.3)
  noise(CH_F,0.15); wave(CH_H,"square"); tone(CH_H,100,50,0.25)
end
local function sfx_heartbeat(i)
  wave(CH_H,"sine"); local b=lerp(50,70,i); tone(CH_H,b,b*0.7,0.06)
end
local function sfx_drip()
  wave(CH_A,"sine"); tone(CH_A,1200+math.random(800),600,0.02)
end
local function sfx_creak()
  wave(CH_A,"sawtooth")
  local f=({55,62,48,70})[math.random(4)]
  tone(CH_A,f,f*0.8,0.1)
end
local function sfx_victory()
  wave(0,"sine"); tone(0,400,800,0.2)
  wave(1,"sine"); tone(1,600,1200,0.2)
end
local function sfx_alert()
  wave(CH_A,"square"); tone(CH_A,120,80,0.08)
end

----------------------------------------------------------------
-- LOAD ROOM
----------------------------------------------------------------
local function load_room(n)
  local m, ppx, ppy, eex, eey
  if n==1 then m,ppx,ppy,eex,eey=room1()
  elseif n==2 then m,ppx,ppy,eex,eey=room2()
  else m,ppx,ppy,eex,eey=room3() end
  room_map=m; px=ppx; py=ppy; ex=eex; ey=eey
  e_tx=eex; e_ty=eey; e_spd=0.02+n*0.008
  e_chase=false; e_alert_x=-1; e_alert_y=-1
  e_accx=0; e_accy=0; e_step_t=0; e_patrol_t=0
  sonar_on=false; sonar_r=0; sonar_t=0; particles={}
  alive=true; scare_fl=0; shake_t=0; shake_x=0; shake_y=0
  death_t=0; hb_rate=0; hb_t=0
end

----------------------------------------------------------------
-- ENTITY AI
----------------------------------------------------------------
local function update_entity()
  if not alive then return end
  local d=dist(px,py,ex,ey)

  -- Behavior
  if e_alert_x>=0 then
    e_chase=true; e_tx=e_alert_x; e_ty=e_alert_y
    if dist(ex,ey,e_alert_x,e_alert_y)<2 then
      e_alert_x=-1; e_alert_y=-1; e_patrol_t=120
    end
  elseif d<4 then
    e_chase=true; e_tx=px; e_ty=py
  elseif e_patrol_t>0 then
    e_patrol_t=e_patrol_t-1
    if frame%60==0 then
      e_tx=clamp(ex+math.random(-4,4),1,COLS-2)
      e_ty=clamp(ey+math.random(-4,4),1,ROWS-2)
    end
  else
    e_chase=false
    if frame%90==0 then
      e_tx=math.random(2,COLS-3); e_ty=math.random(2,ROWS-3)
    end
  end

  -- Move
  local spd=e_chase and (e_spd*1.8) or e_spd
  local dx,dy=e_tx-ex, e_ty-ey
  local td=dist(ex,ey,e_tx,e_ty)
  if td>0.5 then
    e_accx=e_accx+(dx/td)*spd; e_accy=e_accy+(dy/td)*spd
    local sx,sy=0,0
    if math.abs(e_accx)>=1 then sx=e_accx>0 and 1 or -1; e_accx=e_accx-sx end
    if math.abs(e_accy)>=1 then sy=e_accy>0 and 1 or -1; e_accy=e_accy-sy end
    if sx~=0 then
      local nx=math.floor(ex+sx)
      if nx>=0 and nx<COLS and room_map[math.floor(ey)] and room_map[math.floor(ey)][nx]~=WALL then
        ex=ex+sx
      end
    end
    if sy~=0 then
      local ny=math.floor(ey+sy)
      if ny>=0 and ny<ROWS and room_map[ny] and room_map[ny][math.floor(ex)]~=WALL then
        ey=ey+sy
      end
    end
  end

  -- Sounds
  e_step_t=e_step_t+1
  if e_step_t>=(e_chase and 12 or 20) then
    e_step_t=0; sfx_entity_step(d)
  end
  if e_chase and d<6 and frame%40==0 then sfx_growl() end

  -- Catch player
  if d<1.5 then
    sfx_jumpscare(); scare_fl=12; shake_t=15; alive=false; death_t=0
  end
  -- Random scare when close
  if d<3 and math.random(100)<4 and scare_fl<=0 then
    scare_fl=3; shake_t=4; noise(CH_S,0.06)
  end
end

----------------------------------------------------------------
-- SONAR
----------------------------------------------------------------
local function do_ping()
  if sonar_t>0 then return end
  sonar_on=true; sonar_r=0; sonar_t=SONAR_CD; sfx_ping(); particles={}
  -- Alert entity
  if alive then
    e_alert_x=px; e_alert_y=py; e_chase=true; sfx_alert()
  end
end

local function update_sonar()
  if sonar_t>0 then sonar_t=sonar_t-1 end
  if not sonar_on then return end
  sonar_r=sonar_r+SONAR_SPD

  -- Ring particles hitting geometry
  if frame%2==0 then
    local segs=20
    for i=0,segs-1 do
      local a=(i/segs)*math.pi*2
      local rx=px*TILE+4+math.cos(a)*sonar_r
      local ry=py*TILE+4+math.sin(a)*sonar_r
      if rx>=0 and rx<W and ry>=0 and ry<H then
        local tx=math.floor(rx/TILE); local ty=math.floor(ry/TILE)
        local t=tile(tx,ty)
        if t==WALL then
          particles[#particles+1]={x=rx,y=ry,life=12,c=LIT}
        elseif t==EXIT then
          particles[#particles+1]={x=rx,y=ry,life=20,c=WHT}
        else
          particles[#particles+1]={x=rx,y=ry,life=4,c=DRK}
        end
      end
    end
  end

  -- Reveal entity
  local ed=dist(px,py,ex,ey)
  if sonar_r>=ed*TILE and sonar_r<ed*TILE+SONAR_SPD*2 then
    particles[#particles+1]={x=ex*TILE+4,y=ey*TILE+4,life=15,c=WHT}
    wave(CH_A,"sawtooth"); tone(CH_A,150,60,0.1)
  end

  if sonar_r>SONAR_MAX then sonar_on=false end

  -- Age particles
  local alive_p={}
  for _,p in ipairs(particles) do
    p.life=p.life-1
    if p.life>0 then alive_p[#alive_p+1]=p end
  end
  particles=alive_p
end

----------------------------------------------------------------
-- AMBIENT / HEARTBEAT
----------------------------------------------------------------
local function update_ambient()
  amb_drip=amb_drip-1
  if amb_drip<=0 then amb_drip=50+math.random(80); sfx_drip() end
  amb_creak=amb_creak-1
  if amb_creak<=0 then amb_creak=100+math.random(150); sfx_creak() end

  -- Heartbeat
  if alive then
    local d=dist(px,py,ex,ey)
    hb_rate=lerp(hb_rate, clamp(1-d/15,0,1), 0.05)
  else
    hb_rate=math.max(hb_rate-0.01,0)
  end
  if hb_rate>0.08 then
    hb_t=hb_t+1
    if hb_t>=math.floor(lerp(30,6,hb_rate)) then
      hb_t=0; sfx_heartbeat(hb_rate)
    end
  else hb_t=0 end
end

----------------------------------------------------------------
-- PLAYER MOVEMENT
----------------------------------------------------------------
local foot_alt=false
local function try_move(dx,dy)
  if not alive then return end
  local nx,ny=px+dx,py+dy
  local t=tile(nx,ny)
  if t==WALL then sfx_bump(); return end
  if t==EXIT then
    sfx_exit()
    if room_num<3 then
      room_num=room_num+1; load_room(room_num)
    else
      scene="victory"; victory_t=0; sfx_victory()
    end
    return
  end
  px=nx; py=ny; foot_alt=not foot_alt; sfx_step(foot_alt)
end

----------------------------------------------------------------
-- DEMO MODE
----------------------------------------------------------------
local function build_demo()
  demo_path={
    {1,0},{1,0},{1,0},{1,0},{1,0},{1,0},{1,0},
    {0,-1},{0,-1},{0,-1},{0,-1},
    {1,0},{1,0},{1,0},{1,0},
    {0,0,true}, -- ping
    {1,0},{1,0},
    {0,1},{0,1},{0,1},{0,1},{0,1},
    {0,0,true},
    {0,1},{0,1},{0,1},{0,1},
    {1,0},{1,0},{1,0},{1,0},{1,0},{1,0},
    {0,1},{0,1},
  }
  demo_step=1; demo_t=0
end

local function update_demo()
  demo_t=demo_t+1
  if demo_t<8 then return end
  demo_t=0
  if demo_step>#demo_path then load_room(1); build_demo(); return end
  local st=demo_path[demo_step]
  if st[3] then
    do_ping()
  else
    local nx,ny=px+st[1],py+st[2]
    local t=tile(nx,ny)
    if t==EMPTY or t==EXIT then
      px=nx; py=ny; foot_alt=not foot_alt; sfx_step(foot_alt)
    end
  end
  demo_step=demo_step+1
end

----------------------------------------------------------------
-- TITLE
----------------------------------------------------------------
local title_flicker=0

local function title_update()
  title_t=title_t+1; title_idle=title_idle+1
  if title_t%60==0 then wave(CH_S,"sine"); tone(CH_S,800,600,0.1) end
  if title_flicker>0 then title_flicker=title_flicker-1
  elseif math.random(200)<3 then title_flicker=5 end

  if title_idle>150 and not demo_on then
    demo_on=true; room_num=1; load_room(1); build_demo()
  end
  if demo_on then update_demo(); update_sonar(); update_entity() end

  if btnp("start") or btnp("a") then
    demo_on=false; scene="game"; room_num=1; load_room(1)
  end
end

local function title_draw()
  s=screen(); cls(s,BLK)
  -- Flickering title
  local tc=WHT
  local fl=math.random(100)
  if fl<6 then tc=DRK elseif fl<12 then tc=LIT end
  if title_flicker>3 then tc=BLK end
  if tc>0 then text(s,"DARK ROOM",W/2,20,tc,ALIGN_CENTER) end

  -- Creepy subtitles
  if title_t>30 then text(s,"you see nothing.",W/2,40,DRK,ALIGN_CENTER) end
  if title_t>60 then text(s,"it sees you.",W/2,50,DRK,ALIGN_CENTER) end
  if title_t>90 then text(s,"ping to survive.",W/2,60,DRK,ALIGN_CENTER) end

  -- Sonar ring on title
  local rr=(title_t%60)*1.5
  if rr<80 then
    local cx,cy=W/2,85
    for i=0,23 do
      local a=(i/24)*math.pi*2
      local rx=cx+math.cos(a)*rr; local ry=cy+math.sin(a)*rr*0.5
      if rx>=0 and rx<W and ry>=0 and ry<H then
        pix(s,math.floor(rx),math.floor(ry), rr<40 and DRK or BLK)
      end
    end
    pix(s,cx,85,WHT)
  end

  -- Entity eyes
  if title_t>100 then
    local blink=math.floor(title_t/20)%5
    if blink<2 then
      local ex2=W/2+math.sin(title_t*0.02)*30
      local ey2=85+math.cos(title_t*0.015)*8
      pix(s,math.floor(ex2)-1,math.floor(ey2),LIT)
      pix(s,math.floor(ex2)+1,math.floor(ey2),LIT)
    end
  end

  if demo_on then
    pix(s,px*TILE+4,py*TILE+4,WHT)
    for _,p in ipairs(particles) do
      if p.x>=0 and p.x<W and p.y>=0 and p.y<H then
        pix(s,math.floor(p.x),math.floor(p.y),p.c)
      end
    end
    text(s,"- DEMO -",W/2,4,DRK,ALIGN_CENTER)
  end

  if title_t%40<25 then text(s,"PRESS START",W/2,110,LIT,ALIGN_CENTER) end
end

----------------------------------------------------------------
-- GAME
----------------------------------------------------------------
local function game_update()
  if not alive then
    death_t=death_t+1
    if scare_fl>0 then scare_fl=scare_fl-1 end
    if shake_t>0 then shake_t=shake_t-1 end
    if death_t>90 and (btnp("start") or btnp("a")) then load_room(room_num) end
    return
  end

  if paused then if btnp("select") then paused=false end; return end
  if btnp("select") then paused=true; return end

  frame=frame+1

  if move_t>0 then move_t=move_t-1 end
  if move_t<=0 then
    if btn("left") then try_move(-1,0); move_t=MOVE_DLY
    elseif btn("right") then try_move(1,0); move_t=MOVE_DLY
    elseif btn("up") then try_move(0,-1); move_t=MOVE_DLY
    elseif btn("down") then try_move(0,1); move_t=MOVE_DLY end
  end

  if btnp("a") then do_ping() end

  update_sonar()
  update_entity()
  update_ambient()

  if scare_fl>0 then scare_fl=scare_fl-1 end
  if shake_t>0 then
    shake_t=shake_t-1; shake_x=math.random(-3,3); shake_y=math.random(-2,2)
  else shake_x=0; shake_y=0 end
end

local function game_draw()
  s=screen(); cls(s,BLK)

  -- Jump scare flash
  if scare_fl>0 then
    cls(s, scare_fl>6 and WHT or LIT)
    if not alive and scare_fl>4 then
      local cx,cy=W/2,H/2
      rectf(s,cx-20,cy-10,12,8,BLK)
      pix(s,cx-15,cy-7,WHT); pix(s,cx-14,cy-7,WHT)
      rectf(s,cx+8,cy-10,12,8,BLK)
      pix(s,cx+13,cy-7,WHT); pix(s,cx+14,cy-7,WHT)
      line(s,cx-15,cy+5,cx+15,cy+5,BLK)
      return
    end
    if scare_fl>3 then return end
  end

  local dpx=px*TILE+4+shake_x; local dpy=py*TILE+4+shake_y

  -- Player dot
  if alive then
    pix(s,dpx,dpy,WHT)
    if math.sin(frame*0.08)>0 then
      pix(s,dpx-1,dpy,DRK); pix(s,dpx+1,dpy,DRK)
      pix(s,dpx,dpy-1,DRK); pix(s,dpx,dpy+1,DRK)
    end
  end

  -- Sonar particles
  for _,p in ipairs(particles) do
    local rx=math.floor(p.x)+shake_x; local ry=math.floor(p.y)+shake_y
    if rx>=0 and rx<W and ry>=0 and ry<H then
      local c=p.c; if p.life<4 then c=DRK end; if p.life<2 then c=BLK end
      if c>0 then pix(s,rx,ry,c) end
    end
  end

  -- Active ring
  if sonar_on then
    for i=0,31 do
      local a=(i/32)*math.pi*2
      local rx=dpx+math.cos(a)*sonar_r; local ry=dpy+math.sin(a)*sonar_r
      if rx>=0 and rx<W and ry>=0 and ry<H then
        pix(s,math.floor(rx),math.floor(ry),DRK)
      end
    end
  end

  -- Entity eyes when close
  if alive then
    local ed=dist(px,py,ex,ey)
    if ed<5 then
      local epx=math.floor(ex*TILE+4)+shake_x
      local epy=math.floor(ey*TILE+4)+shake_y
      if math.floor(frame/8)%5<3 then
        local br=ed<3 and WHT or LIT
        pix(s,epx-1,epy,br); pix(s,epx+1,epy,br)
      end
    end
  end

  -- Room indicator
  text(s,room_num.."/3",4,2,DRK)

  -- Heartbeat edge pulse
  if hb_rate>0.3 and math.sin(frame*0.3)*hb_rate>0.3 then
    local c=hb_rate>0.7 and LIT or DRK
    for i=0,W-1,4 do pix(s,i,0,c); pix(s,i,H-1,c) end
    for i=0,H-1,4 do pix(s,0,i,c); pix(s,W-1,i,c) end
  end

  -- Sonar cooldown
  if sonar_t>0 then
    rectf(s,W/2-8,H-5,math.floor((sonar_t/SONAR_CD)*16),2,DRK)
  elseif frame%40<30 then
    pix(s,W/2,H-4,LIT)
  end

  -- Death
  if not alive and scare_fl<=0 then
    text(s,"IT GOT YOU",W/2,H/2-8,WHT,ALIGN_CENTER)
    if death_t>30 then text(s,"ROOM "..room_num,W/2,H/2+4,DRK,ALIGN_CENTER) end
    if death_t>60 and frame%40<25 then
      text(s,"PRESS START",W/2,H/2+16,LIT,ALIGN_CENTER)
    end
  end

  if paused then
    rectf(s,W/2-25,H/2-8,50,16,BLK)
    text(s,"PAUSED",W/2,H/2-4,WHT,ALIGN_CENTER)
  end
end

----------------------------------------------------------------
-- VICTORY
----------------------------------------------------------------
local function victory_update()
  victory_t=victory_t+1
  if victory_t%30==0 and victory_t<120 then sfx_victory() end
  if victory_t>60 and (btnp("start") or btnp("a")) then
    scene="title"; title_t=0; title_idle=0; demo_on=false
  end
end

local function victory_draw()
  s=screen(); cls(s,BLK)
  local r=math.min(victory_t*0.8,50)
  local cx,cy=W/2,H/2
  for ring=math.floor(r),0,-4 do
    local c=DRK; if ring<r*0.3 then c=WHT elseif ring<r*0.6 then c=LIT end
    for i=0,23 do
      local a=(i/24)*math.pi*2
      local rx=cx+math.cos(a)*ring; local ry=cy+math.sin(a)*ring
      if rx>=0 and rx<W and ry>=0 and ry<H then
        pix(s,math.floor(rx),math.floor(ry),c)
      end
    end
  end
  if victory_t>30 then text(s,"SILENCE",W/2,H/2-12,WHT,ALIGN_CENTER) end
  if victory_t>50 then
    text(s,"YOU ESCAPED",W/2,H/2,LIT,ALIGN_CENTER)
    text(s,"THE DARK ROOM",W/2,H/2+12,LIT,ALIGN_CENTER)
  end
  if victory_t>90 and victory_t%40<25 then
    text(s,"PRESS START",W/2,H-12,DRK,ALIGN_CENTER)
  end
end

----------------------------------------------------------------
-- ENGINE CALLBACKS
----------------------------------------------------------------
function _init()
  mode(2)
end

function _start()
  scene="title"; frame=0; title_t=0; title_idle=0; demo_on=false
  paused=false; move_t=0; amb_drip=30; amb_creak=60
  particles={}; hb_rate=0; hb_t=0
  wave(CH_S,"sine"); wave(CH_A,"sine"); wave(CH_H,"triangle"); wave(CH_F,"triangle")
end

function _update()
  if scene=="title" then title_update()
  elseif scene=="game" then game_update()
  elseif scene=="victory" then victory_update() end
end

function _draw()
  if scene=="title" then title_draw()
  elseif scene=="game" then game_draw()
  elseif scene=="victory" then victory_draw() end
end
