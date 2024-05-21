.586
.model flat,stdcall
option casemap:none

 include mydebuger.inc



   .data
   	;szMsg db "输出中文测试",10,0
   	szUnKnowCmd db "无法识别的命令",0ah,0
   	szExePath db 100 dup(0) ;被调试程序的路径
	pInfo PROCESS_INFORMATION<0>
	
	;szPrompt db ">",0
	szFmt db "%s\n",0
	szCmd db "0",0
	gLastCodeAddr dword 0h
	gUnAsmErrMsg db "反汇编错误",0ah,0h
	szDMsg db "检查到CC指令，先恢复",LF,0h
	
	
	gBPAddr dd 0h ; 断点地址
	gBPOldCode byte 0h ; 原来的指令
	gBPOldCodeAsm db 100 dup(0)
	gBPMode byte 0h
	gBPCC byte 0cch ; int3指令
	
	
	gIsBreakSys byte 01h ;中断于系统断点 
	gIsCC byte 0h
	
	gStepPAddr dd 0h ;单步的断点地址
	gStepPCode dd 0h ;单步的原代码
	
	gTraceMode byte 0h ;单步步进模式
	
	gLastOldCode db 100 dup(0h) ;最后一次int 3断点的原汇编指令
	

	gerrMsg db "产生异常的地址 %08X",LF,0h
   .code



getDebugExe proc stdcall uses esi
	LOCAL @args:dword
   	
   	invoke GetCommandLine
   	mov @args,eax
   	
   	.if eax==NULL
   		xor eax,eax
   		ret
   	.endif
   	
   	mov esi,eax
   	xor eax,eax
findSpace:
   	lodsb
   	cmp al,20H
   	jne findSpace

	invoke strcpy,offset szExePath,esi
	mov eax,offset szExePath
	ret

getDebugExe endp

dbgCREATE_PROCESS_DEBUG_EVENT proc stdcall,pEvent:ptr DEBUG_EVENT
	mov eax,DBG_CONTINUE
	ret
dbgCREATE_PROCESS_DEBUG_EVENT endp

dbgCREATE_THREAD_DEBUG_EVENT proc stdcall,pEvent:ptr DEBUG_EVENT
	jmp main
	szLabel:
		db "CREATE_THREAD_DEBUG_EVENT",0AH,0
	
	main:
	;invoke printf,offset szLabel
	
	mov eax,DBG_CONTINUE
	ret
dbgCREATE_THREAD_DEBUG_EVENT endp

dbgEXCEPTION_DEBUG_EVENT proc stdcall,pEvent:ptr DEBUG_EVENT
	LOCAL @cmd:Cmd ; 解析到的命令
	LOCAL @pException:ptr EXCEPTION_DEBUG_INFO
	LOCAL @ctx:CONTEXT
	LOCAL @hProcess:dword ; 进程句柄
	LOCAL @eAddr:dword; ;触发异常的代码地址
	LOCAL @keepCmd:byte;
	LOCAL @dwResult:dword
	
	assume esi:ptr DEBUG_EVENT
	mov esi,pEvent
	mov eax,[esi].u.Exception.pExceptionRecord.ExceptionAddress
	mov @eAddr,eax
	
	;打开进程
	invoke OpenProcess,PROCESS_ALL_ACCESS,FALSE,[esi].dwProcessId
	.if eax<=0
		mov eax,DBG_EXCEPTION_NOT_HANDLED
		ret
	.endif
	mov @hProcess,eax
	
	invoke RtlZeroMemory,addr @cmd,sizeof Cmd
	
	lea eax,[esi].u.Exception
	mov @pException,eax
	mov @keepCmd,TRUE
	
	.while TRUE
		
		;收到异常消息事件首先打印当前线程环境信息
		invoke infoRegisters,pEvent
		invoke printf,offset gerrMsg,@eAddr
		mov ebx,@eAddr
		mov eax,offset gLastOldCode
		
		
		.if byte ptr [eax]!=0h && gStepPAddr==ebx
			invoke printf,offset szAsmFmg,offset gLastOldCode
		.elseif gBPAddr==ebx
			invoke printf,offset szAsmFmg,offset gBPOldCodeAsm
		.elseif gBPMode==TRUE
			invoke printf,offset szAsmFmg,offset gLastOldCode
		.else
			invoke showEipAssembly,pEvent
		.endif
		
		
		;恢复断点
		.if gBPMode==TRUE
			mov gBPMode,FALSE
			invoke cmdWriteMemory,pEvent,@hProcess,gBPAddr,offset gBPCC,1
			.if eax==NULL
				mov eax,DBG_EXCEPTION_NOT_HANDLED
				mov @dwResult,eax
				.break
			.endif
			
			.if gTraceMode==TRUE
				mov gTraceMode,FALSE
				;置TF=1位
				invoke threadContext,pEvent,addr @ctx
				or @ctx.regFlag,100h
				invoke saveThreadContext,pEvent,addr @ctx
				.continue
			.endif

			mov eax,DBG_CONTINUE
			mov @dwResult,eax
			.break
		.endif
		
		
		;打印当前异常代码地址的反汇编指令
		;invoke showEipAssembly,pEvent
		;invoke unAssembly,pEvent,@eAddr,@eAddr,1

		;解析命令
		invoke parseCmd,addr @cmd
		
		;未识别的命令
		.if eax==0
			invoke printf,offset szUnKnowCmd
			.continue
		.endif
		
		;显示寄存器信息
		.if @cmd.mCmd==CMD_READ_REGISTER
			invoke infoRegisters,pEvent
			.continue
		.endif
		
		;运行
		.if @cmd.mCmd==CMD_STEP_G
			invoke cmdStep_G,pEvent,@hProcess,@eAddr
			mov eax,DBG_CONTINUE
			mov @dwResult,eax
			.break
		.endif
		
		;运行(无视所有异常)
		.if @cmd.mCmd==CMD_STEP_KG
			invoke cmdStep_G,pEvent,@hProcess,@eAddr
			mov eax,DBG_EXCEPTION_NOT_HANDLED
			mov @dwResult,eax
			.break
		.endif
		
		;反汇编
		.if @cmd.mCmd==CMD_UNASSEMBLY
			;没有指定代码地址且上一次代码地址为空,使用EIP的地址
			.if @cmd.mAddr<=0
				
				.if gLastCodeAddr<=0
					assume edi:ptr EXCEPTION_DEBUG_INFO
					mov edi,@pException
					mov ecx, [edi].pExceptionRecord.ExceptionAddress
					mov @cmd.mAddr,ecx
					mov gLastCodeAddr,ecx
				.else
					mov ecx,gLastCodeAddr
					mov @cmd.mAddr,ecx ;使用上次代码地址
				.endif
				
			.else
				mov ecx,@cmd.mAddr
				mov gLastCodeAddr,ecx
			.endif
			
			;反汇编
			invoke unAssembly,pEvent,@cmd.mAddr,@cmd.mAddr,@cmd.mSize
			
			.if eax<=0
				invoke printf,gUnAsmErrMsg
			.else
				mov ecx,gLastCodeAddr
				add ecx,eax
				mov gLastCodeAddr,ecx
			.endif
			.continue
		.endif
		
		;读取内存
		.if @cmd.mCmd==CMD_READ_MEMORY
			invoke cmdReadMemory,pEvent,@hProcess,@cmd.mAddr,@cmd.mSize,@cmd.mVal
			.continue
		.endif
		
		;写入内存
		.if @cmd.mCmd==CMD_WRITE_MEMORY
			invoke cmdWriteMemory,pEvent,@hProcess,@cmd.mAddr,addr @cmd.mVal,@cmd.mSize
			.continue
		.endif
		
		
		;设置软件断点 int 3
		.if @cmd.mCmd==CMD_BP
			invoke cmdSetBP,pEvent,@hProcess,@cmd.mAddr
			.continue
		.endif
		
		;单步步过
		.if @cmd.mCmd==CMD_STEP_P
			;处理单步、断点异常
			.if [esi].u.Exception.pExceptionRecord.ExceptionCode ==EXCEPTION_BREAKPOINT || [esi].u.Exception.pExceptionRecord.ExceptionCode ==EXCEPTION_SINGLE_STEP
				invoke cmdSetNextCodeBP,pEvent,@hProcess,@eAddr
			.endif
			mov eax,DBG_CONTINUE
			mov @dwResult,eax
			.break
		.endif
		
		;单步步进
		.if @cmd.mCmd==CMD_STEP_T
			;处理单步、断点异常
			invoke cmdTrace,pEvent,@hProcess,@eAddr
			mov eax,DBG_CONTINUE
			mov @dwResult,eax
			.break
		.endif
		
	.endw
	
	invoke CloseHandle,@hProcess
	mov eax,@dwResult
	ret
dbgEXCEPTION_DEBUG_EVENT endp

dbgEXIT_PROCESS_DEBUG_EVENT proc stdcall,pEvent:ptr DEBUG_EVENT
	jmp main
	szLabel:
		db "EXIT_PROCESS_DEBUG_EVENT",0AH,0
	
	main:
	;invoke printf,offset szLabel

	mov eax,DBG_CONTINUE
	ret
dbgEXIT_PROCESS_DEBUG_EVENT endp

dbgEXIT_THREAD_DEBUG_EVENT proc stdcall,pEvent:ptr DEBUG_EVENT
	jmp main
	szLabel:
		db "EXIT_THREAD_DEBUG_EVENT",0AH,0
	
	main:
	;invoke printf,offset szLabel

	mov eax,DBG_CONTINUE
	ret
dbgEXIT_THREAD_DEBUG_EVENT endp

dbgLOAD_DLL_DEBUG_EVENT proc stdcall,pEvent:ptr DEBUG_EVENT
	jmp main
	szLabel:
		db "LOAD_DLL_DEBUG_EVENT",0AH,0
	
	main:
	;invoke printf,offset szLabel

	mov eax,DBG_CONTINUE
	ret
dbgLOAD_DLL_DEBUG_EVENT endp

dbgUNLOAD_DLL_DEBUG_EVENT proc stdcall,pEvent:ptr DEBUG_EVENT
	jmp main
	szLabel:
		db "UNLOAD_DLL_DEBUG_EVENT",0AH,0
	
	main:
	;invoke printf,offset szLabel

	mov eax,DBG_CONTINUE
	ret
dbgUNLOAD_DLL_DEBUG_EVENT endp

; 调试器主循环
; 处理被调试进程的异常
dbgLoop proc stdcall
	LOCAL @dwStatus:dword
	LOCAL @event:DEBUG_EVENT
	LOCAL @debuged:dword
	
	invoke RtlZeroMemory,addr @event,sizeof DEBUG_EVENT
	
	assume esi:ptr PROCESS_INFORMATION
	assume edi:ptr DEBUG_EVENT
	
	mov esi,offset pInfo
	mov @debuged,1
	
	.while @debuged
		
		invoke WaitForDebugEvent,addr @event,INFINITE
		
		;等待被调试进程事件失败，继续等待。
		.if eax==FALSE
			mov @dwStatus,DBG_CONTINUE
			invoke ContinueDebugEvent,[esi].dwProcessId,[esi].dwThreadId,@dwStatus
			.continue
		.endif
		
		lea edi,@event
		
		;进程被创建
		.if [edi].dwDebugEventCode==CREATE_PROCESS_DEBUG_EVENT
		
			invoke dbgCREATE_PROCESS_DEBUG_EVENT,addr @event
			mov @dwStatus,eax
		
		;线程创建	
		.elseif [edi].dwDebugEventCode==CREATE_THREAD_DEBUG_EVENT
		
			invoke dbgCREATE_THREAD_DEBUG_EVENT,addr @event
			mov @dwStatus,eax
		
		;产生异常	
		.elseif [edi].dwDebugEventCode==EXCEPTION_DEBUG_EVENT
		
			invoke dbgEXCEPTION_DEBUG_EVENT,addr @event
			mov @dwStatus,eax
		
		;退出进程	
		.elseif [edi].dwDebugEventCode==EXIT_PROCESS_DEBUG_EVENT
		
			invoke dbgEXIT_PROCESS_DEBUG_EVENT,addr @event
			mov @debuged,0
			.continue
		
		;退出线程	
		.elseif [edi].dwDebugEventCode==EXIT_THREAD_DEBUG_EVENT
		
			invoke dbgEXIT_THREAD_DEBUG_EVENT,addr @event
			mov @dwStatus,DBG_CONTINUE
		
		;加载DLL	
		.elseif [edi].dwDebugEventCode==LOAD_DLL_DEBUG_EVENT
		
			invoke dbgLOAD_DLL_DEBUG_EVENT,addr @event
			mov @dwStatus,DBG_CONTINUE
		
		;输出调试信息	
		.elseif [edi].dwDebugEventCode==OUTPUT_DEBUG_STRING_EVENT
		
			mov @dwStatus,DBG_CONTINUE
		
		;卸载DLL	
		.elseif [edi].dwDebugEventCode==UNLOAD_DLL_DEBUG_EVENT
		
			invoke dbgUNLOAD_DLL_DEBUG_EVENT,addr @event
			mov @dwStatus,DBG_CONTINUE
			
		.endif
		;mov @dwStatus,DBG_CONTINUE
		invoke ContinueDebugEvent,[edi].dwProcessId,[edi].dwThreadId,@dwStatus
	.endw
	
	ret

dbgLoop endp

   
  start proc
  	LOCAL @sp:STARTUPINFOA
  	

   	invoke getDebugExe
   	.if eax==NULL
   		ret
   	.endif
   	
   	invoke RtlZeroMemory,addr @sp,sizeof STARTUPINFOA
  	
  	assume esi:ptr STARTUPINFOA
  	lea esi,@sp
  	mov [esi].cb,sizeof STARTUPINFOA
  	assume esi:nothing
  
  	invoke RtlZeroMemory,offset pInfo ,sizeof PROCESS_INFORMATION
   	
   	;打开被调试的程序
   	invoke CreateProcess,offset szExePath,NULL,NULL,NULL,FALSE,DEBUG_ONLY_THIS_PROCESS,NULL,NULL,addr @sp,offset pInfo
   	.if eax==FALSE
   		ret
   	.endif
   	
   	;调试器主循环
	invoke dbgLoop
   	
   	xor eax,eax
   	invoke ExitProcess,eax
  start endp
  
  end start