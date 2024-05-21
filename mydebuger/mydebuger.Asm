.586
.model flat,stdcall
option casemap:none

 include mydebuger.inc



   .data
   	;szMsg db "������Ĳ���",10,0
   	szUnKnowCmd db "�޷�ʶ�������",0ah,0
   	szExePath db 100 dup(0) ;�����Գ����·��
	pInfo PROCESS_INFORMATION<0>
	
	;szPrompt db ">",0
	szFmt db "%s\n",0
	szCmd db "0",0
	gLastCodeAddr dword 0h
	gUnAsmErrMsg db "��������",0ah,0h
	szDMsg db "��鵽CCָ��Ȼָ�",LF,0h
	
	
	gBPAddr dd 0h ; �ϵ��ַ
	gBPOldCode byte 0h ; ԭ����ָ��
	gBPOldCodeAsm db 100 dup(0)
	gBPMode byte 0h
	gBPCC byte 0cch ; int3ָ��
	
	
	gIsBreakSys byte 01h ;�ж���ϵͳ�ϵ� 
	gIsCC byte 0h
	
	gStepPAddr dd 0h ;�����Ķϵ��ַ
	gStepPCode dd 0h ;������ԭ����
	
	gTraceMode byte 0h ;��������ģʽ
	
	gLastOldCode db 100 dup(0h) ;���һ��int 3�ϵ��ԭ���ָ��
	

	gerrMsg db "�����쳣�ĵ�ַ %08X",LF,0h
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
	LOCAL @cmd:Cmd ; ������������
	LOCAL @pException:ptr EXCEPTION_DEBUG_INFO
	LOCAL @ctx:CONTEXT
	LOCAL @hProcess:dword ; ���̾��
	LOCAL @eAddr:dword; ;�����쳣�Ĵ����ַ
	LOCAL @keepCmd:byte;
	LOCAL @dwResult:dword
	
	assume esi:ptr DEBUG_EVENT
	mov esi,pEvent
	mov eax,[esi].u.Exception.pExceptionRecord.ExceptionAddress
	mov @eAddr,eax
	
	;�򿪽���
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
		
		;�յ��쳣��Ϣ�¼����ȴ�ӡ��ǰ�̻߳�����Ϣ
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
		
		
		;�ָ��ϵ�
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
				;��TF=1λ
				invoke threadContext,pEvent,addr @ctx
				or @ctx.regFlag,100h
				invoke saveThreadContext,pEvent,addr @ctx
				.continue
			.endif

			mov eax,DBG_CONTINUE
			mov @dwResult,eax
			.break
		.endif
		
		
		;��ӡ��ǰ�쳣�����ַ�ķ����ָ��
		;invoke showEipAssembly,pEvent
		;invoke unAssembly,pEvent,@eAddr,@eAddr,1

		;��������
		invoke parseCmd,addr @cmd
		
		;δʶ�������
		.if eax==0
			invoke printf,offset szUnKnowCmd
			.continue
		.endif
		
		;��ʾ�Ĵ�����Ϣ
		.if @cmd.mCmd==CMD_READ_REGISTER
			invoke infoRegisters,pEvent
			.continue
		.endif
		
		;����
		.if @cmd.mCmd==CMD_STEP_G
			invoke cmdStep_G,pEvent,@hProcess,@eAddr
			mov eax,DBG_CONTINUE
			mov @dwResult,eax
			.break
		.endif
		
		;����(���������쳣)
		.if @cmd.mCmd==CMD_STEP_KG
			invoke cmdStep_G,pEvent,@hProcess,@eAddr
			mov eax,DBG_EXCEPTION_NOT_HANDLED
			mov @dwResult,eax
			.break
		.endif
		
		;�����
		.if @cmd.mCmd==CMD_UNASSEMBLY
			;û��ָ�������ַ����һ�δ����ַΪ��,ʹ��EIP�ĵ�ַ
			.if @cmd.mAddr<=0
				
				.if gLastCodeAddr<=0
					assume edi:ptr EXCEPTION_DEBUG_INFO
					mov edi,@pException
					mov ecx, [edi].pExceptionRecord.ExceptionAddress
					mov @cmd.mAddr,ecx
					mov gLastCodeAddr,ecx
				.else
					mov ecx,gLastCodeAddr
					mov @cmd.mAddr,ecx ;ʹ���ϴδ����ַ
				.endif
				
			.else
				mov ecx,@cmd.mAddr
				mov gLastCodeAddr,ecx
			.endif
			
			;�����
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
		
		;��ȡ�ڴ�
		.if @cmd.mCmd==CMD_READ_MEMORY
			invoke cmdReadMemory,pEvent,@hProcess,@cmd.mAddr,@cmd.mSize,@cmd.mVal
			.continue
		.endif
		
		;д���ڴ�
		.if @cmd.mCmd==CMD_WRITE_MEMORY
			invoke cmdWriteMemory,pEvent,@hProcess,@cmd.mAddr,addr @cmd.mVal,@cmd.mSize
			.continue
		.endif
		
		
		;���������ϵ� int 3
		.if @cmd.mCmd==CMD_BP
			invoke cmdSetBP,pEvent,@hProcess,@cmd.mAddr
			.continue
		.endif
		
		;��������
		.if @cmd.mCmd==CMD_STEP_P
			;�����������ϵ��쳣
			.if [esi].u.Exception.pExceptionRecord.ExceptionCode ==EXCEPTION_BREAKPOINT || [esi].u.Exception.pExceptionRecord.ExceptionCode ==EXCEPTION_SINGLE_STEP
				invoke cmdSetNextCodeBP,pEvent,@hProcess,@eAddr
			.endif
			mov eax,DBG_CONTINUE
			mov @dwResult,eax
			.break
		.endif
		
		;��������
		.if @cmd.mCmd==CMD_STEP_T
			;�����������ϵ��쳣
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

; ��������ѭ��
; ���������Խ��̵��쳣
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
		
		;�ȴ������Խ����¼�ʧ�ܣ������ȴ���
		.if eax==FALSE
			mov @dwStatus,DBG_CONTINUE
			invoke ContinueDebugEvent,[esi].dwProcessId,[esi].dwThreadId,@dwStatus
			.continue
		.endif
		
		lea edi,@event
		
		;���̱�����
		.if [edi].dwDebugEventCode==CREATE_PROCESS_DEBUG_EVENT
		
			invoke dbgCREATE_PROCESS_DEBUG_EVENT,addr @event
			mov @dwStatus,eax
		
		;�̴߳���	
		.elseif [edi].dwDebugEventCode==CREATE_THREAD_DEBUG_EVENT
		
			invoke dbgCREATE_THREAD_DEBUG_EVENT,addr @event
			mov @dwStatus,eax
		
		;�����쳣	
		.elseif [edi].dwDebugEventCode==EXCEPTION_DEBUG_EVENT
		
			invoke dbgEXCEPTION_DEBUG_EVENT,addr @event
			mov @dwStatus,eax
		
		;�˳�����	
		.elseif [edi].dwDebugEventCode==EXIT_PROCESS_DEBUG_EVENT
		
			invoke dbgEXIT_PROCESS_DEBUG_EVENT,addr @event
			mov @debuged,0
			.continue
		
		;�˳��߳�	
		.elseif [edi].dwDebugEventCode==EXIT_THREAD_DEBUG_EVENT
		
			invoke dbgEXIT_THREAD_DEBUG_EVENT,addr @event
			mov @dwStatus,DBG_CONTINUE
		
		;����DLL	
		.elseif [edi].dwDebugEventCode==LOAD_DLL_DEBUG_EVENT
		
			invoke dbgLOAD_DLL_DEBUG_EVENT,addr @event
			mov @dwStatus,DBG_CONTINUE
		
		;���������Ϣ	
		.elseif [edi].dwDebugEventCode==OUTPUT_DEBUG_STRING_EVENT
		
			mov @dwStatus,DBG_CONTINUE
		
		;ж��DLL	
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
   	
   	;�򿪱����Եĳ���
   	invoke CreateProcess,offset szExePath,NULL,NULL,NULL,FALSE,DEBUG_ONLY_THIS_PROCESS,NULL,NULL,addr @sp,offset pInfo
   	.if eax==FALSE
   		ret
   	.endif
   	
   	;��������ѭ��
	invoke dbgLoop
   	
   	xor eax,eax
   	invoke ExitProcess,eax
  start endp
  
  end start