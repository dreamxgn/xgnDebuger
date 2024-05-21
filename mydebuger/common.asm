.586
.model flat,stdcall
option casemap:none

include mydebuger.inc

public parseCmd,infoRegisters,unAssembly,saveThreadContext,szAsmFmg

.data
	szPrompt db ">",0
	szMsg db "显示线程上下文",LF,0
	szRegisterInfoFmt db "EAX = %X ECX = %X EDX = %X EBX = %X ESP = %X EBP = %X ESI = %X EDI = %X",LF
	db "GS = %X FS = %X ES = %X DS = %X SS = %X CS = %X EIP = %X EFLAGS = %X",LF,0h
	szTestFmt db "%X",LF,0h
	
	szCmd_U_Fmt db "u %x %d"
	szAsmFmg db "%s",LF,0h
	
	szCmd_DB_Fmt db "db %x %d",0h
	szCmd_DW_Fmt db "dw %x %d",0h
	szCmd_DD_Fmt db "dd %x %d",0h
	
	szCmd_EB_Fmt db "eb %x %x",0h
	szCmd_EW_Fmt db "ew %x %x",0h
	szCmd_ED_Fmt db "ed %x %x",0h
	
	szCmd_BP_Fmt db "bp %x",0h
	
	szLF_Fmt db LF,0h
	
	szMem_DB_Fmt db "%02X  ",0h
	szMem_DW_Fmt db "%04X  ",0h
	szMem_DD_Fmt db "%08X  ",0h
	
	szBP_Error_MSG db "无法在该地址设置断点 %08X",LF,0h
	
	szFindCall db "call",0h
	szDebugMsg db "系统断点被触发了",LF,0h
.code

;解析命令
parseCmd proc stdcall uses esi,nCmd:ptr Cmd
	LOCAL @szBuff[100] ;指令缓冲区
	assume esi:ptr Cmd
	mov esi,nCmd
	
	invoke RtlZeroMemory,nCmd,sizeof Cmd
	
	invoke printf,offset szPrompt
	invoke gets,addr @szBuff
	
	lea eax,@szBuff[0]
	
	.if [esi].mSize<=0
		mov [esi].mSize,08h
	.endif
	
	; 读取所有寄存器的值 r
	.if byte ptr [eax]=='r'
		mov [esi].mCmd,CMD_READ_REGISTER
		mov eax,Cmd
		ret
	.endif
	
	; CMD_STEP_G 运行指令(无视所有异常)
	.if byte ptr [eax]== 'g' && byte ptr [eax+1]== 's'
		mov [esi].mCmd,CMD_STEP_KG
		mov eax,Cmd
		ret
	.endif
	
	; CMD_STEP_G 运行指令
	.if byte ptr [eax]== 'g'
		mov [esi].mCmd,CMD_STEP_G
		mov eax,Cmd
		ret
	.endif
	
	;解析 u 命令
	.if byte ptr [eax]== 'u'
		
		invoke sscanf,addr @szBuff,offset szCmd_U_Fmt,addr [esi].mAddr,addr [esi].mSize
		mov [esi].mCmd,CMD_UNASSEMBLY
		mov eax,Cmd
		ret
		
	.endif
	
	;解析d 命令
	.if byte ptr [eax]=='d'
		
		;读取一个字节 db addr
		.if byte ptr [eax+1]=='b'
			invoke sscanf,addr @szBuff,offset szCmd_DB_Fmt,addr [esi].mAddr,addr [esi].mVal
			mov [esi].mCmd,CMD_READ_MEMORY
			mov [esi].mSize,01h
			mov eax,Cmd
			ret
		.endif
		
		;读取两个字节
		.if byte ptr [eax+1]=='w'
			invoke sscanf,addr @szBuff,offset szCmd_DW_Fmt,addr [esi].mAddr,addr [esi].mVal
			mov [esi].mCmd,CMD_READ_MEMORY
			mov [esi].mSize,02h
			mov eax,Cmd
			ret
		.endif
		
		;读取4个字节
		.if byte ptr [eax+1]=='d'
			invoke sscanf,addr @szBuff,offset szCmd_DD_Fmt,addr [esi].mAddr,addr [esi].mVal
			mov [esi].mCmd,CMD_READ_MEMORY
			mov [esi].mSize,04h
			mov eax,Cmd
			ret
		.endif
		ret
	.endif
	
	;解析e 命令
	.if byte ptr [eax]=='e'
		
		;写入一个字节 eb addr 数据
		.if byte ptr [eax+1]=='b'
			invoke sscanf,addr @szBuff,offset szCmd_EB_Fmt,addr [esi].mAddr,addr [esi].mVal
			mov [esi].mCmd,CMD_WRITE_MEMORY
			mov [esi].mSize,01h
			mov eax,Cmd
			ret
		.endif
		
		;读取两个字节
		.if byte ptr [eax+1]=='w'
			invoke sscanf,addr @szBuff,offset szCmd_EW_Fmt,addr [esi].mAddr,addr [esi].mVal
			mov [esi].mCmd,CMD_WRITE_MEMORY
			mov [esi].mSize,02h
			mov eax,Cmd
			ret
		.endif
		
		;读取4个字节
		.if byte ptr [eax+1]=='d'
			invoke sscanf,addr @szBuff,offset szCmd_ED_Fmt,addr [esi].mAddr,addr [esi].mVal
			mov [esi].mCmd,CMD_WRITE_MEMORY
			mov [esi].mSize,04h
			mov eax,Cmd
			ret
		.endif
		ret
	.endif
	
	;解析 bp 命令
	.if byte ptr [eax]=='b' && byte ptr [eax+1]=='p'
		invoke sscanf,addr @szBuff,offset szCmd_BP_Fmt,addr [esi].mAddr
		mov [esi].mCmd,CMD_BP
		mov eax,Cmd
		ret
	.endif
	
	;单步步过
	.if byte ptr [eax]=='p'
		mov [esi].mCmd,CMD_STEP_P
		mov eax,Cmd
		ret
	.endif
	
	;单步步进
	.if byte ptr [eax]=='t'
		mov [esi].mCmd,CMD_STEP_T
		mov eax,Cmd
		ret
	.endif
	xor eax,eax
	ret
parseCmd endp


;显示当前的寄存器信息
infoRegisters proc stdcall uses esi ,pEvent:ptr DEBUG_EVENT

	LOCAL @hContext:CONTEXT
	
	invoke threadContext,pEvent,addr @hContext
	.if eax==NULL
		ret
	.endif
	
	assume esi:ptr CONTEXT
	lea esi,@hContext
	
	mov eax,[esi].regFlag
	
	invoke printf,offset szRegisterInfoFmt,[esi].regEax,[esi].regEcx,[esi].regEdx,[esi].regEbx,[esi].regEsp,[esi].regEbp,[esi].regEsi,[esi].regEdi,
	[esi].regGs,[esi].regFs,[esi].regEs,[esi].regDs,[esi].regSs,[esi].regCs,[esi].regEip, eax
	
	ret

infoRegisters endp

;反汇编代码
unAssembly proc stdcall uses esi ,pEvent:ptr DEBUG_EVENT,ceip:dword,cAddr:dword,cSize:dword
	LOCAL @hProcess:dword ;进程句柄
	LOCAL @buff[MAXBYTE] ;读取的代码存放的缓冲区,每次读取 FF 字节。
	LOCAL @dwReadLen:dword ; 实际读取代码的长度
	LOCAL @ins[MAXBYTE] ; 反汇编后的指令字符串
	LOCAL @dwAsmLen:dword ;已反汇编的指令长度，单位: 字节
	
	mov @dwAsmLen,0h
	invoke RtlZeroMemory,addr @ins,MAXBYTE
	invoke RtlZeroMemory,addr @buff,MAXBYTE
	
	assume esi:ptr DEBUG_EVENT
	mov esi,pEvent
	
	invoke OpenProcess,PROCESS_ALL_ACCESS,FALSE,[esi].dwProcessId
	.if eax==NULL
		xor eax,eax
		ret
	.endif
	
	mov @hProcess,eax
	
	;读取指定地址处的代码字节
	invoke ReadProcessMemory,@hProcess,ceip,addr @buff,MAXBYTE,addr @dwReadLen
	.if eax==0
		invoke CloseHandle,@hProcess ;ReadProcessMemory 失败，关闭进程句柄。
		xor eax,eax
		ret
	.endif
	
	;显示 cSize 行反汇编指令
	.while cSize>0
		
		;初始化存在反汇编指令字符串的缓冲区
		invoke RtlZeroMemory,addr @ins,MAXBYTE
		
		;移动缓冲区@buff 到下一条指令的位置 base+已反汇编的指令长度
		lea ecx,@buff[0]
		add ecx,@dwAsmLen
		
		invoke disassembly,ceip,ecx,@dwReadLen,addr @ins
		
		.if eax<=0
			invoke CloseHandle,@hProcess
			mov eax,@dwAsmLen
			ret
		.endif
		
		add @dwAsmLen,eax ;增加已反汇编字节
		add ceip,eax ;增加EIP
		
		invoke printf,offset szAsmFmg,addr @ins
		dec cSize
	.endw
	
	invoke CloseHandle,@hProcess
	mov eax,@dwAsmLen
	ret
unAssembly endp


;显示当前线程EIP地址的反汇编
showEipAssembly proc stdcall,pEvent:ptr DEBUG_EVENT
	LOCAL @ctx:CONTEXT
	
	invoke threadContext,pEvent,addr @ctx
	.if eax==0
		ret
	.endif
	
	invoke unAssembly,pEvent,@ctx.regEip,@ctx.regEip,1

	ret
showEipAssembly endp


;获取线程上下文
threadContext proc stdcall uses esi,pEvent:ptr DEBUG_EVENT,pCtx:ptr CONTEXT
	LOCAL @hThread:dword
	
	assume esi:ptr DEBUG_EVENT
	mov esi,pEvent
	
	invoke RtlZeroMemory,pCtx,sizeof CONTEXT
	
	invoke OpenThread,THREAD_ALL_ACCESS,FALSE,[esi].dwThreadId
	.if eax==NULL
		ret
	.endif
	mov @hThread,eax
	
	assume esi:ptr CONTEXT
	mov esi,pCtx
	mov [esi].ContextFlags,CONTEXT_ALL
	
	invoke GetThreadContext,@hThread,pCtx
	.if eax==NULL
		invoke CloseHandle,@hThread
		xor eax,eax
		ret
	.endif
	
	invoke CloseHandle,@hThread
	mov eax,pCtx
	ret
threadContext endp

;保存线程上下文
saveThreadContext proc stdcall uses esi,pEvent:ptr DEBUG_EVENT,pCtx:ptr CONTEXT
	
	LOCAL @hThread:dword
	
	assume esi:ptr DEBUG_EVENT
	mov esi,pEvent
	
	invoke OpenThread,THREAD_ALL_ACCESS,FALSE,[esi].dwThreadId
	.if eax==NULL
		ret
	.endif
	mov @hThread,eax
	
	assume esi:ptr CONTEXT
	mov esi,pCtx
	mov [esi].ContextFlags,CONTEXT_ALL
	
	invoke SetThreadContext,@hThread,pCtx
	.if eax==NULL
		invoke CloseHandle,@hThread
		xor eax,eax
		ret
	.endif
	
	invoke CloseHandle,@hThread
	mov eax,pCtx
	ret
saveThreadContext endp

;读取进程内存
; baseAddr 内存地址
; nSize 读取的字节块大小
; nNum 读取多少块
; hProcess 进程句柄
; pEvent 事件结构体
cmdReadMemory proc stdcall uses esi ecx,pEvent:ptr DEBUG_EVENT,hProcess:dword,baseAddr:dword,nSize:dword,nNum:dword
	LOCAL @dwReadLen:dword  ;实际读取的字节数
	LOCAL @dwLineNum:dword ;行显示字节数量
	LOCAL @readLen:dword ; 需要读取的字节数量 nSize*nNum
	LOCAL @buff:dword ;缓冲区
	
	
	mov @dwLineNum,0h
	
	mov ecx,nSize
	mov eax,nNum
	mul ecx
	mov @readLen,eax
	
	;申请内存
	invoke malloc,@readLen
	.if eax==0
		ret
	.endif
	
	mov @buff,eax
	invoke RtlZeroMemory,@buff,@readLen
	
	
	
	
	invoke ReadProcessMemory,hProcess,baseAddr,@buff,@readLen,addr @dwReadLen
	.if eax==NULL
		ret
	.endif
	
	assume esi:nothing
	mov esi,@buff
	mov ecx,@dwReadLen
	
	.while @dwReadLen>0
		
		;每行显示16个字节数据
		.if @dwLineNum==010h
			invoke printf,offset szLF_Fmt
			mov @dwLineNum,0h
		.endif
		
		.if nSize==1
			invoke printf,offset szMem_DB_Fmt,byte ptr [esi]
		.endif
		
		.if nSize==2
			invoke printf,offset szMem_DW_Fmt,word ptr [esi]
		.endif
		
		.if nSize==4
			invoke printf,offset szMem_DD_Fmt,dword ptr [esi]
		.endif
		
		add esi,nSize
		mov eax,nSize
		add @dwLineNum,eax
		sub @dwReadLen,eax
	.endw
	invoke printf,offset szLF_Fmt
	ret
cmdReadMemory endp

;写入内存
cmdWriteMemory proc stdcall,pEvent:ptr DEBUG_EVENT,hProcess:dword,baseAddr:dword,buff:dword,nSize:dword
	LOCAL @oldProtect:dword
	
	mov @oldProtect,0
	
	invoke VirtualProtectEx,hProcess,baseAddr,nSize,PAGE_EXECUTE_READWRITE,addr @oldProtect
	.if eax==NULL
		xor eax,eax
		ret
	.endif

	invoke WriteProcessMemory,hProcess,baseAddr,buff,nSize,NULL
	
	;还原内存保护属性
	invoke VirtualProtectEx,hProcess,baseAddr,nSize,@oldProtect,addr @oldProtect
	mov eax,1
	ret
cmdWriteMemory endp

cmdSetBP proc stdcall,pEvent:ptr DEBUG_EVENT,hProcess:dword,bpAddr:dword
	LOCAL @ins:byte
	LOCAL @codeBuff[MAXBYTE]
	LOCAL @dwReadLen:dword
	LOCAL @cc:byte
	
	mov @cc,0cch
	
	mov @ins,0cch
	
	.if bpAddr<=0
		invoke printf,offset szBP_Error_MSG,bpAddr
		ret
	.endif
	
	mov eax,bpAddr
	mov gBPAddr,eax
	
	;读取原来的指令
	invoke ReadProcessMemory,hProcess,bpAddr,offset gBPOldCode,1,addr @dwReadLen
	.if eax==NULL
		ret
	.endif
	

	invoke ReadProcessMemory,hProcess,bpAddr,addr @codeBuff,MAXBYTE,addr @dwReadLen
	.if eax==0
		invoke CloseHandle,hProcess ;ReadProcessMemory 失败，关闭进程句柄。
		mov eax,DBG_EXCEPTION_NOT_HANDLED
		ret
	.endif
	
	;保存原来的汇编指令
	invoke disassembly,bpAddr,addr @codeBuff,@dwReadLen,offset gBPOldCodeAsm
	
	invoke cmdWriteMemory,pEvent,hProcess,bpAddr,addr @cc,1
	ret

cmdSetBP endp


;单步步过
;恢复断点处原有指令
;检测是否是call 指令，如果是call 指令就不能设置TF=1，需要在下条指令处设置int3。
cmdSingleStepP proc stdcall,pEvent:ptr DEBUG_EVENT,hProcess:dword,bpAddr:dword
	LOCAL @codeBuff[MAXBYTE] ;需要反汇编的指令内容
	LOCAL @dwReadLen:dword ;读取的指令长度
	LOCAL @ins[MAXBYTE] ;反汇编后的指令内容
	LOCAL @insLen:dword ;反汇编后的指令长度
	LOCAL @ctx:CONTEXT ;线程上下文
	LOCAL @nextCodeAddr:dword ;下一条指令地址
	
	
	
	;只有设置了断点才能恢复
	.if gBPAddr==0
		xor eax,eax
		ret
	.endif
	
	invoke RtlZeroMemory,addr @ins,MAXBYTE
	invoke RtlZeroMemory,addr @codeBuff,MAXBYTE
	invoke RtlZeroMemory,addr @ctx,sizeof CONTEXT
	
	
	;恢复原有指令
	;invoke cmdWriteMemory,pEvent,hProcess,gBPAddr,offset gOldCode,1
	
	;读取原代码
	invoke ReadProcessMemory,hProcess,gBPAddr,addr @codeBuff,MAXBYTE,addr @dwReadLen
	.if eax==0
		invoke CloseHandle,hProcess ;ReadProcessMemory 失败，关闭进程句柄。
		xor eax,eax
		ret
	.endif
	
	
	;判断是否是call 指令
	invoke disassembly,gBPAddr,addr @codeBuff,@dwReadLen,addr @ins
	mov @insLen,eax
	
	.if @insLen==NULL
		xor eax,eax
		ret
	.endif
	
	;判断是否是Call指令
	invoke strstr,addr @ins,offset szFindCall
	
	.if eax==NULL
		;不是call 指令,只需要设置单步标识 TF=1
		invoke threadContext,pEvent,addr @ctx
		or @ctx.regFlag,100h
		invoke saveThreadContext,pEvent,addr @ctx
		ret
	.else
		;是call 指令，需要将下一条指令改写为int 3
		mov eax,@insLen
		add eax,gBPAddr
		mov @nextCodeAddr,eax
		
		invoke cmdSetBP,pEvent,hProcess,@nextCodeAddr
		
		ret
	.endif
cmdSingleStepP endp

cmdStep_G proc stdcall,pEvent:ptr DEBUG_EVENT,hProcess:dword,exceptionAddr:dword
	LOCAL @codeBuff[MAXBYTE] ;需要反汇编的指令内容
	LOCAL @dwReadLen:dword ;读取的指令长度
	LOCAL @ins[MAXBYTE] ;反汇编后的指令内容
	LOCAL @insLen:dword ;反汇编后的指令长度
	LOCAL @ctx:CONTEXT ;线程上下文
	LOCAL @nextCodeAddr:dword ;下一条指令地址
	LOCAL @currCodeAddr:dword
	LOCAL @cc:byte
	
	mov @cc,0cch
	
	invoke RtlZeroMemory,addr @ins,MAXBYTE
	invoke RtlZeroMemory,addr @codeBuff,MAXBYTE
	invoke RtlZeroMemory,addr @ctx,sizeof CONTEXT
	
	mov eax,exceptionAddr
	mov @currCodeAddr,eax
	
	
	;恢复指令
	;系统断点
	.if gIsBreakSys==TRUE
		mov gIsBreakSys,FALSE
		invoke printf, offset szDebugMsg
		;系统断点被触发
		;读取原代码
		;add @currCodeAddr,1
		ret
	.endif
	
	;恢复代码,只有单步、BP断点触发才需要恢复代码
	mov eax,exceptionAddr
	
	;恢复单步
	.if gStepPAddr>0 && gStepPAddr==eax
		;恢复原有指令
		invoke cmdWriteMemory,pEvent,hProcess,gStepPAddr,offset gStepPCode,1
		.if eax==NULL
			mov eax,DBG_EXCEPTION_NOT_HANDLED
			ret
		.endif
		
		;重新设置EIP
		invoke threadContext,pEvent,addr @ctx
		mov eax,gStepPAddr
		mov @ctx.regEip,eax
		invoke saveThreadContext,pEvent,addr @ctx
		mov eax,exceptionAddr
		mov @currCodeAddr,eax
		
		
	
	;恢复断点	
	.elseif gBPAddr>0 && gBPAddr==eax
		;恢复原有指令
		invoke cmdWriteMemory,pEvent,hProcess,gBPAddr,offset gBPOldCode,1
		.if eax==NULL
			mov eax,DBG_EXCEPTION_NOT_HANDLED
			ret
		.endif
		
		;重新设置EIP
		invoke threadContext,pEvent,addr @ctx
		mov eax,gBPAddr
		mov @ctx.regEip,eax
		or @ctx.regFlag,0100h ;置TF=1
		invoke saveThreadContext,pEvent,addr @ctx
		mov eax,exceptionAddr
		mov @currCodeAddr,eax
		mov gBPMode,TRUE
		;需要设置一个标识并置TF=1,下下次单步异常时还原断点。
	.endif
	ret
cmdStep_G endp

; 设置单步步过断点
; exceptionAddr 产生异常的地址
;
;
cmdSetNextCodeBP proc stdcall,pEvent:ptr DEBUG_EVENT,hProcess:dword,exceptionAddr:dword
	LOCAL @codeBuff[MAXBYTE] ;需要反汇编的指令内容
	LOCAL @dwReadLen:dword ;读取的指令长度
	LOCAL @ins[MAXBYTE] ;反汇编后的指令内容
	LOCAL @insLen:dword ;反汇编后的指令长度
	LOCAL @ctx:CONTEXT ;线程上下文
	LOCAL @nextCodeAddr:dword ;下一条指令地址
	LOCAL @currCodeAddr:dword
	LOCAL @cc:byte
	
	mov @cc,0cch
	
	invoke RtlZeroMemory,addr @ins,MAXBYTE
	invoke RtlZeroMemory,addr @codeBuff,MAXBYTE
	invoke RtlZeroMemory,addr @ctx,sizeof CONTEXT
	
	mov eax,exceptionAddr
	mov @currCodeAddr,eax
	
	
	;恢复指令
	
	;系统断点
	.if gIsBreakSys==TRUE
		mov gIsBreakSys,FALSE
		invoke printf, offset szDebugMsg
		;系统断点被触发
		;读取原代码
		add @currCodeAddr,1
	.endif
	
	;恢复代码,只有单步、BP断点触发才需要恢复代码
	mov eax,exceptionAddr
	
	;恢复单步
	.if gStepPAddr>0 && gStepPAddr==eax
		;恢复原有指令
		invoke cmdWriteMemory,pEvent,hProcess,gStepPAddr,offset gStepPCode,1
		.if eax==NULL
			mov eax,DBG_EXCEPTION_NOT_HANDLED
			ret
		.endif
		
		;重新设置EIP
		invoke threadContext,pEvent,addr @ctx
		mov eax,gStepPAddr
		mov @ctx.regEip,eax
		invoke saveThreadContext,pEvent,addr @ctx
		mov eax,exceptionAddr
		mov @currCodeAddr,eax
		
		
	
	;恢复断点	
	.elseif gBPAddr>0 && gBPAddr==eax
		;恢复原有指令
		invoke cmdWriteMemory,pEvent,hProcess,gBPAddr,offset gBPOldCode,1
		.if eax==NULL
			mov eax,DBG_EXCEPTION_NOT_HANDLED
			ret
		.endif
		
		;重新设置EIP
		invoke threadContext,pEvent,addr @ctx
		mov eax,gBPAddr
		mov @ctx.regEip,eax
		or @ctx.regFlag,0100h ;置TF=1
		invoke saveThreadContext,pEvent,addr @ctx
		mov eax,exceptionAddr
		mov @currCodeAddr,eax
		mov gBPMode,TRUE
		;需要设置一个标识并置TF=1,下下次单步异常时还原断点。
	.endif
	
	

	invoke ReadProcessMemory,hProcess,@currCodeAddr,addr @codeBuff,MAXBYTE,addr @dwReadLen
	.if eax==0
		invoke CloseHandle,hProcess ;ReadProcessMemory 失败，关闭进程句柄。
		mov eax,DBG_EXCEPTION_NOT_HANDLED
		ret
	.endif

	;当前指令是否是call 指令
	invoke disassembly,@currCodeAddr,addr @codeBuff,@dwReadLen,addr @ins
	mov @insLen,eax
	
	.if @insLen==NULL
		mov eax,DBG_EXCEPTION_NOT_HANDLED
		ret
	.endif
	
	;invoke printf,addr @ins
	
	;判断是否是Call指令
	invoke strstr,addr @ins,offset szFindCall
	
	.if eax==NULL
		;不是call 指令,只需要设置单步标识 TF=1
		invoke threadContext,pEvent,addr @ctx
		or @ctx.regFlag,100h
		invoke saveThreadContext,pEvent,addr @ctx
		mov eax,DBG_CONTINUE
		
		mov gStepPAddr,0h
		mov gStepPCode,0h
		invoke RtlZeroMemory,offset gLastOldCode,064h
		mov eax,DBG_CONTINUE
		ret
	.else
		;是call 指令，需要将下一条指令改写为int 3
		mov eax,@insLen
		add eax,@currCodeAddr
		mov @nextCodeAddr,eax
		mov gStepPAddr,eax
		
		;读取原来的指令
		invoke ReadProcessMemory,hProcess,@nextCodeAddr,offset gStepPCode,1,addr @dwReadLen
		.if eax==NULL
			mov eax,DBG_EXCEPTION_NOT_HANDLED
			ret
		.endif
		
		invoke ReadProcessMemory,hProcess,@nextCodeAddr,addr @codeBuff,MAXBYTE,addr @dwReadLen
		.if eax==0
			invoke CloseHandle,hProcess ;ReadProcessMemory 失败，关闭进程句柄。
			mov eax,DBG_EXCEPTION_NOT_HANDLED
			ret
		.endif
		
		;保存原来的汇编指令
		invoke disassembly,gStepPAddr,addr @codeBuff,@dwReadLen,offset gLastOldCode
		
		invoke cmdWriteMemory,pEvent,hProcess,@nextCodeAddr,addr @cc,1
		
		mov eax,DBG_CONTINUE
		ret
	.endif
	
cmdSetNextCodeBP endp


;单步步进
cmdTrace proc stdcall,pEvent:ptr DEBUG_EVENT,hProcess:dword,exceptionAddr:dword
	LOCAL @ctx:CONTEXT ;线程上下文
	LOCAL @currCodeAddr:dword
	
		;恢复代码,只有单步、BP断点触发才需要恢复代码
	mov eax,exceptionAddr
	
	;恢复单步
	.if gStepPAddr>0 && gStepPAddr==eax
		;恢复原有指令
		invoke cmdWriteMemory,pEvent,hProcess,gStepPAddr,offset gStepPCode,1
		.if eax==NULL
			mov eax,DBG_EXCEPTION_NOT_HANDLED
			ret
		.endif
		
		;重新设置EIP
		invoke threadContext,pEvent,addr @ctx
		mov eax,gStepPAddr
		mov @ctx.regEip,eax
		invoke saveThreadContext,pEvent,addr @ctx
		mov eax,exceptionAddr
		mov @currCodeAddr,eax
		
		
	
	;恢复断点	
	.elseif gBPAddr>0 && gBPAddr==eax
		;恢复原有指令
		invoke cmdWriteMemory,pEvent,hProcess,gBPAddr,offset gBPOldCode,1
		.if eax==NULL
			mov eax,DBG_EXCEPTION_NOT_HANDLED
			ret
		.endif
		
		;重新设置EIP
		invoke threadContext,pEvent,addr @ctx
		mov eax,gBPAddr
		mov @ctx.regEip,eax
		or @ctx.regFlag,0100h ;置TF=1
		invoke saveThreadContext,pEvent,addr @ctx
		mov eax,exceptionAddr
		mov @currCodeAddr,eax
		mov gBPMode,TRUE
		;需要设置一个标识并置TF=1,下下次单步异常时还原断点。
	.endif
	
	
	
	;置TF=1位
	invoke threadContext,pEvent,addr @ctx
	or @ctx.regFlag,100h
	invoke saveThreadContext,pEvent,addr @ctx
	mov gTraceMode,TRUE
	ret
cmdTrace endp

end