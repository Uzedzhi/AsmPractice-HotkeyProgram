.286
model tiny
.code
org 100h

locals @@

;-------------------------------
; macro which prints "pixel" to buffer 'SaveBuffer' with index di
; IN:		di			- index where it prints
; 			Ah 			- Color argument
;			Al			- char argument
; OUT:					  in buffer pixel is placed
; DESTR:	DI
;-------------------------------
PRINTCHARANDINC MACRO Char, Color
		mov ah, Color
		mov al, Char
		stosw
endm

Start:          CLD
	            call ParseAllFlags
;----------------------------------------------------------------
; this block makes it so our program wont open a second time
; at the start of each interrupt function we have a construction
; similar to this:
;   	jmp @@SkipHeader
;		db 'ITS_MY_TSR_INTRUDER'
;		@@SkipHeader:
;----------------------------------------------------------------
; ===================Exit if segment of old interrupt func is the default one==================
				; get current interrupt segment and offset
				; into es:[bx]
				mov ax, 3509h
				int 21h					
				; because repe cmpsb compares strings from es:[di] to ds:[si]
				; we should place old segment and offset to es:[di]
				
				; es is already installed
				mov di, bx					; in di is offset of current 09 int func
				add di, 2                   ; sip 2 bytes from 'jmp short' instruction

				mov si, offset HeaderStr    ; DS:SI points to our signature
				xor cx, cx
				mov cl, HeaderLen           ; CX = len of signature

				repe cmpsb                  ; compare cx bytes from ES:DI to DS:SI
				jne @@DontExitProgram       ; if found mismatch - dont exit program, it means our int func has not been placed yet

				mov dx, offset ProgramIsAlreadyRunningErrorString
				sti
				call ExitWithError          ; EOP because we try to place to of the same residents
				@@DontExitProgram:
; =================================Exited or continuing========================================
; ============================saving old 9 interrupt func pos==================================
				push 0
                pop es                      ; es = 0 segment pointer
                mov bx, 4 * 09h             ; bx = pos of 09h func in the actual memory
                
					; changing 09h interception to ours
                CLI ; cli to not get an interrupt halfway while we are changing pos
                mov dx, es:[bx]             ; dx = segment of 9 interrupt func
                mov OldOffsetOf9Int, dx
                
                mov dx, es:[bx + 2]
                mov OldSegmentOf9Int, dx ; saving old segment and offset values
; ========================================Saved================================================
; =============================initializing our interrupt func=================================
				; if we dont have 'enable dynamic' flag enabled
				; when we are initializing hlt program, it hlts processor when openes menushka
				; if dynamic is enabled, menushka updates every tick.
				; changing address of int func right from the memory.
				; first byte is index, second is segment
				cmp [EnabledDynamic], 01h
				je @@InitNonHltIntFunc
				
				mov bx, 4 * 09h
				; hlt function
                mov es:[bx], offset Our09FuncHltEdition
				jmp @@EndOfInterruptFuncInit

				; non hlt function
				@@InitNonHltIntFunc:
				mov es:[bx], offset Our09FuncNonHltEdition

				; second byte is segment
				@@EndOfInterruptFuncInit:
                mov ax, cs                  ; ax = current segment pointer
                mov es:[bx+2], ax
; =============================initialized======================================================
;===============================saving old 08 interrupt func====================================
                mov bx, 4 * 08h
                mov dx, es:[bx]
                mov OldOffsetOf8Int, dx
                mov dx, es:[bx + 2]
                mov OldSegmentOf8Int, dx
; =========================================saved=================================================
; =============================initializing our own 8 interrupt func=============================
				; just like this 9 interrupt, we are changing 8 interrupt func to ours. 
				; the process is as described above
				; first byte is address
                mov es:[bx], offset Our08FuncTimerEdition

				; second byte is segment
                mov ax, cs
                mov es:[bx + 2], ax
; ==========================================initialized==========================================
                sti	; now resuming interrupt signaling

                mov ah, 31h                 ; ah = code of dos func to stay residient
                mov al, 00h                 ; al = exit code of this func
                mov dx, offset ENDOFOURFUNC
				
                shr dx, 4h                  ; dx = size of the program to stay residient
                inc dx
                int 21h


IsHalted	db 00h
;----------------------------------------------------------------------------
; this function is responsible for opening menushka without halting the processor.
; the process is simple:
; if menushka isnt opened, when open it and each tick our 08 interrupt will trigger, which will
; check if there are any changes in the menushka in video memory.
; if there are, then update buffers responsible
; for keeping the videomemory accurate
; and then update video memory
; if menushka is opened
; ignore any non hotkey scan code and wait for user to press hot key
; once pressed, the 08 interrupt func will become "normal"(old one) and menushka will disappear from the videomemory
;----------------------------------------------------------------------------
Our09FuncNonHltEdition proc
	jmp short @@SkipHeader
	db 'ITS_MY_TSR_INTRUDER'
	@@SkipHeader:
	; because it is resident interrupt func,
	; it doesnt destroy anything
	push ss es ds bp sp di si dx cx bx ax

	; changing bp to sp to later use
	; it to access regex values
	mov bp, sp

	; moving cs to ds
	; it is needed to make sure then we
	; acsess the memory our segment is right
	push cs
	pop ds
	STI

	cmp cs:[IsOpenMenu], 01h		; if menu is opened
	je @@CheckIfPressedClose		; when ckeck if we pressed hotkey to close it

; ==================in this section menu is not opened=======================
    in al, 60h                      ; al = pressed key
    cmp al, cs:[HotKey]             ; if pressed key is Hotkey('1')
    je @@CallOpenMenushka    		; when open menushka
	jmp @@Exit						; else call old 09 interrupt func
; ================================section end================================

; =================in this section menu is opened============================
	@@CheckIfPressedClose:
	in al, 60h
	cmp al, cs:[Hotkey]				; if pressed close
	je @@CallCloseMenushka
	cmp al, cs:[HltHotKey]
	je @@HltUntilNextHltHotKey
	jmp @@Exit
; ================================section end================================

	@@HltUntilNextHltHotKey:
	cmp cs:[IsHalted], 00h
	je @@SkipExit
	mov cs:[IsHalted], 00h
	jmp @@Exit
	@@SkipExit:
	mov cs:[IsHalted], 01h
	
	sti
	@@Loop:
		hlt

		cmp [IsHalted], 00h
		je @@Exit
		jmp @@Loop
; ================================Opening menushka================================
	@@CallOpenMenushka:
	call PlaceFrameFromVMToBuffer 	; placing videomemory into buffer
	mov cs:[IsOpenMenu], 01h		; menu is opened
	call OpenMenushka				; opening menushka
	jmp @@Exit
; ================================Opened Menushka=================================

; ===============================Closing Menushka=================================
	@@CallCloseMenushka:
	mov cs:[IsOpenMenu], 00h		; menu is closed
	call PlaceFrameFromBufferToVM	; close menu in videomemory
; ====================================Closed======================================

	@@Exit:
    pop ax bx cx dx si di
	add sp, 2
	pop bp ds es ss
    jmp dword ptr cs:[OldOffsetOf9Int]
	iret
endp

;--------------------------------------------------------------
; func which turns hex value like F to actual value at cx
; IN:		ds:[si] - char position
; OUT:		CX 		- hex value of ds[al] symbol OR -1 if not in diapason 0-9 && A-F
; Destroys:	BX, CX
;--------------------------------------------------------------
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

	; now in bx is value of 0-5 
	@@PassedTesthex:
	add bx, 0Ah		; if our char is 'A'-'F' when add 0Ah

	@@PassedTest:
	mov cx, bx
	ret
endp

;---------------------------------------------------------------
; таймерное прерывание — сравнивает MenuSaveBuffer с видеопамятью.
; При расхождении копирует изменённый символ в VmBuffer
; и восстанавливает значение рамки в видеопамяти
; Работает только пока меню открыто
;---------------------------------------------------------------
Our08FuncTimerEdition proc
	push ss es ds bp sp di si dx cx bx ax
	mov bp, sp
	; т.к. функция прерывания(резидентная)
	; то сохраняем все значения регистров

    cmp cs:[IsOpenMenu], 01h 	; если меню не открыто
    jne @@CallOld08Func			; то скипаем наше прерывания, возвращаемся к старому

    push cs
    pop ds                          ; ds = cs(для правильное адресации к памяти)
    push 0b800h
    pop es                          ; es = сегмент видеопамяти
    call PlaceFrameStartToBx        ; bx = смещение левого верхнего угла рамки в видеопамяти
    xor si, si                      ; si = индекс в буфере
    mov dx, 11h                     ; счётчик строк

    @@RowLoop:
        mov cx, FrameLen            ; счётчик символов в строке
        @@ColLoop:
            mov ax, es:[bx]                          ; слово из видеопамяти

            cmp ax, cs:[offset MenuSaveBuffer + si]	 ; если слово и значение в видеопамяти совпадают то 
            je @@Same                                ; пропускаем

			; иначе это означает что
			; чужая прога нарисовала поверх нашей рамки
			; мы должны это исправить и сначала сохранить этот
			; инородный элемент в нашем массиве, который
			; сохраняет все значения под рамкой(Vmbuffer), а потом
			; восстановить рамку в видеопамяти из массива(MenuSavebuffer)
            mov cs:[offset VmBuffer + si], ax  		; сохраняем в буфер значений под рамкой
            mov ax, cs:[offset MenuSaveBuffer + si] ; восстанавливаем значение рамки
			mov es:[bx], ax

        	@@Same:
            add si, 2 ;
            add bx, 2 ; инкрементируем все индексы
			dec cx	  ; спускаемся вних на одону строчку
            jnz @@ColLoop ; если cx = 0 то выходим из цикла

        add bx, 160d - (FrameLen * 2)   ; пропускаем остаток строки экрана
        dec dx
        jnz @@RowLoop

	call OpenMenushka
    @@CallOld08Func:
    pop ax bx cx dx si di
	add sp, 2
	pop bp ds es ss
    jmp dword ptr cs:[OldOffsetOf8Int]  ; цепочка к старому обработчику
	iret
endp


;--------------------------------------------------------------
; func which turns 2 hex values in ascii like 4ch to actual value at cx
; IN:		ds:[si] - char position
; OUT:		CX 		- hex value of ds[al] symbol OR -1 if not in diapason 0-9 && A-F
; Destroys:	BX, SI, CX, SI(places it at the end of the hex char)
;--------------------------------------------------------------
Convert2BytesToHex proc
	; first hex value
	call ConvertToHex

	cmp cx, -1h		; if not hex exti with error
	je @@ExitFunc

	shl cx, 4h ; store hex value as 00X0h
	push cx ; first hex value stored in stack

	; second hex value
	inc si
	call ConvertToHex

	cmp cx, -1h		; if not hex exti with error
	je @@ExitFuncWithPop

	pop bx 		; bx = first hex value as 000X
	add cx, bx ; adding hex values together: 00X0 + 000X = 00XX - 1 byte of hex value

	@@ExitFunc:
	ret

	@@ExitFuncWithPop:
	pop cx		; popping on on the second check to clear stack
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
; Destroys:	si, DX, CX, DI
;-------------------------------
GetValueFromInput proc
	mov si, dx
	call CheckIfHexCharorDec
	; now in cx is identificator of our prefix

	inc si ; to skip prefix

	mov di, cx
	shl di, 1		; di = cx * 2
	jmp [offset @@TableOfJumps + di]

	@@TableOfJumps:
	dw offset @@NoPrefix
	dw offset @@HPrefix
	dw offset @@DPrefix
	dw offset @@CPrefix

	@@NoPrefix:
	dec si ; if no prefix then where is nothing to skip
	@@Hprefix:
	@@Dprefix: ;	TODO ToDecimal
		call Convert2BytesToHex
		jmp @@continue
	@@Cprefix:
		mov cl, ds:[si]		; no need to convert, just place ascii code in the regex
		jmp @@continue
	@@continue:
		mov dx, offset ErrorString		; init error str in case there is an error
		cmp cx, -1h
		je ExitWithError

		mov dx, si
		ret
endp

;-------------------------------
; exits the program entirely, prints errror string to the console
; IN:		dx 		- error string address
; OUT:		program dies
; Destroys:	program
;-------------------------------
ExitWithError proc
	mov ah, 09h	; print error str
	int 21h

	mov ax, 4c00h ; DIIIIE
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
; -so: style of the main frame(id 11)
; -ed: enable dynamic update(id 12)
; IN:		ds:[dl] - start of the flag
; OUT:		cx		- flag id
; Destroys:	si, cx, dx, di
;-------------------------------
ArrayOfFlagNames   		db 'x', ' ', 'y', ' ', 'ft', 'fs', 'rt', 'lt', 'lb', 'rb', 'cb', 'ci', 'so', 'ed'
IdentifyFlag proc
	mov cx, 0Dh 	; amount of flags + 1
	mov di, dx
	mov bx, [di]	; bx = flag in command line

	@@Loop:
		test cx, cx	; if cx(counter) is zero then flag is not found
		je @@Exit	; return with no flag

		dec cx		; decrement counter after check to check 0th index also

		mov si, cx
		shl si, 1	; si = cx * 2

		; comparing flag name in cmd with flag name in array
		; if equal then we found the flag
		cmp bx, ds:[offset ArrayOfFlagNames + si]
		je @@LoopExit

		jmp @@Loop
	@@LoopExit:
	inc cx
	cmp cx, 02h
	jbe @@Exit
	inc dx

	@@Exit:
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
; -so: style of the main frame(id 11)
; -ed: enable dynamic update(id 12)
; IN:		ds:[si] - start of the string
; OUT:		it will place all flag values to the specific flags
; 			which were placed in command line.
; Exp:		DF = 0
; Destroys:	All variables that can change are in 'frame variables' part of consts
;-----------------------------------------------------------------------------------------------
ParseAllFlags proc
	mov dx, CommandLineStrStart ; dx = current pos in the cmd line

	; 81h = start of cmd
	; [80h] = len of cmd line
	; 81h + [80h] = end of cmd line
	mov cl, ds:[80h]
	mov byte ptr EndOfCmdLine, cl
	add EndOfCmdLine, 80h
	xor cx, cx

	@@Loop:
		; comparing current pos(dx) in the cmd to the heighest value(
		cmp dx, EndOfCmdLine
		jae @@Exit

;======================get char=====================
		mov ax, '-'				; al is symbol we try to locate
		mov di, dx				; di is current pos in cmd string
		mov cx, EndOfCmdLine	; cl is end of cmd line(explained above)
		sub cx, dx				; subbing from end of line current pos in the cmd to get max len we can read from cmd

		mov bx, cx				; saving cx to bx
		repne scasb

		sub cx, bx
		neg cx 					; return index of the symbol '-'
;========================done=========================

		; now cx is index of that symbol
		; and we are adding to that index current pos in the cmd, so we arrive at symbol '-'
		add dx, cx
		dec dx

		; if the address of the symbol we arrived at above is more than
		; end of cmd then there is no more symbol '-'
		cmp dx, [EndOfCmdLine]
		jae @@Exit

		inc dx	; +1 to current pos in cmd to skip '-' symbol and get to flag name

		call IdentifyFlag	; now cx = flag id
		test cx, cx			; if cx is NF when throw an error
		je @@NFERROR

		; skipping last flag char and ' ' to arrive at flag value
		add dx, 2h

		cmp cx, 0Bh
		je @@StyleFlag
		cmp cx, 0Ch
		je @@EnabledDynamicFlag

		push cx					; pushing flag id
		call GetValueFromInput	; get that value
								; now cl = flag value
		pop si 					; popping flag id, si = flag id

		; now we are placing our value(cl)  into the desired variable/
		; all variables are located in DATA segment and sorted by rising of flag id
		; for example. 'X' has flag id 1 so its placed in the code as 1st variable
		; so if we write to address of X + flag id when we will write into variable orf that same flag id
		mov [offset X + si - 1], cl	
		jmp @@Loop

	    @@StyleFlag:
		call GetValueFromStyleFlag
		jmp @@Loop

		@@EnabledDynamicFlag:
		mov [EnabledDynamic], 01h
		jmp @@Loop

	@@NFERROR:
		mov dx, offset NoFlagErrorStr
		call ExitWithError
	@@Exit:
		ret

endp
; CX - flag id
; DX - current pos at the flag value 
GetValueFromStyleFlag proc
	push di bx

	mov di, NumOfFlags
	@@Loop:
		test di, di
		je @@Exit

		dec di
		push di
		call GetValueFromInput	; get that value
		pop di
		
		; now cl = flag value
		mov bx, offset X + NumOfFlags - 1
		sub bx, di
		mov cs:[bx], cl
		inc dx
		jmp @@Loop

	@@Exit:
	pop bx di
	ret
endp

; ============================================DATA SEGMENT========================================================
OldOffsetOf8Int     dw 00h
OldSegmentOf8Int    dw 00h

; error strings
ErrorString							db 'ERROR: you typed incorrect command line prompt, correct usage: <program name>.com -<flag name> <flag value> ... -<flag name> <flag value>$'
ErrorStringPos						db 'ERROR: you typed incorrect X or Y pos values. they should in diapason 00h <= X <= 90h, 00h <= Y <= 21h$'
FatalErrorString					db 'ERROR: fatal$'
ProgramIsAlreadyRunningErrorString	db 'ERROR: program is already running in resident mode$'
NoFlagErrorStr						db 'ERROR: invalid flag. please use one of the accepted flags.$'

; header string
HeaderStr							db 'ITS_MY_TSR_INTRUDER'
HeaderLen							db 13h

; frame variables
HltHotKey			db 1Bh
HotKey              db 1Ah
X                   db 28h
Y                   db 05h
FrameCharacterTop   db '#'
FrameCharacterSide	db '#'
RTcorner			db '#'
LTcorner			db '#'
LBcorner			db '#'
RBcorner			db '#'
ColorCodeBorder		db 7Eh
ColorCodeInner		db 70h
EnabledDynamic		db 00h

FrameLen            equ 12h     ; 12h to fit perfectly all regex and flags
CommandLineStrStart	equ 82h
WordsEndPos			dw 0000h
EndOfCmdLine		dw 0000h

; Old interrupt func location
OldOffsetOf9Int     dw 00h
OldSegmentOf9Int    dw 00h
NumOfFlags			equ 0Ah



; SaveBuffer is an array which holds previous video segment data.
; It is used only for opening menushka with hlt
; it is initialized to perfectly fit in the frame 18x17 pixels, 2 bytes for each pixel
IsOpenMenu			db 00h
SaveBuffer 			db FrameLen * 17 * 2 dup(0) 
MenuSaveBuffer 		db FrameLen * 17 * 2 dup(0) 
VmBuffer 			db FrameLen * 17 * 2 dup(0) 

;========================================================END OF DATA SEGMENT========================================================

;----------------------------------------------------------------------------------------
; эта функция оборачивает стандартную функцию прерывания 9h
; и ждет пока пользователь нажмет на горячую клавишу.
; По нажатию открывается менюшка с регистрами и процессор останавливает
; свою работу, но продолжает слушать прерывания.
; Когда он поймает еще прерывание с нажатием той же горячец клавиши,
; он закроет менюшку и продолжит работу как ни в чем не бывало.
; Открытие многоразовое
;----------------------------------------------------------------------------------------
Our09FuncHltEdition proc
	jmp short @@SkipHeader
	db 'ITS_MY_TSR_INTRUDER'
	@@SkipHeader:
    push ss es ds bp sp di si dx cx bx ax
	mov bp, sp

	cmp cs:[IsOpenMenu], 01h		; if menu is opened
	je @@CheckIfPressedClose		; when ckeck if we pressed hotkey to close it

; ==================in this section menu is not opened=======================
    in al, 60h                      ; al = pressed key
    cmp al, cs:[HotKey]             ; if pressed key is Hotkey('1')
    je @@CallOpenMenushka    		; when open menushka
	jmp @@CallOld09Func				; else call old 09 interrupt func
; ================================section end================================

; =================in this section menu is opened============================
	@@CheckIfPressedClose:
	in al, 60h
	cmp al, cs:[Hotkey]		; if pressed close
	je @@CallCloseMenushka
	call BlinkBit
	jmp @@Exit
; ================================section end================================

; ================================Opening menushka================================
	@@CallOpenMenushka:
	push cs
	pop ds
	call PlaceFrameFromVMToBuffer 	; placing videomemory into buffer
	mov cs:[IsOpenMenu], 01h		; menu is opened
	call OpenMenushka				; opening menushka
	call BlinkBit					; blink to signal we ended our interrupt
; ================================Opened Menushka=================================

; =================cycle waiting for hotkey to be presed again====================
	sti
	@@IntLoop:
		hlt

		cmp cs:[IsOpenMenu], 00h
		jne @@IntLoop
	; if we are out of the cycle it means that user pressed hotkey
	; again and closed the menushka. So we can peacefully exit the func
	jmp @@Exit
; ===================================cycled=======================================

	@@CallCloseMenushka:
	call PlaceFrameFromBufferToVM
	mov cs:[IsOpenMenu], 00h
	call BlinkBit

	@@Exit:
	pop ax bx cx dx si di
	add sp, 2
	pop bp ds es ss
    iret

	@@CallOld09Func:
    pop ax bx cx dx si di
	add sp, 2
	pop bp ds es ss
    jmp dword ptr cs:[OldSegmentOf9Int]
	iret

endp

;------------------------------------------------------------------
; Копирует прямоугольник экрана ПОД будущей рамкой в массив buffer
; OUT:		сохраняет в массив SaveBuffer 17x18x2 байт значений пикселей экрана
;------------------------------------------------------------------
PlaceFrameFromVMToBuffer proc
	push ds es bx si di cx
    cld
    call PlaceFrameStartToBx    ; Теперь bx = адрес верхнего левого угла рамки

    push 0b800h
    pop ds                      ; ds = Сегмент видеопамяти
    push cs
    pop es                      ; es = сегмент кода

    mov si, bx                  ; SI указывает на экран
    mov di, offset VmBuffer

    mov dx, 17d
	@@RowLoop:
	    mov cx, FrameLen
	    rep movsw                   

	    add si, 160d - (FrameLen * 2) ; переходим на новую строку

	    dec dx
	    jnz @@RowLoop
	pop cx di si bx es ds
    ret
endp

;------------------------------------------------------------------
; Копирует значения пикселей из буфера в видеопамять, затирая рамку
; и сохраняя последнюю версию открытой программы
; OUT:		сохраняет в массив 17x18x2 байт значений пикселей экрана
;------------------------------------------------------------------
PlaceFrameFromBufferToVM proc
	push ds es bx si di cx
    cld
    call PlaceFrameStartToBx    ; Теперь bx = адрес верхнего левого угла рамки

    push 0b800h
    pop es                      ; ds = Сегмент видеопамяти
    push cs
    pop ds                      ; es = сегмент кода

    mov si, offset VmBuffer     ; si = указатель на массив
    mov di, bx					; di = указатель на экран

    mov dx, 17d
	@@RowLoop:
	    mov cx, FrameLen
	    rep movsw                 

	    add di, 160d - (FrameLen * 2) 

	    dec dx
	    jnz @@RowLoop
	pop cx di si bx es ds
    ret
endp

;---------------------------------------------------------------
; ложит в bx индекс, на который нужно сместиться от начала видео памяти чтобы попасть на Y строку и X пиксель в этой строке
; EXP:		X, Y - x and y coordinates
; DESTR:	bx, ax, dx
;---------------------------------------------------------------
PlaceFrameStartToBx proc
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
endp


;---------------------------------------------------------------
; эта функция моргает битиком в 61h прерывание чтобы
; сигнализировать что мы закончили обрабатывать прерывание и готовы принять следующее
;---------------------------------------------------------------
BlinkBit proc
	in al, 61h                      ; al = значение, полученное от чтение 61 порта(клавиатуры)
    mov ah, al                      ; ah = дублирует al
    or al, 80h                      ; al = значение из порта, но с установленным битиком(битом блокировки клавиатуры)
    out 61h, al                     ; запускаем этот бит в порт 61h
    mov al, ah                      ; al = восстанавливаем ah
    out 61h, al                     ; запускаем в порт значение с разблокировкой клавиатуры

    mov al, 20h
    out 20h, al
	ret
endp

;---------------------------------------------------------------
; функция открывает менюшку в видеопамяти.
; она выводит все регистры и флаги, из значения и названия.
; пример выводы менюшки:
;
; 				##################
; 				# ax: 0000 CF: 0 #
; 				# bx: 0000 PF: 1 #
; 				# cx: 0005 AF: 0 #
; 				# dx: fd88 ZF: 0 #
; 				# si: c98d SF: 0 #
; 				# di: 9a8d TF: 0 #
; 				# sp: 9183 IF: 1 #
; 				# bp: 2134 DF: 0 #
; 				# ds: 3443 OF: 0 #
; 				# es: 0123	   	 #
; 				# ss: 01EF	   	 #
; 				# ip: 034D	   	 #
; 				# cs: 019E	   	 #
; 				##################
; рамка кастомизируется переменными, расположенными в 
; data segment под комментарием frame variables
; DESTR: ax, di, bx, cx, es, si
;---------------------------------------------------------------
OpenMenushka proc
	call PrintMenushkaToSaveBuffer

	push ds es bx si di cx
    cld
    call PlaceFrameStartToBx    ; Теперь bx = адрес верхнего левого угла рамки

    push 0b800h
    pop es                      ; ds = Сегмент видеопамяти
    push cs
    pop ds                      ; es = сегмент кода

    mov si, offset MenuSaveBuffer     ; si = указатель на массив
    mov di, bx					; di = указатель на экран

    mov dx, 17d
	@@RowLoop:
	    mov cx, FrameLen
	    rep movsw                 

	    add di, 160d - (FrameLen * 2) 

	    dec dx
	    jnz @@RowLoop
	pop cx di si bx es ds
    ret

	ret
endp

PrintMenushkaToSaveBuffer proc
	mov bx, offset MenuSaveBuffer
	push cs
	pop es
    mov al, LTcorner
	mov ah, RTcorner

    mov di, bx
    call PrintBorderRow

    add bx, FrameLen * 2
    mov di, bx
    call PrintNormalRow

; printing all regex values and names to the frame
    xor cx, cx
    @@Loop:
        cmp cx, 0Dh
        je @@ExitLoop

        add bx, FrameLen * 2
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

; ==========================Print Normal Row========================
    add bx, FrameLen * 2
    mov di, bx
    mov cx, dx
    call PrintNormalRow
; ========================Printed========================

; ========================Print Border row========================
    mov al, LBcorner
	mov ah, RBcorner

    add bx, FrameLen * 2
    mov di, bx
    mov cx, dx
    call PrintBorderRow
; ========================printed========================

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


; regex and glaf names, needed for later pprinting
AllRegex            db 'ax', 'bx', 'cx', 'dx', 'si', 'di', 'sp', 'bp', 'ds', 'es', 'ss', 'ip', 'cs' ; names of all the regex
AllFlags            db 'CF', 'PF', 'AF', 'ZF', 'SF', 'TF', 'IF', 'DF', 'OF' ; all flags in order of appearing in the flag register
AllFlagsBits        db  0,    2,    4,    6,    7,    8,    9,    10,   11 ; shows which bit does this flag correspond to
;	/\
; tells which bit of flag regex does the flag above correspond to

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

ENDOFOURFUNC:
end Start