/********************************************************************* 
Raspberry Pi Bare Metal Repruductor Wav Raw de 8Bit Mono 44100Hz DMA
**********************************************************************
    · Convertimos Audio Raw que va en Bytes a Words para usar DMA
    · Configuramos el GPIO 12 Como alt0  para PWM (Buzzer)
    · Configuracion del Reloj de GPIO
    · Configuracion de PWM
    · Configuracion de DMA
    · Activamos DMA en bucle, comienza el reproductor
***********************************************************************/

/*********************************************************************
*********************************************************************  
                Z O N A    D E    M A C R O S
********************************************************************* 
**********************************************************************/

.set    PERIPHERAL_BASE, 	0x20000000                              @ Direccion Base de Perifericos
.set    GPIO_BASE,          0x200000                                @ Direccion Base de GPIO
.set    CM_BASE,            0x101000                                @ Direccion Base de Clock Manager
.set    CM_PASSWORD,        0x5A000000                              @ Clock Control Password "5A"
.set    CM_PWMDIV,          0x0A4                                   @ Divisor para PWM Clock Manager
.set    CM_ENAB,            0x10                                    @ Clock Control: Enable Clock Generator
.set    CM_SRC_OSCILLATOR,  0x01                                    @ Clock Control: Clock Source = Oscillator
.set    CM_SRC_PLLCPER,     0x05                                    @ Clock Control: Clock Source = PLLC
.set    CM_SRC_PLLDPER,     0x06                                    @ Clock Control: Clock Source = PLLD
.set    CM_PWMCTL,          0x0A0                                   @ Clock Manager PWM Clock Control
.set    PWM_BASE,           0x20C000                                @ Direcion base de PWM
.set    PWM_RNG1,           0x10                                    @ Rango de PWM Canal 1
.set    PWM_PWEN1,          0x1                                     @ PWM Control: Canal 1 Enable
.set    PWM_USEF1,          0x20                                    @ PWM Control: Canal 1 usar Fifo
.set    PWM_CLRF1,          0x40                                    @ PWM Control: Limpiar Fifo
.set    PWM_CTL,            0x0                                     @ PWM Control
.set    PWM_DMAC,           0x8                                     @ PWM DMA Configuracion
.set    DMA_ENABLE,         0x7FF0                                  @ Global Enable bits par cada canal de DMA
.set    DMA_EN0,            0x1                                     @ DMA Enable: Enable DMA Engine 0
.set    DMA0_BASE,          0x7000                                  @ Direccion registro DMA Canal 0 
.set    DMA_CONBLK_AD,      0x4                                     @ DMA Channel 0..14 Direccion de Bloque de Control
.set    DMA_ACTIVE,         0x1                                     @ DMA Control & Status: Activa DMA
.set    DMA_CS,             0x0                                     @ DMA Channel 0..14 Control & Status
.set    DMA_DEST_DREQ,      0x40                                    @ DMA Transfer Information: Control Destination Writes with DREQ
.set    DMA_PERMAP_5,       0x50000                                 @ DMA Transfer Information: Peripheral Mapping Peripheral Number 5
.set    DMA_SRC_INC,        0x100                                   @ DMA Transfer Information: Source Address Increment
.set    PWM_FIF1,           0x18                                    @ PWM FIFO Input
.set    PWM_ENAB,           0x80000000                              @ PWM DMA Configuration: DMA Enable
.set	C_OKLED,			47                                      @ LED de actividad Raspberyy Pi Zero W
.set    GPIO_GPSET0, 		0x1C                                    @ Para activar (Salida 1) Pines Zona de Memoria
.set    GPIO_GPCLR0, 		0x28                                    @ Para Desactivar (Salida 0) Pines Zona de memoria


/********************************************************************* 
********************************************************************* 
                Z O N A    D E    C O D I G O
********************************************************************* 
**********************************************************************/

/********************************************************************* 
        P U N T O    D E   I N I C I O   D E   E J E C UC I O N
**********************************************************************/

@ Convertimos el fichero Raw de 8 bits a 32 bits con los primeros 3 bytes en blanco para DMA
    ldr     r0, =SNDSample
    ldr     r1, =DMASample
    ldr     r2, =SNDSampleEOF
    bl      sndConvertAudio                                         @ Convertimos el raw para DMA

@ Valores para pin de GPIO
@---------------------------------------------
@ 000 = GPIO Pin X es una entrada
@ 001 = GPIO Pin X es una salida
@ 100 = GPIO Pin X toma función alternativa 0 
@ 101 = GPIO Pin X toma función alternativa 1 
@ 110 = GPIO Pin X toma función alternativa 2 
@ 111 = GPIO Pin X toma función alternativa 3 
@ 011 = GPIO Pin X toma función alternativa 4 
@ 010 = GPIO Pin X toma función alternativa 5
@ ---------------------------------------------

@ Ponemos GPIO 12 a Alternate Function 0 (En binario 100, ver arriba aclaracion) para usar PWM0
    mov     r0, #12                                                 @ Pin GPIO
    mov     r1, #4                                                  @ Alt Fun 0 (4 en decimal, 100 en binario)
    bl      gpSel

@ Ponemos GPIO 47 a 1 como de salida
    mov 	r0, #C_OKLED								            @ Pin OkLed
	mov 	r1, #1
	bl 		gpSel										            @ Lo marcamos como de salida

@ Encendemos el led de Actividad
    mov     r0, #C_OKLED                                            @ Pin OkLed
    mov     r1, #0                                                  @ Se activa en Bajo, el led de Actividad
    bl      gpSet

@ Configuramos Clock para GPIO
    mov     r0, #45                                                 @ El 45 viene de -> 500Mhz / 45 = 11.11 -> 11.11 / 0.0441 = 252 -> Perdemos de 256 a 252 de rango :( para 256 deberia ser 256 * 0.0441 = 11.29
    bl      sndSetClockGPIO                                         @ Configuramos el reloj para GPIO

@ Configuramos PWM
    ldr     r0, =252                                                @ El 252 viene de -> 500Mhz / 45 = 11.11 -> 11.11 / 0.0441 = 252 -> Perdemos de 256 a 252 de rango :( para 256 deberia ser 256 * 0.0441 = 11.29
    bl      sndSetPWM                                               @ Configuramos PWM

@ Configuramos DMA Canal 1 
    mov     r0, #1                                                  @ Configuramos DMA, el canal 1
    bl      sndSetDMA   
 
Loop$:
    b       Loop$                                                   @ Hasta el Infinito y mas alla (Como lo hacemos por DMA podemos quedarnos en bucle sin fin)
/* Fin Punto de inicio de jecucion */

/********************************************************************* 
               F U N C I O N E S   D E   A P O Y O
**********************************************************************/
/***************************************************************/
/* gpSel:                                                      */
/***************************************************************/
/* Funcion que marca un pin con funcionalidad                  */
/*   Parametros:                                               */
/*    - r0, pin de 0 a 54                                      */
/*    - r1, funcionalidad de 0 a 7, entrada 0, salida 1        */
/***************************************************************/
.global gpSel
gpSel:
	cmp 	r0, #53                                                 @ Comprobamos los parametros de entrada
	cmpls 	r1, #7
	bxhi 	lr

	push 	{r2, r3, lr}							                @ Salvaguardamos los registros que no usemos como parametros, ni resultado pero usemos dentro

    ldr     r2, =PERIPHERAL_BASE + GPIO_BASE                        @ Puntero a zona de gestion de GPIO

gpSLoop$:
    cmp 	r0, #9									                @ Calculamos que registro de GPIO Sel le corresponde, hay 10 por registro de 0 a 9 
	subhi 	r0, #10
	addhi 	r2, #4
	bhi 	gpSLoop$

	add 	r0, r0, lsl #1							                @ Multiplicacion por 3, se desplaza uno a la izquierda y se suma el mismo r2 = 3 * r2 -> r2 = 2 * r2 + r2
	lsl 	r1, r0

	mov 	r3, #7									                @ r3 = 111 en binario para la mascara
	lsl 	r3, r0									                @ r3 = 11100..00 donde 111 se situa en la posicion de su pin
	mvn 	r3, r3									                @ r3 = 11..1100011..11 invertimos la mascara
	ldr 	r0, [r2]								                @ r2 = seleccion actual de pines
	and 	r0, r3									                @ r2 selecciona actual con nuestro pin a 000
	orr 	r1, r0									                @ r1 seleccion actual con nuestra funcion establecida
	str 	r1, [r2]								                @ Lo guardamos

	pop		{r2, r3, lr}
	bx 		lr
/* Fin Funcion gpSel */

/***************************************************************/
/* gpSet:                                                      */
/***************************************************************/
/* Funcion que marca un pin con la salida indicada             */
/*   Parametros:                                               */
/*    - r0, pin de 0 a 54                                      */
/*    - r1, valor del pin                                      */
/***************************************************************/
.global gpSet
gpSet:	
  	cmp 		r0, #53									            @ Comprobamos que el pin sea de 0 a 53
	bxhi 		lr

	push 		{r2, r3, lr}							            @ Salvaguardamos los registros que no usemos como parametros, ni resultado pero usemos dentro
	
    ldr         r2, =PERIPHERAL_BASE + GPIO_BASE                    @ Puntero a zona de gestion de GPIO
    
	lsr 		r3, r0, #5								            @ Calculamos el registro al que va, dividiendo por 32
	lsl 		r3, #2									            @ Multiplicamos por 4
	add 		r2, r3									            @ El desplazamiento sobre el base SET o CLEAR

	and 		r0, #31									            @ Al hacer un And nos quedamos con el resto de dividir por 32
	mov 		r3, #1
	lsl 		r3, r0									            @ Calculamos el pin, desplazandolo y poniendolo en su lugar
	
	teq 		r1, #0									            @ Comprobamos si es SET o CLEAR
	streq 		r3, [r2, #GPIO_GPCLR0]					            @ Es Clear
	strne 		r3, [r2, #GPIO_GPSET0]					            @ Es Set
	
	pop 		{r2, r3, lr}
	bx			lr
/* Fin Funcion gpSet */

/***************************************************************/
/* sndConvertAudio:                                            */
/***************************************************************/
/* Funcion que convierte un Audio raw en 32 bit                */
/* Para su uso con DMA                                         */
/*   Parametros:                                               */
/*    - r0, direccion del wav raw                              */
/*    - r1, direccion de la conversion para DMA                */
/*    - r2, direccion que marca el final del raw               */
/***************************************************************/
.global sndConvertAudio
sndConvertAudio: 

sndCALoop$:
    push    {r3}
    ldrb    r3, [r0], #1
    str     r3, [r1], #4
    cmp     r0, r2
    bne     sndCALoop$

    pop     {r3}
	bx 		lr
/* Fin Funcion sndConvertAudio */

/***************************************************************/
/* sndSetClockGPIO:                                            */
/***************************************************************/
/* Funcion que configura el reloj para GPIO                    */
/*   Parametros:                                               */
/*    - r0, Divisor Entero del Clock de 500 MHz                */
/***************************************************************/
.global sndSetClockGPIO
sndSetClockGPIO: 
    push    {r1-r2}

    ldr     r1, =PERIPHERAL_BASE + CM_BASE
    ldr     r2, =CM_PASSWORD                                        @ Bits 0..11 PArte decimal del Divisor = 0, Bits 12..23 Parte entera del Divisor 500 / r0
    lsl     r0, #12
    add     r2, r0
    str     r2, [r1, #CM_PWMDIV]

    ldr     r2, =CM_PASSWORD + CM_ENAB + CM_SRC_PLLDPER             @ Usamos fuente de reloj -> 500MHz Clock PLLD
    str     r2, [r1, #CM_PWMCTL]

    pop     {r1-r2}
	bx 		lr
/* Fin Funcion sndSetClockGPIO */

/***************************************************************/
/* sndSetPWM:                                                  */
/***************************************************************/
/* Funcion que configura PWM                                   */
/*   Parametros:                                               */
/*    - r0, Rango de Duty Cycle                                */
/***************************************************************/
.global sndSetPWM
sndSetPWM: 
    push    {r1}

    ldr     r1, =PERIPHERAL_BASE + PWM_BASE
    str     r0, [r1, #PWM_RNG1]                                     @ Guardamos el Rango del Duty Cycle

    ldr     r0, =PWM_USEF1 + PWM_PWEN1 + PWM_CLRF1                  @ Activamos el PWM1
    str     r0, [r1, #PWM_CTL]

    ldr     r0, =PWM_ENAB + 0x0001                                  @ Bits 0..7 DMA Umbral para DREQ Signal = 1, Bits 8..15 DMA Umbral para PANIC Signal = 0
    str     r0, [r1, #PWM_DMAC]                                     @ PWM DMA Enable

    pop     {r1}
	bx 		lr
/* Fin Funcion sndSetPWM */

/***************************************************************/
/* sndSetDMA:                                                  */
/***************************************************************/
/* Funcion que configura DMA                                   */
/*   Parametros:                                               */
/*    - r0, DMA Channel                                        */
/***************************************************************/
.global sndSetDMA
sndSetDMA: 
    push    {r1-r2}

    ldr     r1, =PERIPHERAL_BASE + DMA_ENABLE                       @ Configuramos DMA Canal
    mov     r2, #1                                                  @ Valor para DMA canal enable
    lsl     r2, r0 
    str     r2, [r1]

    ldr     r1, =PERIPHERAL_BASE                                    @ Configuramos Control Block Data Address para DMA Canal
    mov     r2, r0, lsl #8                                          @ Base para Canal DMA
    add     r2, r2, #0x7000
    add     r1, r2                                                  @ Le sumamos la base de Canal DMA

    ldr     r2, =DMAControlBlockAudio                               @ Le ponemos la direccion del bloque de control
    str     r2, [r1, #DMA_CONBLK_AD]

    mov     r2, #DMA_ACTIVE
    str     r2, [r1, #DMA_CS]                                       @ Activamos DMA

    pop     {r1-r2}
	bx 		lr
/* Fin Funcion sndSetDMA */


/*********************************************************************
*********************************************************************  
                Z O N A    D E    D A T O S
********************************************************************* 
**********************************************************************/

.section .data

.align 8
DMAControlBlockAudio:                                               @ Estructura de Bloque de Control
  .word     DMA_DEST_DREQ + DMA_PERMAP_5 + DMA_SRC_INC              @ DMA Información de transferencia
  .word     DMASample                                               @ DMA Direccion origen
  .word     0x7E000000 + PWM_BASE + PWM_FIF1                        @ DMA Direccion destino
  .word     (SNDSampleEOF - SNDSample) * 4                          @ DMA Tamaño del bloque a transferir
  .word     0                                                       @ DMA 2D Mode Stride
  .word     DMAControlBlockAudio                                    @ DMA Direccion del proximo bloque de control, este mismo bloque y asi hago Loop

.align 4
SNDSample:                                                          @ 8bit 44100Hz Unsigned 8 Bit Mono Audio Raw
  .incbin  "leave.bin"
SNDSampleEOF:                                                       @ Marca de fin de fichero

.align 4
DMASample:                                                          @ Espacio de memoria donde pondremos el Audio Raw para DMA hay que poner el byte en Words (32 bits)
