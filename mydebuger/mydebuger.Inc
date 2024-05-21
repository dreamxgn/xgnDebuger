  include windows.inc
   include user32.inc
   include kernel32.inc
   include msvcrt.inc
   include libc.inc
   
   includelib user32.lib
   includelib kernel32.lib
   includelib msvcrt.lib
   includelib libc.lib
   includelib Asm.lib
   
printf proto C,fmt:dword,arg1:VARARG
strcpy proto C,dest:dword,src:dword
scanf proto C,buf:dword,fmt:dword,arg1:VARARG
gets proto C,buf:dword
strcmp proto C,s1:dword,s2:dword
sscanf proto C,s:dword,fmt:dword,arg:VARARG
strstr proto C,s:dword,subs:dword


disassembly proto C,eip:dword,codeBuff:dword,codeLen:dword,insCode:dword
parseCmd proto stdcall,nCmd:ptr Cmd
infoRegisters proto stdcall,pEvent:ptr DEBUG_EVENT
unAssembly proto stdcall ,pEvent:ptr DEBUG_EVENT,ceip:dword,cAddr:dword,cSize:dword
threadContext proto stdcall,pEvent:ptr DEBUG_EVENT,pCtx:ptr CONTEXT
malloc proto C,nSize:dword
cmdReadMemory proto stdcall ,pEvent:ptr DEBUG_EVENT,hProcess:dword,baseAddr:dword,nSize:dword,nNum:dword
cmdWriteMemory proto  stdcall,pEvent:ptr DEBUG_EVENT,hProcess:dword,baseAddr:dword,buff:dword,nSize:dword
showEipAssembly proto stdcall,pEvent:ptr DEBUG_EVENT
cmdSetBP proto stdcall,pEvent:ptr DEBUG_EVENT,hProcess:dword,bpAddr:dword
cmdSingleStepP proto stdcall,pEvent:ptr DEBUG_EVENT,hProcess:dword,bpAddr:dword
cmdSetNextCodeBP proto stdcall,pEvent:ptr DEBUG_EVENT,hProcess:dword,exceptionAddr:dword

saveThreadContext proto stdcall,pEvent:ptr DEBUG_EVENT,pCtx:ptr CONTEXT
cmdStep_G proto stdcall,pEvent:ptr DEBUG_EVENT,hProcess:dword,exceptionAddr:dword
cmdTrace proto stdcall,pEvent:ptr DEBUG_EVENT,hProcess:dword,exceptionAddr:dword

EXTERNDEF gBPAddr:dword
externdef gBPOldCode:byte,gIsBreakSys:byte,gIsCC:byte,szAsmFmg:byte,gStepPAddr:dword,gStepPCode:dword,gLastOldCode:byte,gBPOldCodeAsm:byte,gBPMode:byte,gTraceMode:byte


;读取所有寄存器的值 r
CMD_READ_REGISTER equ 0h 

;写入某个寄存器 wr reg value
CMD_WRITE_REGISTER equ 01h

;反汇编 u addr 行数
CMD_UNASSEMBLY equ 02h

;汇编 a addr 汇编代码
CMD_ASSEMBLY equ 03h

;读内存 d addr 要读取的字节数   db dw dd
CMD_READ_MEMORY equ 04h
;写内存 e addr 要写入的数据 eb ew ed
CMD_WRITE_MEMORY equ 05h

;单步步进 t
CMD_STEP_T equ 06h 
;单步步过 p
CMD_STEP_P equ 07h
;单步步过 p

;运行(无视所有异常) gs
CMD_STEP_KG equ 0eh
;运行 g
CMD_STEP_G equ 0bh

;设置软件断点 bp addr  ( int 3)
CMD_BP equ 08h ;设置软件断点

;设置硬件断点 ba addr (dr0-7 调试寄存器)
CMD_BA equ 0ch 

;设置内存断点 bu addr (virtualprotect)
CMD_BU equ 0dh

CMD_BL equ 09h ; 查看断点

CMD_BC equ 0ah ;清除断点

;换行符
LF equ 0ah

Cmd struct
	mCmd db 0
	mAddr dd 0
	mSize dd 0
	mVal dd 0
	mBPType db 0 ;断点类型
Cmd ends