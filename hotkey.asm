.286
model tiny
.code
org 100h

locals @@

;-------------------------------
; macro which prints "pixel" to video memory at es:[di]
; IN:		es:[di]		- spot where it prints
; 			Ah 			- Color argument
;			Al			- char argument
; OUT:					  on screen pixel is displayed
; EXP:		es = 0b800h - segment of visible videomemory
; DESTR:	DI
;-------------------------------
PRINTCHARANDINC MACRO Char, Color
		mov ah, Color
		mov al, Char
		mov word ptr es:[di], ax
		add di, 2h
endm

Start:          CLD
	            call ParseAllFlags

                push 0
                pop es                      ; es = 0 segment pointer
                mov bx, 4 * 09h             ; bx = pos of 09h func in the actual memory
                ; changing 09h interception to ours
                CLI

                mov dx, es:[bx]             ; dx = Offset of 9 interrupt func
                mov OldOffsetOf9Int, dx
                
                mov dx, es:[bx + 2]
                mov OldSegmentOf9Int, dx ; saving old segment and offset values

                mov es:[bx], offset Our09func
                mov ax, cs                  ; ax = current segment pointer
                mov es:[bx+2], ax
                STI

                mov ah, 31h                 ; ah = code of dos func to stay residient
                mov al, 00h                 ; al = exit code of this func
                mov dx, offset ENDOFOURFUNC
                shr dx, 4h                  ; dx = size of the program to stay residient
                inc dx

                int 21h

;-------------------------------
; func which turns hex value like F to actual value at cx
; IN:		ds:[si] - char position
; OUT:		CX 		- hex value of ds[al] symbol OR -1 if not in diapason 0-9 && A-F
; Destroys:	BX
;-------------------------------
ConvertToHex proc
	; check if 0-9
	xor bx, bx
	mov bl, ds:[si]
	sub bx, '0'
	cmp bx, 9h
	jbe @@PassedTest

	; check if A-F
	sub bx, 'A' - '0'
	cmp bx, 5h
	jbe @@PassedTesthex

	; check if a-f
	sub bx, 'a' - 'A'
	cmp bx, 5h
	jbe @@PassedTesthex

	; if not a hex\/_\/
	mov cx, -1h
	ret

	@@PassedTest:
	xor cx, cx
	mov cx, bx
	ret

	@@PassedTesthex:
	add bx, 0Ah
	mov cx, bx
	ret
endp

;-------------------------------
; func which turns 2 hex values in ascii like 4ch to actual value at cx
; IN:		ds:[si] - char position
; OUT:		CX 		- hex value of ds[al] symbol OR -1 if not in diapason 0-9 && A-F
; Destroys:	BX, SI
;-------------------------------
Convert2BytesToHex proc
	; first hex value
	call ConvertToHex

	cmp cx, -1h
	je @@ExitFunc

	shl cx, 4h ; store hex value as 00X0h
	push cx ; first hex value stored in stack

	; second hex value
	inc si
	call ConvertToHex

	cmp cx, -1h
	je @@ExitFuncWithPop

	pop bx 		; bx = first hex value as 000X
	add cx, bx ; adding hex values together: 00X0 + 000X = 00XX - 1 byte of hex value

	@@ExitFunc:
	ret

	@@ExitFuncWithPop:
	pop cx
	mov cx, -1h
	ret
endp

;-------------------------------
; func which checks if ds:[si] Has H\h(Hex), D\d(decimal number) C\c(Char) prefix, or no prefix at all(Default is Hex)
; IN:		ds:[si] - char
; OUT:		cx = 0 if no prefix, 
;			cx = 1 if H prefix
;			cx = 2 if D prefix
;			cx = 3 if C prefix
; Destroys:	cx
;-------------------------------
CheckIfHexCharorDec proc
	xor cx, cx

	cmp byte ptr ds:[si], 'H'
	je @@exit1
	cmp byte ptr ds:[si], 'h'
	je @@exit1

	cmp byte ptr ds:[si], 'D'
	je @@exit2
	cmp byte ptr ds:[si], 'd'
	je @@exit2

	cmp byte ptr ds:[si], 'C'
	je @@exit3
	cmp byte ptr ds:[si], 'c'
	je @@exit3

	; exit with 0
	ret

	@@exit3:
		inc cx
	@@exit2:
		inc cx
	@@exit1:
		inc cx
		ret
endp

;-------------------------------
; check ds:[si] to identify prefix.
; if prefix is 1('H') or 2('D') - gets 2 bytes in hex\decimal format from ds:[si] and converts them to hex in cx
; if prefix is 3('C')			- gets 1 byte from ds:[si] and places it to cx
; if prefix is 0(None)			- gets 2 bytes in hex format
; IN:		ds:[si] - char
; OUT:		cx		- hex format of char as stated in description
; Destroys:	si
;-------------------------------
GetValueFromInput proc
	call CheckIfHexCharorDec
	; now in cx is identificator of our prefix

	inc si ; to skip prefix
	cmp cx, 00h
	je @@NoPrefix

	cmp cx, 01h
	je @@HPrefix

	cmp cx, 02h
	je @@DPrefix

	cmp cx, 03h
	je @@CPrefix

	; if somehow none of these values are  true, throm an ErrorS
	mov dx, offset FatalErrorString
	call ExitWithError

	@@NoPrefix:
	dec si ; if no prefix then where is nothing to skip
	@@Hprefix:
		call Convert2BytesToHex
		jmp @@continue
	@@Dprefix:
		call Convert2BytesToHex ; TODO ToDecimal
		jmp @@continue
	@@Cprefix:
		mov cl, ds:[si]
		jmp @@continue
	
	@@continue:
		mov dx, offset ErrorString
		cmp cx, -1h
		je ExitWithError
		ret

endp


;-------------------------------
; exits the program entirely, prints errror string to the console
; IN:		dx 		- error string address
; OUT:		program dies
; Destroys:	program
;-------------------------------
ExitWithError proc
	mov ah, 09h
	int 21h

	mov ax, 4c00h
	int 21h
	ret
endp

;-------------------------------
; check ds:[si] to identify flag and return its id in cx register
; -x: x pos of top left corner of frame (id 1)
; -y: y pos of top left corner of frame (id 2)
; -ft: The character of which does frame top and bottom part consist of (id 3)
; -fs: The character of which does frame left and right part consist of (id 4)
; -lt: left top corners (id 6)
; -rt: right top corner (id 5)
; -rb: right bottom corner (id 8)
; -lb: left bottom corner (id 7)
; -cb: color of border (id 9)
; -ci: color of inner frame (id 10)
; -s:  main string, written inside of frame (id 4)
; IN:		ds:[si] - start of the flag
; OUT:		cx		- flag id
; Destroys:	si, cx
;-------------------------------
IdentifyFlag proc
	xor cx, cx

	cmp byte ptr ds:[si], 'x'
	je @@XposFlag

	cmp byte ptr  ds:[si], 'y'
	je @@YposFlag

	cmp byte ptr ds:[si], 'f'
	je @@FrameCharFlags

	cmp byte ptr ds:[si], 'l'
	je @@LeftCornerFlags

	cmp byte ptr ds:[si], 'r'
	je @@RightCornerFlags

	cmp byte ptr ds:[si], 'c'
	je @@ColorFlags

	; no flags
	@@noflags:
	mov cx, 00h
	ret

	@@LeftCornerFlags:
	inc si
	cmp byte ptr ds:[si], 't'
	je @@LTcornerFlag

	cmp byte ptr ds:[si], 'b'
	je @@LBcornerFlag
	jmp @@noflags

	@@RightCornerFlags:
	inc si
	cmp byte ptr ds:[si], 't'
	je @@RTcornerFlag

	cmp byte ptr ds:[si], 'b'
	je @@RBcornerFlag
	jmp @@noflags

	@@ColorFlags:
	inc si
	cmp byte ptr ds:[si], 'b'
	je @@ColorCodeBorderFlag

	cmp byte ptr ds:[si], 'i'
	je @@ColorCodeInnerFlag
	jmp @@noflags

	@@FrameCharFlags:
    inc si
	cmp byte ptr ds:[si], 't'
	je @@FrameCharTopFlag

	cmp byte ptr ds:[si], 's'
	je @@FrameCharSideFlag
	jmp @@noflags

	@@ColorCodeInnerFlag:
	inc cx
	@@ColorCodeBorderFlag:
	inc cx
	@@RBcornerFlag:
	inc cx
	@@LBcornerFlag:
	inc cx
	@@LTcornerFlag:
	inc cx
	@@RTcornerFlag:
	inc cx
	@@FrameCharSideFlag:
	inc cx
	@@FrameCharTopFlag:
	inc cx
	@@YposFlag:
	inc cx
	@@XposFlag:
	inc cx
	ret
	
endp


;----------------------------------------------------------------------------------------------
; this function will start parsing flags from ds:[82h] up to end of str
; flag always starts with '-' and when right after it should be flag Id.
; Ids are as follows:
; -x: x pos of top left corner of frame (id 1)
; -y: y pos of top left corner of frame (id 2)
; -ft: The character of which does frame top and bottom part consist of (id 3)
; -fs: The character of which does frame left and right part consist of (id 4)
; -lt: left top corners (id 6)
; -rt: right top corner (id 5)
; -rb: right bottom corner (id 8)
; -lb: left bottom corner (id 7)
; -cb: color of border (id 9)
; -ci: color of inner frame (id 10)
; IN:		ds:[si] - start of the string
; OUT:		it will place all flag values to the specific flags
; 			which were placed in command line.
; Exp:		DF = 0
; Destroys:	All variables that can change are in 'frame variables' part of consts
;-----------------------------------------------------------------------------------------------
ParseAllFlags proc
	xor ax, ax
	mov cx, ds:[80h]		 	; cx - current len until the end of str
	mov bx, cx					; bx is also same

	xor dx, dx
	mov si, CommandLineStrStart ; si = cmdstart


	; loop of iteration across all '-' symbols found in the command line
	; it will iterate while si < EndOfCommandLine (si < ax)
	@@Loop:
		mov al, ds:[80h] 		; moving strlen to the ax
		add ax, 82h				; ax = start of cmd + strlen = end of cmd
		cmp si, ax
		jae @@exit

		mov cx, ax
		sub cx, si

		mov al, '-'		; al is symbol we try to locate
		mov di, si		; di is cmd str
		call GetChar

		; now cx is index of that symbol
		cmp cx, bx  ; if cx is strlen that means no symbol '-'
		jae @@exit

		add si, cx		; si points to the '-' symbol
		inc si

		call IdentifyFlag
		; now cx has flag id
		add si, 2h ; now si is on flag value

		cmp cx, 00h
		je @@NF

		push cx ;  flag id
		call GetValueFromInput
		pop bx
		; cx = value, bx = flag id
		cmp bx, 01h
		je @@X
		cmp bx, 02h
		je @@Y
		cmp bx, 03h
		je @@FT
        cmp bx, 04h
		je @@FS
		cmp bx, 05h
		je @@RT
		cmp bx, 06h
		je @@LT
		cmp bx, 07h
		je @@LB
		cmp bx, 08h
		je @@RB
		cmp bx, 09h
		je @@CB
		cmp bx, 0Ah
		je @@CI

    @@Exit:
		ret

    @@NF:
        jmp @@ExitWithNoFlagError
    @@X:
        mov X, cl
        jmp @@loop
    @@Y:
        mov Y, cl
        jmp @@loop
    @@FS:
        mov FrameCharacterSide, cl
        jmp @@loop
    @@FT:
        mov FrameCharacterTop, cl
        jmp @@loop
    @@RT:
        mov RTcorner, cl
        jmp @@loop
    @@LT:
        mov LTcorner, cl
        jmp @@loop
    @@LB:
        mov LBcorner, cl
        jmp @@loop
    @@RB:
        mov RBcorner, cl
        jmp @@loop
    @@CB:
        mov ColorCodeBorder, cl
        jmp @@loop
    @@CI:
        mov ColorCodeInner, cl
        jmp @@loop

	@@ExitWithNoFlagError:
		mov dx, offset NoFlagErrorStr
		call ExitWithError
		ret

endp

; error strings
ErrorString			db 'ERROR: you typed incorrect command line prompt, correct usage: <program name>.com <X> <Y> <Framecharacter> <LTcorner> <RTcorner> <RBcorner> <LBcorner> <Colorcode1> <Colorcode2>$'
ErrorStringPos		db 'ERROR: you typed incorrect X or Y pos values. they should in diapason 00h <= X <= 90h, 00h <= Y <= 21h$'
FatalErrorString	db 'ERROR: fatal$'
NoFlagErrorStr		db 'ERROR: invalid flag. please use one of the accepted flags.$'

; frame variables
HotKey              db 02h      ; '1'
X                   db 28h
Y                   db 05h
FrameCharacterSide	db '#'
FrameCharacterTop   db '#'
LTcorner			db '#'
LBcorner			db '#'
RTcorner			db '#'
RBcorner			db '#'
ColorCodeBorder		db 7Eh
ColorCodeInner		db 70h
FrameLen            equ 12h     ; 12h to fit perfectly all regex and flags
CommandLineStrStart	equ 82h
WordsEndPos			dw 0000h

; Old interrupt func location
OldOffsetOf9Int     dw 00h
OldSegmentOf9Int    dw 00h

Our09func proc
;AllRegex            db 'ax', 'bx', 'cx', 'dx', 'si', 'di', 'sp', 'bp', 'ds', 'es', 'ss', 'ip', 'cs' ; names of all the regex
    push ss es ds bp sp di si dx cx bx ax
    cld
	mov bp, sp						; now bp = pointer to all of regex values

    in al, 60h                      ; al = pressed key
    cmp al, cs:[HotKey]             ; if pressed key is Hotkey('1')
    jne @@CallOld09InterruptFunc    ; when open menushka else goto old func

    push cs
    pop ds                          ; ds = current segment pointer
    call OpenMenushka

    in al, 61h                      ; al = значение, полученное от чтение 61 порта(клавиатуры)
    mov ah, al                      ; ah = дублирует al
    or al, 80h                      ; al = значение из порта, но с установленным битиком(битом блокировки клавиатуры)
    out 61h, al                     ; запускаем этот бит в порт 61h
    mov al, ah                      ; al = восстанавливаем ah
    out 61h, al                     ; запускаем в порт значение с разблокировкой клавиатуры

    mov al, 20h
    out 20h, al

    pop ax bx cx dx si di
	add sp, 2
	pop bp ds es ss
    iret

    @@CallOld09InterruptFunc:
    pop ax bx cx dx si di
	add sp, 2
	pop bp ds es ss
    jmp dword ptr cs:[OldOffsetOf9Int]
endp

OpenMenushka proc
    push 0b800h
    pop es                         ; es = videomemory segment

; placing bx = Y * RowLen + X * 2 (pos of top left corner of the frame)
	xor bx, bx			; bx = 0
	mov bl, X			; bx = X
	shl bx, 1			; bx = bx * 2 (bx = X * 2)

    xor dx, dx          ; dx = 0
	mov dl, Y			; dl = Y
	mov ax, 160d     	; ax = Rowlen
	mul dx				; ax = Y * RowLen
	add bx, ax			; bx = bx + ax (bx = X * 2 + Y * Rowlen)
; placed

    mov al, LTcorner
	mov ah, RTcorner

    mov di, bx
    call PrintBorderRow

    add bx, 80d * 2
    mov di, bx
    call PrintNormalRow

; printing all regex values and names to the frame
    xor cx, cx
    @@Loop:
        cmp cx, 0Dh
        je @@ExitLoop


        add bx, 80d * 2
        mov di, bx
        call PrintNormalRow

        mov di, bx
        add di, 4h

        push cx
        call PrintRegexById
        pop cx

        cmp cx, 8h
        ja @@DontPrintFlag
        ; we print flag value and name in here

        push cx
        add di, 2h
        call PrintFlagById
        pop cx

        @@DontPrintFlag:
        ; flags are all printed

        inc cx
        jmp @@Loop

    @@ExitLoop:
; done printing



    add bx, 80d * 2
    mov di, bx
    mov cx, dx
    call PrintNormalRow

    mov al, LBcorner
	mov ah, RBcorner

    add bx, 80d * 2
    mov di, bx
    mov cx, dx
    call PrintBorderRow

    ret

endp

;------------------------------------------
; prints flag name and value like: CF: 1
; IN:		ES:DI = print position
;			cx    = flag id
; OUT:				prints row to es:di
; EXP:		
; Destroys:	cx, dx, ax, di, si
;------------------------------------------
PrintFlagById proc    
    ; print name of flag to es:[di]
    ; name is 2 bytes
    mov si, cx
    shl si, 1                   ; si = si * 2
    add si, offset AllFlags     ; now si = address of flag name

    mov dx, cs:[si]             ; dh = first symbol of the flag, dl = second

	PRINTCHARANDINC dl, ColorCodeInner
	PRINTCHARANDINC dh, ColorCodeInner
	PRINTCHARANDINC ':', ColorCodeInner
	PRINTCHARANDINC ' ', ColorCodeInner

    mov ax, ss:[bp + 26d]      ; ax = all flags in order

    ; printing bit corresponding to the flag
    mov si, cx
    add si, offset AllFlagsBits         ; si = адрес в памяти, где лежит то, на каком бите значение флага

    mov cl, cs:[si]    ; si = на каком бите в регистре ax находится значение флага
    xor ch, ch         ; зануляем ch

    shr ax, cl          ; теперь первый бит в ax показывает значение нашего флага
    and ax, 01h         ; зануляем все остальные биты

    mov dx, ax
    add dx, '0'
    PRINTCHARANDINC dl, ColorCodeInner

    ret 
endp


AllRegex            db 'ax', 'bx', 'cx', 'dx', 'si', 'di', 'sp', 'bp', 'ds', 'es', 'ss', 'ip', 'cs' ; names of all the regex
AllFlags            db 'CF', 'PF', 'AF', 'ZF', 'SF', 'TF', 'IF', 'DF', 'OF' ; all flags in order of appearing in the flag register
AllFlagsBits        db  0,    2,    4,    6,    7,    8,    9,    10,   11 ; shows which bit does this flag correspond to

Previous videoframe

;------------------------------------------
; prints regex name and value like: ax: 0000
; IN:		ES:DI = start position
;			cx    = regex id
; OUT:				prints row to es:di
; EXP:		DF 	  = 0
; Destroys:	cx, dx, ax, di, si
;------------------------------------------
PrintRegexById proc
    ; print name of regex to es:[di]
    ; name is 2 bytes
    mov si, cx
    shl si, 1                   ; si = si * 2
    add si, offset AllRegex     ; now si = address of regex name
    mov dx, cs:[si]             ; dh = first symbol of the regex, dl = second

    PRINTCHARANDINC dl, ColorCodeInner
    PRINTCHARANDINC dh, ColorCodeInner
    PRINTCHARANDINC ':', ColorCodeInner
    PRINTCHARANDINC ' ', ColorCodeInner

    call PrintRegexValueById

    ret
endp

;------------------------------------------
; prints regex value like: 0000
; IN:		ES:DI = print position
;			cx    = regex id
; OUT:				prints value to es:di
; Destroys:	cx, ax, di, dx, si
;------------------------------------------
PrintRegexValueById proc
    shl cx, 1                           ; cx = cx * 2

	mov si, cx
	add si, bp		; si = bp + cx * 2
    mov dx, ss:[si]

; getting the first byte
    mov ax, dx      ; ax = dx value
    and ax, 0F000h  ; ax & 111100...000000
    shr ax, 12      ; now in al is 1st regex byte
    call ConvertFromHexToAsciiSymbol ; now cx = ascii symbol of first hex in regex
    PRINTCHARANDINC cl, ColorCodeInner
    
; got it

; getting the second byte
    mov ax, dx
    and ax, 00F00h  ; ax & 0000111100...0000
    shr ax, 8       ; now in al 2nd regex byte
    call ConvertFromHexToAsciiSymbol ; now cx = ascii symbol of first hex in regex
    PRINTCHARANDINC cl, ColorCodeInner
; got it

;getting the third byte
    mov ax, dx
    and ax, 000F0h  ; ax & 0000...0011110000
    shr ax, 4       ; now in al is 3rd regex byte
    call ConvertFromHexToAsciiSymbol ; now cx = ascii symbol of first hex in regex
    PRINTCHARANDINC cl, ColorCodeInner
; got it

;getting the fourth byte
    mov ax, dx
    and ax, 0000Fh  ; ax & 000000...001111
    call ConvertFromHexToAsciiSymbol ; now cx = ascii symbol of first hex in regex
    PRINTCHARANDINC cl, ColorCodeInner
; got it

endp


;------------------------------------------
; converts value in al to 1 hex symbol (only first 4 bits)
; IN:		AL    = value
; OUT:		Cl    = ascii symbol of first 4 bits in AL
; Destroys:	cx, ax
;------------------------------------------
ConvertFromHexToAsciiSymbol proc
    xor cx, cx
    and AL, 0Fh

    cmp AL, 9h
    jbe @@ConvertToNum

    ; then its not num, its letter
    add al, 'A' - 0Ah
    mov cl, al
    jmp @@Exit

    @@ConvertToNum:
    add al, '0'
    mov cl, al

    @@Exit:
    ret

endp

;------------------------------------------
; prints row of corners repeating chars like <Lcorner>##############<Rcorner>
; IN:		ES:DI = row start position
;			AX    = corner values(al - left corner, ah - right corner)
; OUT:				prints row to [es:di, es:di + cx]
; EXP:		DF 	  = 0
; Destroys:	CX, DI, AX
;------------------------------------------
PrintBorderRow proc
	push ax
; PRINT left corner
	PRINTCHARANDINC al, ColorCodeBorder
; printed

; print main border
	mov cx, FrameLen - 2
	mov al, FrameCharacterTop
	mov ah, ColorCodeBorder
	rep stosw
; Printed

	pop ax
	mov al, ah
; print right corner
	PRINTCHARANDINC al, ColorCodeBorder
; printed

	ret
endp

;------------------------------------------
; prints row in form of #_________#, _ is space
; IN:		ES:DI - row start position
; OUT:		prints to [es:di, es:di + cx] row
; EXP:		DF 	  = 0
; Destroys:	CX, DI, AX
;------------------------------------------
PrintNormalRow proc
	PRINTCHARANDINC FrameCharacterSide, ColorCodeBorder

    push cx
	mov cx, FrameLen - 2
	mov al, ' '
	mov ah, ColorCodeInner
	rep stosw
    pop cx

	PRINTCHARANDINC FrameCharacterSide, ColorCodeBorder
	ret
endp

;------------------------------------------
; finds the al symbol in string es:di, returns index (reads no more than cx symbols)
; IN:		ES:DI - source string
; 			AL	  - symbol
;			CX	  - string len
; OUT:		CX    - symbol position
; EXP:		DF 	  = 0
; Destroys:	DI, BX
;------------------------------------------
GetChar proc
	mov bx, cx
	repne scasb

	je @@Found
	; delimiter not found
	sub cx, bx
	neg cx ; no delimiter found, so return string len
	ret

	@@Found:
	; delimiter found:
	sub cx, bx
	neg cx
	dec cx ; if delimiter found we substract its len from the answer to get actual index
	ret
endp

ENDOFOURFUNC:

end Start