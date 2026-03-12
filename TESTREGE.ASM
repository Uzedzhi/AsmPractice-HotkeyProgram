.286
.model tiny
.code
locals @@

org 100h
Start:			mov di, 0441Fh
				mov cx, offset ENDOFOURPROG - offset checkregex
				; ds:[si] -> es:[di]
				mov si, offset checkregex

				push 05555h
				pop es

				mov di, 441Fh
				rep movsb

				jmp dword ptr [JumpTo]

				JumpTo:
				dw 441Fh, 05555h

				OFFSET100H:

				mov ax, 4c00h
				int 21h

checkregex proc
	mov ax, 1111h
	mov bx, 2222h
	mov cx, 3333h
	mov dx, 4444h
	mov si, 5555h
	mov di, 4444h
	mov bp, 2222h
	push 1111h
	pop ds
	push 2222h
	pop es
	push 3333h
	pop ss
	push 3333h + 0Eh
	pop sp
	jmp $
	ret
endp

ENDOFOURPROG:

end Start