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


SET A, 0x001f
SET B, 0x0020
:main_loop
SET [0x8000+A], 0xff00
ADD A, B
IFG 0x180, A
  SET PC, check1
SET B, 0xFFE0
ADD A, B
:check1
IFG 0x1000, A
  SET PC, check2
SET B, 0x0020
ADD A, B
ADD A, B
:check2
JSR scroll
SET PC, main_loop

; scrolls video memory to the left by one
:scroll
SET PUSH, A
SET PUSH, B
SET A, 0x8000
:scroll_loop
SET [A], [1+A]
; check for last column (make it 0)
SET B, A
ADD B, 1
AND B, 0x1f
IFE B, 0
  SET [A], 0

ADD A, 1
IFG 0x8180, A
  SET PC, scroll_loop

SET B, POP
SET A, POP
SET PC, POP


:monitor_n
DAT 0
