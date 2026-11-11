; =============================================================================
; Tetris The Grand Master (TGM1) ruleset for NES Tetris
;
; Rules follow TGM1 (Arika, 1998):
;   * ARS rotation (pieces spawn flat side up, right-then-left wall kicks,
;     arcade centre column rule, I and O never kick), IRS
;   * TGM randomizer: 4 piece history, 4 rolls, first piece never S/Z/O
;   * levels 0-999, +1 per piece, +n per n lines, stops at x99 and 998
;   * TGM1 gravity curve (in 1/256 G) up to 20G at level 500
;   * lock delay 30 (reset only when the piece steps down), ARE 30,
;     line clear 41, DAS 16 then 1 cell/frame, down = soft drop + lock
;   * score = (ceil((level + lines) / 4) + soft) * lines * combo * bravo
;   * grades 9 .. S9 by score, GM by meeting the 300/500/999 requirements
;   * level 999 ends the game, followed by a 20G credit roll
;
; All NTSC frame counts. B-TYPE plays TGM1's "20G mode".
; The numbers were checked against the arcade program; see
; docs/TGM1_ARCADE_NOTES.md for addresses and details.
; =============================================================================

; ---------------------------------------------------------------- tuning ----
TGM_LOCK_DELAY      = 30
TGM_ARE             = 30
TGM_LINE_CLEAR      = 41
TGM_DAS             = 15        ; frames held before auto-repeat (16th frame repeats)
TGM_ROLL_FRAMES     = 3238      ; length of the credit roll (estimate: the arcade ends
                                ; its roll when the staff credits finish, not on a timer)
TGM_GM_GRADE        = 18
TGM_TOP_GRADE       = 17        ; S9
TGM_20G             = $1400     ; 20 rows per frame, in 1/256 G

RENDER_GRADE        = $08

COLON_TILE          = $2A       ; ':' in the game tileset (added by tools/tgm_assets.py)
ENDING_COLON_TILE   = $3D       ; ':' in the type A ending tileset
ENDING_D_TILE       = $17
ENDING_M_TILE       = $31
ENDING_N_TILE       = $3A

TGM_PLAYSTATE_WIN   = $0C

; ------------------------------------------------------------------ RAM -----
; $0300-$03EF is unused by the original game.
tgmLevel            := $0300    ; BCD, low two digits
tgmLevelHi          := $0301    ; hundreds digit (0-9)
tgmGravLo           := $0302    ; current gravity, 1/256 G
tgmGravHi           := $0303
tgmGravSub          := $0304    ; gravity sub-row accumulator
tgmLockTimer        := $0305
tgmDasTimer         := $0306
tgmDasPrevDir       := $0307
tgmDelay            := $0308    ; frames until the next piece may spawn
tgmSoft             := $0309    ; frames down was held for the current piece
tgmCombo            := $030A
tgmScore            := $030B    ; 3 bytes, binary, little endian
tgmGrade            := $030E    ; 0 = grade 9 ... 17 = S9, 18 = GM
tgmGMPossible       := $030F
tgmCheckpoint       := $0310    ; GM checkpoints passed (300, 500)
tgmTimeFrames       := $0311    ; 0-59
tgmTimeSec          := $0312    ; BCD
tgmTimeMin          := $0313    ; BCD
tgmTimerOn          := $0314
tgmHistory          := $0315    ; 4 bytes, piece types
tgmRngStarted       := $0319
tgmRoll             := $031A    ; credit roll in progress
tgmRollTimer        := $031B    ; 2 bytes
tgmDir              := $031D    ; 0 none, 1 left, 2 right, 3 down
tgmMul              := $031E    ; 3 bytes, multiply accumulator
tgmMulTmp           := $0321    ; 3 bytes
tgmTmp              := $0324
tgmTmp2             := $0325
tgmOrigOrient       := $0326
tgmCount            := $0327
tgmEffGLo           := $0328
tgmEffGHi           := $0329
tgmCol              := $032A
tgmClearTime        := $032B    ; 3 bytes: clock (frames, sec, min) 4 frames after the last lock
tgmClearCount       := $032E    ; frames until tgmClearTime is taken
tgmTimerTiles       := $0330    ; 8 bytes, staged for the NMI
tgmDigits           := $0338    ; 6 bytes, scratch for binary->BCD

DIR_NONE            = 0
DIR_LEFT            = 1
DIR_RIGHT           = 2
DIR_DOWN            = 3

; ============================================================ game setup ====

; Called from gameModeState_initGameState before the first pieces are chosen.
tgmInitGame:
        ldx     #tgmDigits+6-tgmLevel
        lda     #$00
@clear: sta     tgmLevel-1,x
        dex
        bne     @clear
        lda     gameMode
        cmp     #$05
        bne     @notDemo
        lda     #$00
        sta     player1_startLevel
@notDemo:
        ; The level menu picks the starting section (x100)
        lda     player1_startLevel
        cmp     #$0A
        bcc     @startOk
        lda     #$09
        sta     player1_startLevel
@startOk:
        sta     tgmLevelHi
        sta     player1_levelNumber
        sta     levelNumber
        ldx     #$01
        cmp     #$00
        beq     @gmOk
        dex
@gmOk:  stx     tgmGMPossible
        lda     #$01
        sta     tgmCombo
        sta     tgmTimerOn
        jsr     tgmUpdateGravity
        jsr     tgmUpdateTimerTiles
        lda     outOfDateRenderFlags
        ora     #RENDER_GRADE
        sta     outOfDateRenderFlags
        rts

; ========================================================= per-frame hook ===

; Runs every frame for player 1 before the play state handler.
tgmPreFrame:
        lda     playState
        beq     @ret
        cmp     #$0A
        bcs     @ret
        lda     tgmTimerOn
        beq     @timerStopped
        jsr     tgmTickTimer
@timerStopped:
        ; The arcade places the piece and tests the GM time limits 4 frames
        ; after the lock; note the clock on that frame.
        lda     tgmClearCount
        beq     @clockNoted
        dec     tgmClearCount
        bne     @clockNoted
        ldx     #$02
@noteClock:
        lda     tgmTimeFrames,x
        sta     tgmClearTime,x
        dex
        bpl     @noteClock
@clockNoted:
        lda     tgmRoll
        beq     @noRoll
        lda     tgmRollTimer
        bne     @decLo
        dec     tgmRollTimer+1
@decLo: dec     tgmRollTimer
        lda     tgmRollTimer
        ora     tgmRollTimer+1
        bne     @noRoll
        lda     #TGM_PLAYSTATE_WIN      ; survived the credit roll
        sta     playState
        rts

@noRoll:
        lda     playState
        cmp     #$01
        beq     @ret
        ; Between pieces: count down ARE / line clear delay and keep DAS charged
        lda     tgmDelay
        beq     @delayDone
        dec     tgmDelay
@delayDone:
        jsr     tgmReadDir
        jsr     tgmUpdateDas
@ret:   rts

; ======================================================== active piece =====

playState_tgmActive:
        jsr     tgmReadDir
        lda     tgmDir
        cmp     #DIR_DOWN
        bne     @notSoft
        inc     tgmSoft
        bne     @notSoft
        dec     tgmSoft                 ; saturate at 255
@notSoft:
        jsr     tgmRotate
        jsr     tgmUpdateDas
        jsr     tgmShift
        jmp     tgmGravityAndLock

; tgmDir from the controller. Left/right win over down; both left and right
; held counts as no horizontal input.
tgmReadDir:
        ldx     #DIR_NONE
        lda     heldButtons
        and     #BUTTON_LEFT+BUTTON_RIGHT
        cmp     #BUTTON_LEFT
        bne     @notLeft
        ldx     #DIR_LEFT
        bne     @store
@notLeft:
        cmp     #BUTTON_RIGHT
        bne     @notRight
        ldx     #DIR_RIGHT
        bne     @store
@notRight:
        lda     heldButtons
        and     #BUTTON_DOWN
        beq     @store
        ldx     #DIR_DOWN
@store: stx     tgmDir
        rts

; Returns in A the direction to move this frame (or DIR_NONE).
tgmUpdateDas:
        lda     tgmDir
        beq     @reset
        cmp     #DIR_DOWN
        beq     @reset
        cmp     tgmDasPrevDir
        bne     @reset
        lda     tgmDasTimer
        cmp     #TGM_DAS
        bcs     @output
        inc     tgmDasTimer
        bne     @output
@reset: lda     #$00
        sta     tgmDasTimer
@output:
        lda     tgmDir
        sta     tgmDasPrevDir
        lda     tgmDasTimer
        beq     @move
        cmp     #TGM_DAS
        beq     @move
        lda     #DIR_NONE
        rts

@move:  lda     tgmDir
        rts

tgmShift:
        cmp     #DIR_LEFT
        bne     @tryRight
        dec     tetriminoX
        jsr     isPositionValid
        bne     @undoLeft
        beq     @moved
@undoLeft:
        inc     tetriminoX
        rts

@tryRight:
        cmp     #DIR_RIGHT
        bne     @ret
        inc     tetriminoX
        jsr     isPositionValid
        bne     @undoRight
@moved: lda     #$03
        sta     soundEffectSlot1Init
        rts

@undoRight:
        dec     tetriminoX
@ret:   rts

; B rotates counter-clockwise, A clockwise (rotationTable: even = B, odd = A)
tgmRotate:
        lda     newlyPressedButtons
        and     #BUTTON_B
        beq     @checkA
        ldy     #$00
        beq     @rotate
@checkA:
        lda     newlyPressedButtons
        and     #BUTTON_A
        beq     @ret
        ldy     #$01
@rotate:
        lda     currentPiece
        sta     tgmOrigOrient
        asl     a
        sty     tgmTmp
        clc
        adc     tgmTmp
        tax
        lda     rotationTable,x
        sta     currentPiece
        jsr     isPositionValid
        beq     @success
        ; Wall kicks. I and O never kick.
        ldx     tgmOrigOrient
        lda     tetriminoTypeFromOrientation,x
        cmp     #iPiece
        beq     @fail
        cmp     #oPiece
        beq     @fail
        jsr     tgmCentreColumnBlocked
        bcs     @fail
        inc     tetriminoX
        jsr     isPositionValid
        beq     @success
        dec     tetriminoX
        dec     tetriminoX
        jsr     isPositionValid
        beq     @success
        inc     tetriminoX
@fail:  lda     tgmOrigOrient
        sta     currentPiece
@ret:   rts

@success:
        lda     #$05
        sta     soundEffectSlot1Init
        rts

; Centre column rule, as in the TGM1 arcade code (ate-05m.3h, $8001910C):
; walk the cells of the rotated piece in reading order (top to bottom, left
; to right) and find the first one that hits a block, a wall or the floor.
; If that cell is in the middle column of the rotation box, the piece does
; not kick. Applies to every piece that can kick (all but I and O).
; Expects currentPiece to hold the rotated orientation.
; Carry set = kick not allowed.
tgmCentreColumnBlocked:
        lda     currentPiece
        asl     a
        asl     a
        sta     tgmTmp
        asl     a
        clc
        adc     tgmTmp
        tax                             ; x = orientation * 12
        lda     #$04
        sta     tgmCount
@mino:  lda     orientationTable,x      ; dy (minos are stored in reading order)
        clc
        adc     tetriminoY
        sta     tgmTmp                  ; row
        lda     orientationTable+2,x    ; dx
        sta     tgmTmp2
        clc
        adc     tetriminoX
        cmp     #$0A                    ; wall (also catches negative columns)
        bcs     @hit
        sta     tgmCol
        lda     tgmTmp
        bmi     @free                   ; above the field
        cmp     #$14
        bcs     @hit                    ; floor
        tay
        lda     multBy10Table,y
        clc
        adc     tgmCol
        tay
        lda     (playfieldAddr),y
        cmp     #tileEmpty
        bcc     @hit
@free:  inx
        inx
        inx
        dec     tgmCount
        bne     @mino
        clc
        rts

@hit:   lda     tgmTmp2                 ; dx = 0 is the middle column
        bne     @kickAllowed
        sec
        rts

@kickAllowed:
        clc
        rts

; Carry set if the piece is resting on something.
tgmIsGrounded:
        inc     tetriminoY
        jsr     isPositionValid
        dec     tetriminoY
        lda     generalCounter
        cmp     #$01
        rts

tgmGravityAndLock:
        lda     tgmGravLo
        sta     tgmEffGLo
        lda     tgmGravHi
        sta     tgmEffGHi
        ; soft drop: at least 1G
        lda     tgmDir
        cmp     #DIR_DOWN
        bne     @gravitySet
        lda     tgmEffGHi
        bne     @gravitySet
        sta     tgmEffGLo
        lda     #$01
        sta     tgmEffGHi
@gravitySet:
        jsr     tgmIsGrounded
        bcc     @falling
        lda     #$00
        sta     tgmGravSub
        jmp     @lockTick

@falling:
        lda     tgmEffGHi
        bne     @wholeRows
        lda     tgmGravSub
        clc
        adc     tgmEffGLo
        sta     tgmGravSub
        bcc     @ret                    ; not a full row yet
        lda     #$01
@wholeRows:
        sta     tgmCount
@fall:  inc     tetriminoY
        jsr     tgmIsGrounded
        bcs     @landed
        dec     tgmCount
        bne     @fall
        lda     #$00                    ; stepped down: lock delay resets
        sta     tgmLockTimer
@ret:   rts

@landed:
        lda     #$00
        sta     tgmLockTimer
@lockTick:
        lda     tgmDir
        cmp     #DIR_DOWN
        beq     tgmLockPiece
        inc     tgmLockTimer
        lda     tgmLockTimer
        cmp     #TGM_LOCK_DELAY
        bcc     @ret
tgmLockPiece:
        lda     #$02
        sta     playState
        lda     #TGM_ARE+1
        sta     tgmDelay
        lda     #$04
        sta     tgmClearCount
        rts

; ================================================================ spawn ====

playState_tgmSpawn:
        lda     vramRow
        cmp     #$20
        bmi     @ret
        lda     tgmDelay
        bne     @ret
        jsr     tgmLevelUpOnSpawn
        lda     #$00
        sta     fallTimer
        sta     tetriminoY
        sta     tgmGravSub
        sta     tgmLockTimer
        sta     tgmSoft
        sta     autorepeatY
        lda     #$04
        sta     tetriminoX
        ldx     nextPiece
        lda     spawnOrientationFromOrientation,x
        sta     currentPiece
        jsr     incrementPieceStat
        jsr     chooseNextTetrimino
        sta     nextPiece
        ; IRS: a rotation button held during ARE rotates the new piece
        ldy     #$00
        lda     heldButtons
        and     #BUTTON_B
        bne     @irs
        iny
        lda     heldButtons
        and     #BUTTON_A
        beq     @spawnCheck
@irs:   lda     currentPiece
        sta     tgmOrigOrient
        asl     a
        sty     tgmTmp
        clc
        adc     tgmTmp
        tax
        lda     rotationTable,x
        sta     currentPiece
        jsr     isPositionValid
        beq     @spawnCheck
        lda     tgmOrigOrient
        sta     currentPiece
@spawnCheck:
        jsr     isPositionValid
        bne     @blockOut
        ; At 1G or more the piece drops on its spawn frame
        lda     tgmGravHi
        beq     @active
        sta     tgmCount
@drop:  jsr     tgmIsGrounded
        bcs     @active
        inc     tetriminoY
        dec     tgmCount
        bne     @drop
@active:
        lda     #$01
        sta     playState
@ret:   rts

@blockOut:
        lda     tgmRoll
        beq     @gameOver
        lda     #TGM_PLAYSTATE_WIN      ; topping out in the roll still clears the game
        sta     playState
        rts

@gameOver:
        lda     #$00
        sta     tgmTimerOn
        lda     #$02
        sta     soundEffectSlot0Init
        lda     #$0A
        sta     playState
        lda     #$F0
        sta     curtainRow
        jmp     updateAudio2

; Level +1 per piece, except at x99 and 998 (those need a line clear).
tgmLevelUpOnSpawn:
        lda     tgmLevel
        cmp     #$99
        beq     @ret
        cmp     #$98
        bne     @inc
        lda     tgmLevelHi
        cmp     #$09
        beq     @ret
@inc:   jsr     tgmLevelInc
        jsr     tgmUpdateGravity
        lda     outOfDateRenderFlags
        ora     #RENDER_LEVEL
        sta     outOfDateRenderFlags
@ret:   rts

; Level +1 in BCD, capped at 999.
tgmLevelInc:
        lda     tgmLevelHi
        cmp     #$09
        bne     @inc
        lda     tgmLevel
        cmp     #$99
        beq     @ret
@inc:   lda     tgmLevel
        clc
        adc     #$01
        sta     tgmLevel
        and     #$0F
        cmp     #$0A
        bcc     @ret
        lda     tgmLevel
        adc     #$05                    ; carry is set: +6
        sta     tgmLevel
        cmp     #$A0
        bcc     @ret
        lda     #$00
        sta     tgmLevel
        inc     tgmLevelHi
@ret:   rts

; =========================================================== randomizer ====

; Returns a spawn orientation in A (replaces the NES randomizer).
tgmPickPiece:
        lda     tgmRngStarted
        bne     @normal
        inc     tgmRngStarted
        jsr     tgmRandomByte
        and     #$03
        tax
        lda     tgmFirstPieceTable,x
        sta     tgmHistory+3
        lda     #zPiece
        sta     tgmHistory
        sta     tgmHistory+1
        sta     tgmHistory+2
        ldx     tgmHistory+3
        lda     spawnTable,x
        rts

@normal:
        lda     #$04
        sta     tgmCount
@roll:  jsr     tgmRandomByte
        and     #$07
        cmp     #$07
        beq     @roll
        sta     tgmTmp
        ldx     #$03
@inHistory:
        cmp     tgmHistory,x
        beq     @reroll
        dex
        bpl     @inHistory
        bmi     @picked
@reroll:
        dec     tgmCount
        bne     @roll
@picked:
        lda     tgmHistory+1
        sta     tgmHistory
        lda     tgmHistory+2
        sta     tgmHistory+1
        lda     tgmHistory+3
        sta     tgmHistory+2
        ldx     tgmTmp
        stx     tgmHistory+3
        lda     spawnTable,x
        rts

tgmFirstPieceTable:
        .byte   iPiece, jPiece, lPiece, tPiece

; Steps the 16-bit LFSR a byte's worth so successive rolls are independent.
tgmRandomByte:
        lda     #$08
        sta     tgmTmp2
@step:  ldx     #rng_seed
        ldy     #$02
        jsr     generateNextPseudorandomNumber
        dec     tgmTmp2
        bne     @step
        lda     rng_seed
        eor     frameCounter
        rts

; ============================================================== gravity ====

tgmUpdateGravity:
        lda     tgmRoll
        bne     @twentyG
        lda     gameType
        bne     @twentyG
        ldx     #$00
@search:
        lda     tgmGravityTable+4,x
        cmp     #$FF
        beq     @found
        lda     tgmLevelHi
        cmp     tgmGravityTable+4,x
        bcc     @found
        bne     @next
        lda     tgmLevel
        cmp     tgmGravityTable+5,x
        bcc     @found
@next:  inx
        inx
        inx
        inx
        bne     @search
@found: lda     tgmGravityTable+2,x
        sta     tgmGravLo
        lda     tgmGravityTable+3,x
        sta     tgmGravHi
        rts

@twentyG:
        lda     #<TGM_20G
        sta     tgmGravLo
        lda     #>TGM_20G
        sta     tgmGravHi
        rts

; level (hundreds, BCD tens/ones) -> gravity in 1/256 G
tgmGravityTable:
        .byte   $00,$00, <4,    >4
        .byte   $00,$30, <6,    >6
        .byte   $00,$35, <8,    >8
        .byte   $00,$40, <10,   >10
        .byte   $00,$50, <12,   >12
        .byte   $00,$60, <16,   >16
        .byte   $00,$70, <32,   >32
        .byte   $00,$80, <48,   >48
        .byte   $00,$90, <64,   >64
        .byte   $01,$00, <80,   >80
        .byte   $01,$20, <96,   >96
        .byte   $01,$40, <112,  >112
        .byte   $01,$60, <128,  >128
        .byte   $01,$70, <144,  >144
        .byte   $02,$00, <4,    >4
        .byte   $02,$20, <32,   >32
        .byte   $02,$30, <64,   >64
        .byte   $02,$33, <96,   >96
        .byte   $02,$36, <128,  >128
        .byte   $02,$39, <160,  >160
        .byte   $02,$43, <192,  >192
        .byte   $02,$47, <224,  >224
        .byte   $02,$51, <256,  >256
        .byte   $03,$00, <512,  >512
        .byte   $03,$30, <768,  >768
        .byte   $03,$60, <1024, >1024
        .byte   $04,$00, <1280, >1280
        .byte   $04,$20, <1024, >1024
        .byte   $04,$50, <768,  >768
        .byte   $05,$00, <TGM_20G, >TGM_20G
        .byte   $FF

; ======================================================= line clears =======
; The rest of the TGM code lives in the other free ROM area.
.segment        "unreferenced_data1"

; Adds 41 frames of line clear delay; called once the rows have been checked.
tgmAddLineClearDelay:
        lda     tgmDelay
        clc
        adc     #TGM_LINE_CLEAR
        sta     tgmDelay
        rts

; Replaces playState_updateLinesAndStatistics.
playState_tgmScore:
        jsr     updateMusicSpeed
        lda     completedLines
        bne     @cleared
        lda     #$01
        sta     tgmCombo
        jmp     @done

@cleared:
        ; LINES counter (BCD)
        ldx     completedLines
@incLines:
        inc     lines
        lda     lines
        and     #$0F
        cmp     #$0A
        bcc     @nextLine
        lda     lines
        adc     #$05
        sta     lines
        cmp     #$A0
        bcc     @nextLine
        lda     #$00
        sta     lines
        inc     lines+1
@nextLine:
        dex
        bne     @incLines
        lda     outOfDateRenderFlags
        ora     #RENDER_LINES
        sta     outOfDateRenderFlags

        lda     tgmRoll
        bne     @levelUp                ; no scoring during the credit roll

        ; combo = combo + 2 * lines - 2
        lda     completedLines
        asl     a
        sec
        sbc     #$02
        clc
        adc     tgmCombo
        bcc     @comboOk
        lda     #$FF
@comboOk:
        sta     tgmCombo

        ; base = ceil((level + lines) / 4) + soft, using the level before the clear
        jsr     tgmLevelToBinary
        lda     completedLines
        clc
        adc     #$03
        adc     tgmMul
        sta     tgmMul
        bcc     @noCarry1
        inc     tgmMul+1
@noCarry1:
        lsr     tgmMul+1
        ror     tgmMul
        lsr     tgmMul+1
        ror     tgmMul
        lda     tgmMul
        clc
        adc     tgmSoft
        sta     tgmMul
        bcc     @noCarry2
        inc     tgmMul+1
@noCarry2:
        lda     completedLines
        jsr     tgmMultiply
        lda     tgmCombo
        jsr     tgmMultiply
        jsr     tgmIsFieldEmpty         ; bravo (all clear): x4
        bne     @noBravo
        ldx     #$02
@bravo: asl     tgmMul
        rol     tgmMul+1
        rol     tgmMul+2
        dex
        bne     @bravo
@noBravo:
        jsr     tgmAddScore

@levelUp:
        lda     tgmLevelHi
        sta     tgmTmp2
        ldx     completedLines
@incLevel:
        jsr     tgmLevelInc
        dex
        bne     @incLevel
        lda     tgmLevelHi
        cmp     tgmTmp2
        beq     @sameSection
        sta     levelNumber             ; drives the palette, like NES levels
        lda     #$06
        sta     soundEffectSlot1Init
@sameSection:
        jsr     tgmUpdateGravity
        jsr     tgmCheckGMRequirements
        lda     outOfDateRenderFlags
        ora     #RENDER_LEVEL
        sta     outOfDateRenderFlags
@done:  lda     #$00
        sta     completedLines
        inc     playState
        rts

; tgmMul = current level as a 16-bit number (tgmMul+2 = 0)
tgmLevelToBinary:
        ldx     tgmLevelHi
        lda     tgmHundredsLo,x
        sta     tgmMul
        lda     tgmHundredsHi,x
        sta     tgmMul+1
        lda     #$00
        sta     tgmMul+2
        lda     tgmLevel
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        tax
        lda     multBy10Table,x
        clc
        adc     tgmMul
        sta     tgmMul
        bcc     @tensDone
        inc     tgmMul+1
@tensDone:
        lda     tgmLevel
        and     #$0F
        clc
        adc     tgmMul
        sta     tgmMul
        bcc     @ret
        inc     tgmMul+1
@ret:   rts

tgmHundredsLo:
        .byte   <0, <100, <200, <300, <400, <500, <600, <700, <800, <900
tgmHundredsHi:
        .byte   >0, >100, >200, >300, >400, >500, >600, >700, >800, >900

; tgmMul (24-bit) *= A
tgmMultiply:
        sta     tgmTmp
        ldx     #$02
@copy:  lda     tgmMul,x
        sta     tgmMulTmp,x
        lda     #$00
        sta     tgmMul,x
        dex
        bpl     @copy
        ldx     #$08
@bit:   lsr     tgmTmp
        bcc     @noAdd
        clc
        lda     tgmMul
        adc     tgmMulTmp
        sta     tgmMul
        lda     tgmMul+1
        adc     tgmMulTmp+1
        sta     tgmMul+1
        lda     tgmMul+2
        adc     tgmMulTmp+2
        sta     tgmMul+2
@noAdd: asl     tgmMulTmp
        rol     tgmMulTmp+1
        rol     tgmMulTmp+2
        dex
        bne     @bit
        rts

; Z set if the playfield has no blocks.
tgmIsFieldEmpty:
        ldy     #$00
@cell:  lda     (playfieldAddr),y
        cmp     #tileEmpty
        bcc     @notEmpty
        iny
        cpy     #$C8
        bne     @cell
        lda     #$00
        rts

@notEmpty:
        lda     #$01
        rts

; score += tgmMul, capped at 999999; refresh the BCD score and the grade
tgmAddScore:
        clc
        lda     tgmScore
        adc     tgmMul
        sta     tgmScore
        lda     tgmScore+1
        adc     tgmMul+1
        sta     tgmScore+1
        lda     tgmScore+2
        adc     tgmMul+2
        sta     tgmScore+2
        ; cap
        lda     tgmScore
        cmp     #<999999
        lda     tgmScore+1
        sbc     #>999999
        lda     tgmScore+2
        sbc     #^999999
        bcc     @capped
        lda     #<999999
        sta     tgmScore
        lda     #>999999
        sta     tgmScore+1
        lda     #^999999
        sta     tgmScore+2
@capped:
        jsr     tgmScoreToBcd
        lda     outOfDateRenderFlags
        ora     #RENDER_SCORE
        sta     outOfDateRenderFlags
        ; grade
@nextGrade:
        lda     tgmGrade
        cmp     #TGM_TOP_GRADE
        bcs     @ret
        asl     a                       ; carry clear (grade < 17)
        adc     tgmGrade                ; x3
        tax
        lda     tgmScore
        cmp     tgmGradeTable,x
        lda     tgmScore+1
        sbc     tgmGradeTable+1,x
        lda     tgmScore+2
        sbc     tgmGradeTable+2,x
        bcc     @ret
        inc     tgmGrade
        lda     #$06
        sta     soundEffectSlot1Init
        lda     outOfDateRenderFlags
        ora     #RENDER_GRADE
        sta     outOfDateRenderFlags
        jmp     @nextGrade

@ret:   rts

; score needed for grades 8, 7, ... 1, S1 ... S9
tgmGradeTable:
        .faraddr 400, 800, 1400, 2000, 3500, 5500, 8000, 12000, 16000
        .faraddr 22000, 30000, 40000, 52000, 66000, 82000, 100000, 120000

; tgmScore (binary) -> score (BCD, 3 bytes, low byte first)
tgmScoreToBcd:
        lda     tgmScore
        sta     tgmMulTmp
        lda     tgmScore+1
        sta     tgmMulTmp+1
        lda     tgmScore+2
        sta     tgmMulTmp+2
        ldx     #$00                    ; digit
        ldy     #$00                    ; offset into tgmPowersOf10
@digit: lda     #$00
        sta     tgmDigits,x
@subtract:
        lda     tgmMulTmp
        cmp     tgmPowersOf10,y
        lda     tgmMulTmp+1
        sbc     tgmPowersOf10+1,y
        lda     tgmMulTmp+2
        sbc     tgmPowersOf10+2,y
        bcc     @nextDigit
        lda     tgmMulTmp               ; carry is set
        sbc     tgmPowersOf10,y
        sta     tgmMulTmp
        lda     tgmMulTmp+1
        sbc     tgmPowersOf10+1,y
        sta     tgmMulTmp+1
        lda     tgmMulTmp+2
        sbc     tgmPowersOf10+2,y
        sta     tgmMulTmp+2
        inc     tgmDigits,x
        bne     @subtract
@nextDigit:
        iny
        iny
        iny
        inx
        cpx     #$05
        bne     @digit
        lda     tgmMulTmp
        sta     tgmDigits+5
        ; pack: score+2 = d0d1, score+1 = d2d3, score = d4d5
        ldx     #$02
        ldy     #$00
@pack:  lda     tgmDigits,y
        asl     a
        asl     a
        asl     a
        asl     a
        ora     tgmDigits+1,y
        sta     score,x
        iny
        iny
        dex
        bpl     @pack
        rts

tgmPowersOf10:
        .faraddr 100000, 10000, 1000, 100, 10

; ============================================================ grade/GM =====

; Checkpoint requirements, evaluated the first time level reaches 300 / 500.
tgmCheckGMRequirements:
        lda     tgmCheckpoint
        bne     @checkpoint500
        lda     tgmLevelHi
        cmp     #$03
        bcc     @ret
        ldx     #$00
        jsr     tgmCheckRequirement
        inc     tgmCheckpoint
@checkpoint500:
        lda     tgmCheckpoint
        cmp     #$01
        bne     @ret
        lda     tgmLevelHi
        cmp     #$05
        bcc     @ret
        ldx     #$06
        jsr     tgmCheckRequirement
        inc     tgmCheckpoint
@ret:   rts

; X = offset into tgmGMRequirements. Clears tgmGMPossible on failure.
tgmCheckRequirement:
        lda     tgmScore
        cmp     tgmGMRequirements+3,x
        lda     tgmScore+1
        sbc     tgmGMRequirements+4,x
        lda     tgmScore+2
        sbc     tgmGMRequirements+5,x
        bcc     @fail
        ; clock 4 frames after the lock <= mm:ss+ff
        lda     tgmClearTime+2
        cmp     tgmGMRequirements,x
        bcc     @ok
        bne     @fail
        lda     tgmClearTime+1
        cmp     tgmGMRequirements+1,x
        bcc     @ok
        bne     @fail
        lda     tgmGMRequirements+2,x
        cmp     tgmClearTime            ; limit >= frames
        bcs     @ok
@fail:  lda     #$00
        sta     tgmGMPossible
@ok:    rts

; Latest allowed time as minutes (BCD), seconds (BCD), frames, then the
; minimum score (24-bit). From the arcade's table at $80073D20: 15300, 27000
; and 48599 frames, grade 1 (12000), S4 (40000) and 126000 points.
tgmGMRequirements:
        .byte   $04,$15,0
        .faraddr 12000                  ; level 300 by 4:15:00
        .byte   $07,$30,0
        .faraddr 40000                  ; level 500 by 7:30:00
        .byte   $13,$29,59
        .faraddr 126000                 ; level 999 before 13:30:00

; Replaces playState_bTypeGoalCheck: reaching 999 ends the game and starts
; the credit roll.
playState_tgmCheckFinish:
        lda     tgmRoll
        bne     @ret
        lda     tgmLevelHi
        cmp     #$09
        bne     @ret
        lda     tgmLevel
        cmp     #$99
        bne     @ret
        ; Level 999! Stop the clock where the arcade does, 4 frames after the lock.
        lda     #$00
        sta     tgmTimerOn
        ldx     #$02
@setTime:
        lda     tgmClearTime,x
        sta     tgmTimeFrames,x
        dex
        bpl     @setTime
        jsr     tgmUpdateTimerTiles
        lda     tgmGMPossible
        beq     @noGM
        lda     tgmCheckpoint
        cmp     #$02
        bne     @noGM
        ldx     #$0C
        jsr     tgmCheckRequirement
        lda     tgmGMPossible
        beq     @noGM
        lda     #TGM_GM_GRADE
        sta     tgmGrade
        lda     outOfDateRenderFlags
        ora     #RENDER_GRADE
        sta     outOfDateRenderFlags
@noGM:  ; credit roll: empty field, 20G, keep playing
        lda     #$01
        sta     tgmRoll
        lda     #<TGM_ROLL_FRAMES
        sta     tgmRollTimer
        lda     #>TGM_ROLL_FRAMES
        sta     tgmRollTimer+1
        jsr     tgmUpdateGravity
        lda     #tileEmpty
        ldx     #>playfield
        ldy     #>playfield
        jsr     memset_page
        lda     #$00
        sta     vramRow
        lda     #$04
        sta     soundEffectSlot1Init    ; tetris jingle
        lda     #$40
        sta     tgmDelay                ; a short breather before the roll
@ret:   inc     playState
        rts

; Played the game to the end: show the ending, then go to high scores.
playState_tgmWin:
        lda     #$00
        sta     tgmTimerOn
        lda     #hidden
        sta     currentPiece
        lda     #$02
        jsr     setMusicTrack
        ldy     #$46
        ldx     #$00
@copySuccessGraphic:
        lda     typebSuccessGraphic,x
        cmp     #$80
        beq     @graphicCopied
        sta     (playfieldAddr),y
        inx
        iny
        jmp     @copySuccessGraphic

@graphicCopied:
        lda     #$00
        sta     player1_vramRow
        sta     vramRow
        jsr     sleep_for_14_vblanks
        lda     #$00
        sta     renderMode
        lda     #$80
        jsr     sleep_for_a_vblanks
        lda     #$02
        sta     spriteIndexInOamContentLookup
        lda     #$04
        sta     renderMode
        jsr     endingAnimationA
        lda     #$00
        sta     playState
        inc     gameModeState
        rts

; ================================================================ timer ====

tgmTickTimer:
        inc     tgmTimeFrames
        lda     tgmTimeFrames
        cmp     #60
        bcc     tgmUpdateTimerTiles
        lda     #$00
        sta     tgmTimeFrames
        lda     tgmTimeSec
        jsr     tgmBcdInc
        cmp     #$60
        bcc     @storeSec
        lda     tgmTimeMin
        cmp     #$99
        beq     @maxed
        jsr     tgmBcdInc
        sta     tgmTimeMin
        lda     #$00
@storeSec:
        sta     tgmTimeSec
        jmp     tgmUpdateTimerTiles

@maxed: lda     #$59
        sta     tgmTimeSec
        lda     #59
        sta     tgmTimeFrames
        ; fall through

; Stage mm:ss:cc as tiles for the NMI.
tgmUpdateTimerTiles:
        ldx     #$00
        lda     tgmTimeMin
        jsr     @twoDigits
        lda     #COLON_TILE
        sta     tgmTimerTiles,x
        inx
        lda     tgmTimeSec
        jsr     @twoDigits
        lda     #COLON_TILE
        sta     tgmTimerTiles,x
        inx
        ldy     tgmTimeFrames
        lda     tgmCentiseconds,y
@twoDigits:
        pha
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        sta     tgmTimerTiles,x
        inx
        pla
        and     #$0F
        sta     tgmTimerTiles,x
        inx
        rts

tgmBcdInc:
        clc
        adc     #$01
        pha
        and     #$0F
        cmp     #$0A
        pla
        bcc     @ret
        adc     #$05                    ; carry set: +6
@ret:   rts

; frame (0-59) -> hundredths of a second, BCD
tgmCentiseconds:
        .byte   $00,$01,$03,$05,$06,$08,$10,$11,$13,$15
        .byte   $16,$18,$20,$21,$23,$25,$26,$28,$30,$31
        .byte   $33,$35,$36,$38,$40,$41,$43,$45,$46,$48
        .byte   $50,$51,$53,$55,$56,$58,$60,$61,$63,$65
        .byte   $66,$68,$70,$71,$73,$75,$76,$78,$80,$81
        .byte   $83,$85,$86,$88,$90,$91,$93,$95,$96,$98

; ================================================================ render ===

; Called from the NMI renderer during play: grade box and timer.
; Skipped on frames that also redraw other HUD numbers: the original
; renderer already uses nearly all of vblank on those frames.
tgmRenderHud:
        lda     outOfDateRenderFlags
        and     #RENDER_STATS+RENDER_SCORE+RENDER_LEVEL+RENDER_LINES
        bne     @ret
        lda     outOfDateRenderFlags
        and     #RENDER_GRADE
        beq     @timer
        lda     #$23
        sta     PPUADDR
        lda     #$3A
        sta     PPUADDR
        ldx     tgmGrade
        lda     tgmGradeTile1,x
        sta     PPUDATA
        lda     tgmGradeTile2,x
        sta     PPUDATA
        lda     outOfDateRenderFlags
        and     #~RENDER_GRADE
        sta     outOfDateRenderFlags
@timer: lda     #$23
        sta     PPUADDR
        lda     #$8D
        sta     PPUADDR
        ldx     #$00
@tile:  lda     tgmTimerTiles,x
        sta     PPUDATA
        inx
        cpx     #$08
        bne     @tile
@ret:   rts

; grade -> two tiles in the game/menu font ("9" .. "1", "S1" .. "S9", "GM")
tgmGradeTile1:
        .byte   $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
        .byte   $1C,$1C,$1C,$1C,$1C,$1C,$1C,$1C,$1C
        .byte   $10
tgmGradeTile2:
        .byte   $09,$08,$07,$06,$05,$04,$03,$02,$01
        .byte   $01,$02,$03,$04,$05,$06,$07,$08,$09
        .byte   $16

; ================================================================ ending ===

; grade -> type A ending (rocket size). GM gets the cathedral.
tgmGradeToEnding:
        .byte   0,0,0,0,0, 1,1,1,1, 2,2,2,2, 3,3,3,3,3, 4

; Writes GRADE / TIME (and GRAND MASTER) onto the ending screen.
; PPU rendering must be off.
tgmDrawEndingText:
        lda     currentPpuCtrl          ; VRAM increment +1
        and     #$FB
        sta     currentPpuCtrl
        sta     PPUCTRL
        ldx     #$00
@string:
        lda     tgmEndingText,x
        cmp     #$FE
        beq     @strings_done
        sta     PPUADDR
        inx
        lda     tgmEndingText,x
        sta     PPUADDR
        inx
@char:  lda     tgmEndingText,x
        inx
        cmp     #$FD
        beq     @string
        sta     PPUDATA
        jmp     @char

@strings_done:
        ; grade value
        lda     #$20
        sta     PPUADDR
        lda     #$CE
        sta     PPUADDR
        ldx     tgmGrade
        lda     tgmGradeTile1,x
        cmp     #$1C
        bne     @notS
        lda     #$0A                    ; S in the ending font
@notS:  cmp     #$10
        bne     @notG
        lda     #$13                    ; G in the ending font
@notG:  sta     PPUDATA
        lda     tgmGradeTile2,x
        cmp     #$16
        bne     @notM
        lda     #ENDING_M_TILE
@notM:  sta     PPUDATA
        ; time value
        lda     #$21
        sta     PPUADDR
        lda     #$0E
        sta     PPUADDR
        ldx     #$00
@time:  lda     tgmTimerTiles,x
        cmp     #COLON_TILE
        bne     @digit
        lda     #ENDING_COLON_TILE
@digit: sta     PPUDATA
        inx
        cpx     #$08
        bne     @time
        ; GRAND MASTER
        lda     tgmGrade
        cmp     #TGM_GM_GRADE
        bne     @ret
        lda     #$21
        sta     PPUADDR
        lda     #$6A
        sta     PPUADDR
        ldx     #$00
@gm:    lda     tgmGrandMasterText,x
        sta     PPUDATA
        inx
        cpx     #12
        bne     @gm
@ret:   rts

; PPU address, tiles..., $FD; $FE ends. Type A ending font:
; 0-9 = $00-$09, S C O R E L V H I G T A - = $0A-$16, D M N : (added)
tgmEndingText:
        .byte   $20,$C7, $13,$0D,$15,ENDING_D_TILE,$0E, $FD     ; GRADE
        .byte   $21,$07, $14,$12,ENDING_M_TILE,$0E, $FD         ; TIME
        .byte   $23,$D2, $55, $FD       ; rows 8-11, cols 8-11: text palette (was sky-only palette 0)
        .byte   $FE
tgmGrandMasterText:
        .byte   $13,$0D,$15,ENDING_N_TILE,ENDING_D_TILE,$FF     ; GRAND
        .byte   ENDING_M_TILE,$15,$0A,$14,$0E,$0D               ; MASTER

.segment        "unreferenced_data4"
