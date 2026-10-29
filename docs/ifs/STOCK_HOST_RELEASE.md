# Stock firmwareExe: when does the host stop/release the IFS feed motor

Source: Ghidra static analysis of the stock `firmwareExe`. Addresses are function entry points.
Wire format: `F<cmd> C<chn> L<len> S<speed>`; status reply is parsed by splitting on `[: ]`, field 3 = state (5 = move done, 0x7f = error, 0x7e = busy/timeout). All IFS traffic goes through `SerialObject::sendCmdToUart4` (005e3230), mutex-serialised.

## 1. Every F112 sender (the only literal "F112" refs)

| Function | Addr | When |
|---|---|---|
| SerialObject::checkLoad | 005fbaa0 | state==5 AND toolhead sensor (checkFilamentSenser) true -> F112. Not sent on its timeout/error/cancel returns. |
| SerialObject::checkFeeding | 005f9674 | (a) state==5 and flag this+0x8a set -> F112 (ret 7); (b) toolhead sensor tripped -> F112 (ret 0); (c) cancel flag (this+0x2e3) set -> F112 (ret 1). NOT sent on: error 0x7f (ret 8), 0x7e x100 (ret 10), double 30 s timeout (ret 3, sends F39 instead). |
| SerialObject::fourInOneLoadFristStep | 005f839c | after the F10 poll loop ends (sensor trip, or >=0x78 polls) -> F112, then LoadSecondStep. NOT sent on 0x7e (ret 10) or cancel (ret 1) exits. |
| SerialObject::checkRefullingFrist | 005f2478 | toolhead sensor cleared during unload -> F112 (resent if reply lacks "ok"). Not sent if state 5 persists >10 polls (ret 4), 0x7f (8), 0x7e (10), cancel. |
| Filament::fourInOneLoadFristStep | 00592534 | UI load wizard, F112 after loop. |
| Filament::doFFMUnload | 00594f60 | UI unload wizard, F112 after the F11 poll loop. |
| FourToOne::on_f112_clicked | 0079f2ac | debug button only. |

No other F112 sender exists. No F112 on print end, pause, cancel (stopFilament 005e3888 only sets flag +0x2e3), idle, or periodically.

## 2. Is F112 always sent / keep-alive

- Unload F11 paths never send F112: SerialObject::fourInOneUnLoad (005f616c), cutFilament (005f5e58), doLoadAndUnload's F11 (005fda70), Filament::checkUnLoad (005930b4). They poll F13 until state 5 and return; motor left as firmware leaves it.
- LoadSecondStep (005f7b4c): `F11 C<n> L100 S1200`, polls F13 every 200 ms until state 5, returns with NO F112. So after every auto-insert the last motor command is an F11 with no F112 (checkFourInOneLoad 005fa288 then sends `F23 C<n>` and checkCrotchF39 = `F39 C<n>`; neither is F112).
- All error/timeout/cancel exits listed above leave F10/F11 motor on without F112.
- Idle polling: thread SerialObject::recvQueryFourInOneSt (005fa660) loops `F13`; usleep 200 ms when main machine status==0 (idle), sleep 1 s otherwise, and 1 s waits while a load/unload holds flag +0x2f0. 4 failed replies -> sigIfsStatus(false). It never sends F112/F39. Only F13 and F19 pass sendCmdToUart4 when this+0x2e2==0.
- F19: only from MachineInfo (initWidget 006eb3c8, slotCheckifs, doUpdateIfs): on demand, no period found.
- F23 C1..C4 batch: clearChnStatus 005e3584 (caller not traced).

## 3. Sequences (literals as in binary; numbers from decompile)

(a) Auto/first insert (recvQueryFourInOneSt -> checkFourInOneLoad, per channel with sensor bit):
`F24 C<n>` (checkCrotchCutting 005f4f8c, poll F13 1 s up to ~21x) ; `F10 C<n> L650 S1200` (0x28a, 0x4b0) ; poll `F13` every 100 ms until toolhead sensor / ~12 s ; `F112` ; `F11 C<n> L100 S1200` ; poll F13 200 ms to state 5 ; `F23 C<n>` ; `F39 C<n>` (checkCrotchF39 005f8da0, polls F13 1 s up to 11x). On 0x7f: `F15` then re-send F10/F11.
Pause auto-load (checkPauseAutoLoad 005fade4): `F24`, `F10 C<n> L200 S..`, F13 polls, `F23 C<n>`, `F39 C<n>`.

(b) Toolchange load during print (doLoadAndUnload 005fda70, old->new): cutFilament(old) (`G1 E-..`, `F11 C<old> L60 S..`) ; checkRefullingFrist(old) (F13 1 s poll, `F112` when toolhead clear) ; `F11 C<old> L50 S..` ; `F39 C<old>` ; `F24 C<new>` ; `F10 C<new> L1000 S<spd>` ; checkFeeding(new) (F13 100 ms poll, up to 30 s, `F112` on toolhead sensor; at 30 s: `F11 C<new> L.. S1200` retry, second 30 s: error + F39) ; `M400`. Error 0x7f: `F15` + F24 + retry.

(c) Unload (checkPrintUnLoad 005f6e58 / fourInOneUnLoad 005f616c): `F23 C<n>` ; `F24 C<n>` ; `F11 C<n> S600` ; M400 ; poll F13 200 ms ; on state 5 repeated `F11 C<n> L70 S..` x3 then `F11 C<n> L60 S..` ; cutFilament. No F112 at all.

(d) Channel switch (changeChannel 005fe970): doLoadAndUnload as (b); cleanFilamentBox (005fce9c) ends with `F23 C<n>`; moves F800/F12000 are printer gcode.

Not found: exact S values for several F10/F11 calls (runtime/config), F19 period, caller of clearChnStatus.
