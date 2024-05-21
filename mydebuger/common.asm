.586
.model flat,stdcall
option casemap:none

include mydebuger.inc

public parseCmd,infoRegisters,unAssembly,saveThreadContext,szAsmFmg

.data
	szPrompt db ">",0
	szMsg db "��ʾ�߳�������",LF,0
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
	
	szBP_Error_MSG db "�޷��ڸõ�ַ���öϵ� %08X",LF,0h
	
	szFindCall db "call",0h
	szDebugMsg db "ϵͳ�ϵ㱻������",LF,0h
.code

;��������
parseCmd proc stdcall uses esi,nCmd:ptr Cmd
	LOCAL @szBuff[100] ;ָ�����
	assume esi:ptr Cmd
	mov esi,nCmd
	
	invoke RtlZeroMemory,nCmd,sizeof Cmd
	
	invoke printf,offset szPrompt
	invoke gets,addr @szBuff
	
	lea eax,@szBuff[0]
	
	.if [esi].mSize<=0
		mov [esi].mSize,08h
	.endif
	
	; ��ȡ���мĴ�����ֵ r
	.if byte ptr [eax]=='r'
		mov [esi].mCmd,CMD_READ_REGISTER
		mov eax,Cmd
		ret
	.endif
	
	; CMD_STEP_G ����ָ��(���������쳣)
	.if byte ptr [eax]== 'g' && byte ptr [eax+1]== 's'
		mov [esi].mCmd,CMD_STEP_KG
		mov eax,Cmd
		ret
	.endif
	
	; CMD_STEP_G ����ָ��
	.if byte ptr [eax]== 'g'
		mov [esi].mCmd,CMD_STEP_G
		mov eax,Cmd
		ret
	.endif
	
	;���� u ����
	.if byte ptr [eax]== 'u'
		
		invoke sscanf,addr @szBuff,offset szCmd_U_Fmt,addr [esi].mAddr,addr [esi].mSize
		mov [esi].mCmd,CMD_UNASSEMBLY
		mov eax,Cmd
		ret
		
	.endif
	
	;����d ����
	.if byte ptr [eax]=='d'
		
		;��ȡһ���ֽ� db addr
		.if byte ptr [eax+1]=='b'
			invoke sscanf,addr @szBuff,offset szCmd_DB_Fmt,addr [esi].mAddr,addr [esi].mVal
			mov [esi].mCmd,CMD_READ_MEMORY
			mov [esi].mSize,01h
			mov eax,Cmd
			ret
		.endif
		
		;��ȡ�����ֽ�
		.if byte ptr [eax+1]=='w'
			invoke sscanf,addr @szBuff,offset szCmd_DW_Fmt,addr [esi].mAddr,addr [esi].mVal
			mov [esi].mCmd,CMD_READ_MEMORY
			mov [esi].mSize,02h
			mov eax,Cmd
			ret
		.endif
		
		;��ȡ4���ֽ�
		.if byte ptr [eax+1]=='d'
			invoke sscanf,addr @szBuff,offset szCmd_DD_Fmt,addr [esi].mAddr,addr [esi].mVal
			mov [esi].mCmd,CMD_READ_MEMORY
			mov [esi].mSize,04h
			mov eax,Cmd
			ret
		.endif
		ret
	.endif
	
	;����e ����
	.if byte ptr [eax]=='e'
		
		;д��һ���ֽ� eb addr ����
		.if byte ptr [eax+1]=='b'
			invoke sscanf,addr @szBuff,offset szCmd_EB_Fmt,addr [esi].mAddr,addr [esi].mVal
			mov [esi].mCmd,CMD_WRITE_MEMORY
			mov [esi].mSize,01h
			mov eax,Cmd
			ret
		.endif
		
		;��ȡ�����ֽ�
		.if byte ptr [eax+1]=='w'
			invoke sscanf,addr @szBuff,offset szCmd_EW_Fmt,addr [esi].mAddr,addr [esi].mVal
			mov [esi].mCmd,CMD_WRITE_MEMORY
			mov [esi].mSize,02h
			mov eax,Cmd
			ret
		.endif
		
		;��ȡ4���ֽ�
		.if byte ptr [eax+1]=='d'
			invoke sscanf,addr @szBuff,offset szCmd_ED_Fmt,addr [esi].mAddr,addr [esi].mVal
			mov [esi].mCmd,CMD_WRITE_MEMORY
			mov [esi].mSize,04h
			mov eax,Cmd
			ret
		.endif
		ret
	.endif
	
	;���� bp ����
	.if byte ptr [eax]=='b' && byte ptr [eax+1]=='p'
		invoke sscanf,addr @szBuff,offset szCmd_BP_Fmt,addr [esi].mAddr
		mov [esi].mCmd,CMD_BP
		mov eax,Cmd
		ret
	.endif
	
	;��������
	.if byte ptr [eax]=='p'
		mov [esi].mCmd,CMD_STEP_P
		mov eax,Cmd
		ret
	.endif
	
	;��������
	.if byte ptr [eax]=='t'
		mov [esi].mCmd,CMD_STEP_T
		mov eax,Cmd
		ret
	.endif
	xor eax,eax
	ret
parseCmd endp


;��ʾ��ǰ�ļĴ�����Ϣ
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

;��������
unAssembly proc stdcall uses esi ,pEvent:ptr DEBUG_EVENT,ceip:dword,cAddr:dword,cSize:dword
	LOCAL @hProcess:dword ;���̾��
	LOCAL @buff[MAXBYTE] ;��ȡ�Ĵ����ŵĻ�����,ÿ�ζ�ȡ FF �ֽڡ�
	LOCAL @dwReadLen:dword ; ʵ�ʶ�ȡ����ĳ���
	LOCAL @ins[MAXBYTE] ; �������ָ���ַ���
	LOCAL @dwAsmLen:dword ;�ѷ�����ָ��ȣ���λ: �ֽ�
	
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
	
	;��ȡָ����ַ���Ĵ����ֽ�
	invoke ReadProcessMemory,@hProcess,ceip,addr @buff,MAXBYTE,addr @dwReadLen
	.if eax==0
		invoke CloseHandle,@hProcess ;ReadProcessMemory ʧ�ܣ��رս��̾����
		xor eax,eax
		ret
	.endif
	
	;��ʾ cSize �з����ָ��
	.while cSize>0
		
		;��ʼ�����ڷ����ָ���ַ����Ļ�����
		invoke RtlZeroMemory,addr @ins,MAXBYTE
		
		;�ƶ�������@buff ����һ��ָ���λ�� base+�ѷ�����ָ���
		lea ecx,@buff[0]
		add ecx,@dwAsmLen
		
		invoke disassembly,ceip,ecx,@dwReadLen,addr @ins
		
		.if eax<=0
			invoke CloseHandle,@hProcess
			mov eax,@dwAsmLen
			ret
		.endif
		
		add @dwAsmLen,eax ;�����ѷ�����ֽ�
		add ceip,eax ;����EIP
		
		invoke printf,offset szAsmFmg,addr @ins
		dec cSize
	.endw
	
	invoke CloseHandle,@hProcess
	mov eax,@dwAsmLen
	ret
unAssembly endp


;��ʾ��ǰ�߳�EIP��ַ�ķ����
showEipAssembly proc stdcall,pEvent:ptr DEBUG_EVENT
	LOCAL @ctx:CONTEXT
	
	invoke threadContext,pEvent,addr @ctx
	.if eax==0
		ret
	.endif
	
	invoke unAssembly,pEvent,@ctx.regEip,@ctx.regEip,1

	ret
showEipAssembly endp


;��ȡ�߳�������
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

;�����߳�������
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

;��ȡ�����ڴ�
; baseAddr �ڴ��ַ
; nSize ��ȡ���ֽڿ��С
; nNum ��ȡ���ٿ�
; hProcess ���̾��
; pEvent �¼��ṹ��
cmdReadMemory proc stdcall uses esi ecx,pEvent:ptr DEBUG_EVENT,hProcess:dword,baseAddr:dword,nSize:dword,nNum:dword
	LOCAL @dwReadLen:dword  ;ʵ�ʶ�ȡ���ֽ���
	LOCAL @dwLineNum:dword ;����ʾ�ֽ�����
	LOCAL @readLen:dword ; ��Ҫ��ȡ���ֽ����� nSize*nNum
	LOCAL @buff:dword ;������
	
	
	mov @dwLineNum,0h
	
	mov ecx,nSize
	mov eax,nNum
	mul ecx
	mov @readLen,eax
	
	;�����ڴ�
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
		
		;ÿ����ʾ16���ֽ�����
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

;д���ڴ�
cmdWriteMemory proc stdcall,pEvent:ptr DEBUG_EVENT,hProcess:dword,baseAddr:dword,buff:dword,nSize:dword
	LOCAL @oldProtect:dword
	
	mov @oldProtect,0
	
	invoke VirtualProtectEx,hProcess,baseAddr,nSize,PAGE_EXECUTE_READWRITE,addr @oldProtect
	.if eax==NULL
		xor eax,eax
		ret
	.endif

	invoke WriteProcessMemory,hProcess,baseAddr,buff,nSize,NULL
	
	;��ԭ�ڴ汣������
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
	
	;��ȡԭ����ָ��
	invoke ReadProcessMemory,hProcess,bpAddr,offset gBPOldCode,1,addr @dwReadLen
	.if eax==NULL
		ret
	.endif
	

	invoke ReadProcessMemory,hProcess,bpAddr,addr @codeBuff,MAXBYTE,addr @dwReadLen
	.if eax==0
		invoke CloseHandle,hProcess ;ReadProcessMemory ʧ�ܣ��رս��̾����
		mov eax,DBG_EXCEPTION_NOT_HANDLED
		ret
	.endif
	
	;����ԭ���Ļ��ָ��
	invoke disassembly,bpAddr,addr @codeBuff,@dwReadLen,offset gBPOldCodeAsm
	
	invoke cmdWriteMemory,pEvent,hProcess,bpAddr,addr @cc,1
	ret

cmdSetBP endp


;��������
;�ָ��ϵ㴦ԭ��ָ��
;����Ƿ���call ָ������call ָ��Ͳ�������TF=1����Ҫ������ָ�����int3��
cmdSingleStepP proc stdcall,pEvent:ptr DEBUG_EVENT,hProcess:dword,bpAddr:dword
	LOCAL @codeBuff[MAXBYTE] ;��Ҫ������ָ������
	LOCAL @dwReadLen:dword ;��ȡ��ָ���
	LOCAL @ins[MAXBYTE] ;�������ָ������
	LOCAL @insLen:dword ;�������ָ���
	LOCAL @ctx:CONTEXT ;�߳�������
	LOCAL @nextCodeAddr:dword ;��һ��ָ���ַ
	
	
	
	;ֻ�������˶ϵ���ָܻ�
	.if gBPAddr==0
		xor eax,eax
		ret
	.endif
	
	invoke RtlZeroMemory,addr @ins,MAXBYTE
	invoke RtlZeroMemory,addr @codeBuff,MAXBYTE
	invoke RtlZeroMemory,addr @ctx,sizeof CONTEXT
	
	
	;�ָ�ԭ��ָ��
	;invoke cmdWriteMemory,pEvent,hProcess,gBPAddr,offset gOldCode,1
	
	;��ȡԭ����
	invoke ReadProcessMemory,hProcess,gBPAddr,addr @codeBuff,MAXBYTE,addr @dwReadLen
	.if eax==0
		invoke CloseHandle,hProcess ;ReadProcessMemory ʧ�ܣ��رս��̾����
		xor eax,eax
		ret
	.endif
	
	
	;�ж��Ƿ���call ָ��
	invoke disassembly,gBPAddr,addr @codeBuff,@dwReadLen,addr @ins
	mov @insLen,eax
	
	.if @insLen==NULL
		xor eax,eax
		ret
	.endif
	
	;�ж��Ƿ���Callָ��
	invoke strstr,addr @ins,offset szFindCall
	
	.if eax==NULL
		;����call ָ��,ֻ��Ҫ���õ�����ʶ TF=1
		invoke threadContext,pEvent,addr @ctx
		or @ctx.regFlag,100h
		invoke saveThreadContext,pEvent,addr @ctx
		ret
	.else
		;��call ָ���Ҫ����һ��ָ���дΪint 3
		mov eax,@insLen
		add eax,gBPAddr
		mov @nextCodeAddr,eax
		
		invoke cmdSetBP,pEvent,hProcess,@nextCodeAddr
		
		ret
	.endif
cmdSingleStepP endp

cmdStep_G proc stdcall,pEvent:ptr DEBUG_EVENT,hProcess:dword,exceptionAddr:dword
	LOCAL @codeBuff[MAXBYTE] ;��Ҫ������ָ������
	LOCAL @dwReadLen:dword ;��ȡ��ָ���
	LOCAL @ins[MAXBYTE] ;�������ָ������
	LOCAL @insLen:dword ;�������ָ���
	LOCAL @ctx:CONTEXT ;�߳�������
	LOCAL @nextCodeAddr:dword ;��һ��ָ���ַ
	LOCAL @currCodeAddr:dword
	LOCAL @cc:byte
	
	mov @cc,0cch
	
	invoke RtlZeroMemory,addr @ins,MAXBYTE
	invoke RtlZeroMemory,addr @codeBuff,MAXBYTE
	invoke RtlZeroMemory,addr @ctx,sizeof CONTEXT
	
	mov eax,exceptionAddr
	mov @currCodeAddr,eax
	
	
	;�ָ�ָ��
	;ϵͳ�ϵ�
	.if gIsBreakSys==TRUE
		mov gIsBreakSys,FALSE
		invoke printf, offset szDebugMsg
		;ϵͳ�ϵ㱻����
		;��ȡԭ����
		;add @currCodeAddr,1
		ret
	.endif
	
	;�ָ�����,ֻ�е�����BP�ϵ㴥������Ҫ�ָ�����
	mov eax,exceptionAddr
	
	;�ָ�����
	.if gStepPAddr>0 && gStepPAddr==eax
		;�ָ�ԭ��ָ��
		invoke cmdWriteMemory,pEvent,hProcess,gStepPAddr,offset gStepPCode,1
		.if eax==NULL
			mov eax,DBG_EXCEPTION_NOT_HANDLED
			ret
		.endif
		
		;��������EIP
		invoke threadContext,pEvent,addr @ctx
		mov eax,gStepPAddr
		mov @ctx.regEip,eax
		invoke saveThreadContext,pEvent,addr @ctx
		mov eax,exceptionAddr
		mov @currCodeAddr,eax
		
		
	
	;�ָ��ϵ�	
	.elseif gBPAddr>0 && gBPAddr==eax
		;�ָ�ԭ��ָ��
		invoke cmdWriteMemory,pEvent,hProcess,gBPAddr,offset gBPOldCode,1
		.if eax==NULL
			mov eax,DBG_EXCEPTION_NOT_HANDLED
			ret
		.endif
		
		;��������EIP
		invoke threadContext,pEvent,addr @ctx
		mov eax,gBPAddr
		mov @ctx.regEip,eax
		or @ctx.regFlag,0100h ;��TF=1
		invoke saveThreadContext,pEvent,addr @ctx
		mov eax,exceptionAddr
		mov @currCodeAddr,eax
		mov gBPMode,TRUE
		;��Ҫ����һ����ʶ����TF=1,���´ε����쳣ʱ��ԭ�ϵ㡣
	.endif
	ret
cmdStep_G endp

; ���õ��������ϵ�
; exceptionAddr �����쳣�ĵ�ַ
;
;
cmdSetNextCodeBP proc stdcall,pEvent:ptr DEBUG_EVENT,hProcess:dword,exceptionAddr:dword
	LOCAL @codeBuff[MAXBYTE] ;��Ҫ������ָ������
	LOCAL @dwReadLen:dword ;��ȡ��ָ���
	LOCAL @ins[MAXBYTE] ;�������ָ������
	LOCAL @insLen:dword ;�������ָ���
	LOCAL @ctx:CONTEXT ;�߳�������
	LOCAL @nextCodeAddr:dword ;��һ��ָ���ַ
	LOCAL @currCodeAddr:dword
	LOCAL @cc:byte
	
	mov @cc,0cch
	
	invoke RtlZeroMemory,addr @ins,MAXBYTE
	invoke RtlZeroMemory,addr @codeBuff,MAXBYTE
	invoke RtlZeroMemory,addr @ctx,sizeof CONTEXT
	
	mov eax,exceptionAddr
	mov @currCodeAddr,eax
	
	
	;�ָ�ָ��
	
	;ϵͳ�ϵ�
	.if gIsBreakSys==TRUE
		mov gIsBreakSys,FALSE
		invoke printf, offset szDebugMsg
		;ϵͳ�ϵ㱻����
		;��ȡԭ����
		add @currCodeAddr,1
	.endif
	
	;�ָ�����,ֻ�е�����BP�ϵ㴥������Ҫ�ָ�����
	mov eax,exceptionAddr
	
	;�ָ�����
	.if gStepPAddr>0 && gStepPAddr==eax
		;�ָ�ԭ��ָ��
		invoke cmdWriteMemory,pEvent,hProcess,gStepPAddr,offset gStepPCode,1
		.if eax==NULL
			mov eax,DBG_EXCEPTION_NOT_HANDLED
			ret
		.endif
		
		;��������EIP
		invoke threadContext,pEvent,addr @ctx
		mov eax,gStepPAddr
		mov @ctx.regEip,eax
		invoke saveThreadContext,pEvent,addr @ctx
		mov eax,exceptionAddr
		mov @currCodeAddr,eax
		
		
	
	;�ָ��ϵ�	
	.elseif gBPAddr>0 && gBPAddr==eax
		;�ָ�ԭ��ָ��
		invoke cmdWriteMemory,pEvent,hProcess,gBPAddr,offset gBPOldCode,1
		.if eax==NULL
			mov eax,DBG_EXCEPTION_NOT_HANDLED
			ret
		.endif
		
		;��������EIP
		invoke threadContext,pEvent,addr @ctx
		mov eax,gBPAddr
		mov @ctx.regEip,eax
		or @ctx.regFlag,0100h ;��TF=1
		invoke saveThreadContext,pEvent,addr @ctx
		mov eax,exceptionAddr
		mov @currCodeAddr,eax
		mov gBPMode,TRUE
		;��Ҫ����һ����ʶ����TF=1,���´ε����쳣ʱ��ԭ�ϵ㡣
	.endif
	
	

	invoke ReadProcessMemory,hProcess,@currCodeAddr,addr @codeBuff,MAXBYTE,addr @dwReadLen
	.if eax==0
		invoke CloseHandle,hProcess ;ReadProcessMemory ʧ�ܣ��رս��̾����
		mov eax,DBG_EXCEPTION_NOT_HANDLED
		ret
	.endif

	;��ǰָ���Ƿ���call ָ��
	invoke disassembly,@currCodeAddr,addr @codeBuff,@dwReadLen,addr @ins
	mov @insLen,eax
	
	.if @insLen==NULL
		mov eax,DBG_EXCEPTION_NOT_HANDLED
		ret
	.endif
	
	;invoke printf,addr @ins
	
	;�ж��Ƿ���Callָ��
	invoke strstr,addr @ins,offset szFindCall
	
	.if eax==NULL
		;����call ָ��,ֻ��Ҫ���õ�����ʶ TF=1
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
		;��call ָ���Ҫ����һ��ָ���дΪint 3
		mov eax,@insLen
		add eax,@currCodeAddr
		mov @nextCodeAddr,eax
		mov gStepPAddr,eax
		
		;��ȡԭ����ָ��
		invoke ReadProcessMemory,hProcess,@nextCodeAddr,offset gStepPCode,1,addr @dwReadLen
		.if eax==NULL
			mov eax,DBG_EXCEPTION_NOT_HANDLED
			ret
		.endif
		
		invoke ReadProcessMemory,hProcess,@nextCodeAddr,addr @codeBuff,MAXBYTE,addr @dwReadLen
		.if eax==0
			invoke CloseHandle,hProcess ;ReadProcessMemory ʧ�ܣ��رս��̾����
			mov eax,DBG_EXCEPTION_NOT_HANDLED
			ret
		.endif
		
		;����ԭ���Ļ��ָ��
		invoke disassembly,gStepPAddr,addr @codeBuff,@dwReadLen,offset gLastOldCode
		
		invoke cmdWriteMemory,pEvent,hProcess,@nextCodeAddr,addr @cc,1
		
		mov eax,DBG_CONTINUE
		ret
	.endif
	
cmdSetNextCodeBP endp


;��������
cmdTrace proc stdcall,pEvent:ptr DEBUG_EVENT,hProcess:dword,exceptionAddr:dword
	LOCAL @ctx:CONTEXT ;�߳�������
	LOCAL @currCodeAddr:dword
	
		;�ָ�����,ֻ�е�����BP�ϵ㴥������Ҫ�ָ�����
	mov eax,exceptionAddr
	
	;�ָ�����
	.if gStepPAddr>0 && gStepPAddr==eax
		;�ָ�ԭ��ָ��
		invoke cmdWriteMemory,pEvent,hProcess,gStepPAddr,offset gStepPCode,1
		.if eax==NULL
			mov eax,DBG_EXCEPTION_NOT_HANDLED
			ret
		.endif
		
		;��������EIP
		invoke threadContext,pEvent,addr @ctx
		mov eax,gStepPAddr
		mov @ctx.regEip,eax
		invoke saveThreadContext,pEvent,addr @ctx
		mov eax,exceptionAddr
		mov @currCodeAddr,eax
		
		
	
	;�ָ��ϵ�	
	.elseif gBPAddr>0 && gBPAddr==eax
		;�ָ�ԭ��ָ��
		invoke cmdWriteMemory,pEvent,hProcess,gBPAddr,offset gBPOldCode,1
		.if eax==NULL
			mov eax,DBG_EXCEPTION_NOT_HANDLED
			ret
		.endif
		
		;��������EIP
		invoke threadContext,pEvent,addr @ctx
		mov eax,gBPAddr
		mov @ctx.regEip,eax
		or @ctx.regFlag,0100h ;��TF=1
		invoke saveThreadContext,pEvent,addr @ctx
		mov eax,exceptionAddr
		mov @currCodeAddr,eax
		mov gBPMode,TRUE
		;��Ҫ����һ����ʶ����TF=1,���´ε����쳣ʱ��ԭ�ϵ㡣
	.endif
	
	
	
	;��TF=1λ
	invoke threadContext,pEvent,addr @ctx
	or @ctx.regFlag,100h
	invoke saveThreadContext,pEvent,addr @ctx
	mov gTraceMode,TRUE
	ret
cmdTrace endp

end