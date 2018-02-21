; find out hardware map
HWN I
:query_loop
SUB I, 1
HWQ I
IFE B, 0x7349
  IFE A, 0xf615
    SET [monitor_n], I
IFN I, 0
  SET PC, query_loop

; set up monitor
SET A, 0
SET B, 0x8000
HWI [monitor_n]
SET A, 1
SET B, 0x8180
HWI [monitor_n]


; load character data:
SET A, shroom
SET B, shroom_end
SET C, 0x8180
JSR copy
SET A, flower
SET B, flower_end
SET C, 0x8190
JSR copy
SET A, star
SET B, star_end
SET C, 0x81a0
JSR copy

; animation:
SET X, 0
:anim_loop
SET A, 0xf000
SET I, [pathx+X]
SET PUSH, I
SET J, [pathy+X]
SET PUSH, J
JSR draw

SET A, 0xf008
SET Y, X
ADD Y, 6
MOD Y, 20
SET I, [pathx+Y]
SET PUSH, I
SET Y, X
ADD Y, 6
MOD Y, 20
SET J, [pathy+Y]
SET PUSH, J
JSR draw

SET A, 0xf010
SET Y, X
ADD Y, 12
MOD Y, 20
SET I, [pathx+Y]
SET PUSH, I
SET Y, X
ADD Y, 12
MOD Y, 20
SET J, [pathy+Y]
SET PUSH, J
JSR draw

JSR delay

SET A, 0x0000
SET J, POP
SET I, POP
JSR clear
SET J, POP
SET I, POP
JSR clear
SET J, POP
SET I, POP
JSR clear

ADD X, 1
IFE X, 20
  SET X, 0
SET PC, anim_loop

SUB PC, 1


; copy memory range [A,B[ to C
:copy
SET PUSH, A
SET PUSH, C
:copy_loop
IFE A, B
  SET PC, copy_end
SET [C], [A]
ADD A, 1
ADD C, 1
SET PC, copy_loop
:copy_end
SET C, POP
SET A, POP
SET PC, POP


; clear 4x2-char graphic from (I,J) with color info in A
:clear
SET PUSH, X
SET X, J
SHL X, 5
ADD X, I
SET [0x8000+X], A
SET [0x8001+X], A
SET [0x8002+X], A
SET [0x8003+X], A
SET [0x8020+X], A
SET [0x8021+X], A
SET [0x8022+X], A
SET [0x8023+X], A
SET X, POP
SET PC, POP


; draw 4x2-char graphic starting at character A to (I,J) with color info in A
:draw
SET PUSH, A
SET PUSH, X
SET X, J
SHL X, 5
ADD X, I
SET [0x8000+X], A
ADD A, 1
SET [0x8001+X], A
ADD A, 1
SET [0x8002+X], A
ADD A, 1
SET [0x8003+X], A
ADD A, 1
SET [0x8020+X], A
ADD A, 1
SET [0x8021+X], A
ADD A, 1
SET [0x8022+X], A
ADD A, 1
SET [0x8023+X], A
SET X, POP
SET A, POP
SET PC, POP


:delay
SET PUSH, A
SET A, 0x400
:delay_loop
SUB A, 1
IFE A, 0
  SET PC, delay_loop
SET A, POP
SET PC, POP

:shroom
DAT 0xe0f8,0xfce6, 0x0ecf,0xe7e1, 0xe1e7,0xcf0e, 0xe6fc,0xf8e0
DAT 0x0f19,0x79cc, 0x8485,0x9f87, 0x879f,0x8584, 0xcc79,0x190f
:shroom_end

:flower
DAT 0x7cc6,0x82bb, 0x296d,0x5555, 0x5555,0x6d29, 0xbb82,0xc67c
DAT 0x1c22,0x4a55, 0xa5c9,0xbf81, 0x81bf,0xc9a5, 0x554a,0x221c
:flower_end

:star
DAT 0x3050,0x9010, 0x1018,0xc601, 0x01c6,0x1810, 0x1090,0x5030
DAT 0xc0b0,0x8c43, 0x4020,0x2110, 0x1021,0x2040, 0x438c,0xb0c0
:star_end

; circular path
:pathx
DAT 14,18,21,24,26, 27,26,24,21,18, 14,10,6,3,1, 0,1,3,6,10
:pathy
DAT  0, 0, 1, 2, 3,  5, 7, 8, 9,10, 10,10,9,8,7, 5,3,2,1, 0


:monitor_n
DAT 0
