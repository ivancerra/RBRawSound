                               RBRawSound
--------------------------------------------------------------------------------------

Reproductor de sonidos Raw en unsigned 8Bit y 44.1KHz Bare Metal DMA y PWM

Más información del código en los pdf adjuntados.

Compilación desde Raspbian con los comandos:
1. Ensamblado: 
  as audio.s -o audio.o
2. Enlazado: 
  ld -e 0 -Ttext=0x8000 audio.o -o audio.elf
3. Creación del kernel:
  objcopy audio.elf -O binary kernel.img
  
Espero que os guste ;)

--------------------------------------------------------------------------------------
              Copyright - Iván Cerra De Castro 2021 - 
