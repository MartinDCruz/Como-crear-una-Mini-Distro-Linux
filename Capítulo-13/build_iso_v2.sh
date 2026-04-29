#!/bin/bash

echo "--- Iniciando Cadena de Montaje V2 (Modular e Industrial) ---"

# ==========================================
# FASE 1: Preparación y Saneamiento
# ==========================================
echo "[+] Fase 1: Limpiando el entorno..."
rm -rf initramfs isofiles initramfs.cpio.gz micro-linux.iso micro-linux.img

if [ ! -f "busybox" ] || [ ! -f "bzImage" ]; then
    echo "[ERROR] Faltan los archivos maestros 'busybox' o 'bzImage'."
    exit 1
fi

# ==========================================
# FASE 2: Esqueleto y Herramientas
# ==========================================
echo "[+] Fase 2: Creando estructura de directorios..."
mkdir -p initramfs/{bin,sbin,etc,proc,sys,usr/bin,usr/sbin,dev}

echo "[+] Instalando BusyBox..."
cp busybox initramfs/bin/busybox
chmod +x initramfs/bin/busybox

cd initramfs/bin
for prog in $(./busybox --list); do
    ln -s busybox $prog
done
cd ../..

# ==========================================
# FASE 3: El Director de Orquesta (inittab y rcS)
# ==========================================
echo "[+] Fase 3: Configurando init, inittab y ACPI..."

# 1. El capataz (Enlazamos el init real de BusyBox a la raíz)
ln -s bin/busybox initramfs/init

# 2. El Archivo Maestro de Configuración (inittab)
cat > initramfs/etc/inittab << 'EOF'
::sysinit:/etc/init.d/rcS
::askfirst:-/bin/sh
::ctrlaltdel:/bin/reboot
::shutdown:/bin/umount -a -r
::restart:/bin/init
EOF

# 3. El Script de Arranque (rcS)
mkdir -p initramfs/etc/init.d
cat > initramfs/etc/init.d/rcS << 'EOF'
#!/bin/sh
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev

echo "---------------------------------------------"
echo " Micro-Linux: ACPI y Procesos en línea. "
echo "---------------------------------------------"
EOF

# Otorgar permisos de ejecución vitales al script rcS
chmod +x initramfs/etc/init.d/rcS

# ==========================================
# FASE 4: LA FRONTERA DE LA SEGURIDAD
# ==========================================

echo "Implementando barrera de seguridad multiusuario..."

# 1. El Archivo Maestro de Configuración (inittab) actualizado
# Reemplazamos la consola directa por el recepcionista getty
cat > initramfs/etc/inittab << 'EOF'
::sysinit:/etc/init.d/rcS
::respawn:/bin/getty 38400 tty1
::ctrlaltdel:/bin/reboot
::shutdown:/bin/umount -a -r
::restart:/bin/init
EOF

# 2. Forjando las Llaves de Identidad
# El Registro Público (passwd)
cat > initramfs/etc/passwd << 'EOF'
root:x:0:0:Administrador:/root:/bin/sh
usuario:x:1000:1000:Usuario Estandar:/home/usuario:/bin/sh
EOF

# La Bóveda Criptográfica (shadow)
# Al dejar la contraseña vacía (::), exigiremos login pero sin clave por ahora
cat > initramfs/etc/shadow << 'EOF'
root::19500:0:99999:7:::
usuario::19500:0:99999:7:::
EOF

# Sellar la bóveda criptográfica contra lecturas públicas
chmod 600 initramfs/etc/shadow

# El Esqueleto de Permisos (group)
cat > initramfs/etc/group << 'EOF'
root:x:0:
usuario:x:1000:
EOF

# 3. Construyendo los hogares de los habitantes
mkdir -p initramfs/root
chmod 700 initramfs/root
chown -R 0:0 initramfs/root             # El Administrador es el único dueño de la bóveda

mkdir -p initramfs/home/usuario
chown -R 1000:1000 initramfs/home/usuario # El Ciudadano es dueño de su propio hogar

# ==========================================
# FASE 5: CONECTANDO CON EL MUNDO
# ==========================================
echo "[+] Fase 5: Configurando interfaces de red y DHCP..."

# 1. Crear el directorio obligatorio para el ejecutor de DHCP
mkdir -p initramfs/usr/share/udhcpc

# 2. Forjar el script maestro de udhcpc (default.script)
cat > initramfs/usr/share/udhcpc/default.script << 'EOF'
#!/bin/sh
# Este script es invocado por udhcpc recibiendo variables del router ($ip, $subnet, $router, $dns)

case "$1" in
    bound|renew)
        # Aplicar la IP y la máscara a la tarjeta física
        ifconfig $interface $ip netmask $subnet
        
        # Definir la puerta de salida (Gateway)
        if [ -n "$router" ]; then
            route add default gw $router
        fi
        
        # Configurar el traductor DNS (resolv.conf)
        if [ -n "$dns" ]; then
            echo -n > /etc/resolv.conf
            for i in $dns; do
                echo "nameserver $i" >> /etc/resolv.conf
            done
        else
            # Respaldo en caso de que el router no entregue DNS
            echo "nameserver 8.8.8.8" > /etc/resolv.conf
        fi
        ;;
esac
EOF

# Sellar el script con los permisos de ejecución obligatorios
chmod +x initramfs/usr/share/udhcpc/default.script

# 3. Inyectar las órdenes de red al script de arranque (rcS)
cat >> initramfs/etc/init.d/rcS << 'EOF'

# --- Inicialización de Red ---
# Despertar la tarjeta virtual interna
ifconfig lo 127.0.0.1 up
# Despertar la tarjeta de red física
ifconfig eth0 up
# Lanzar el cliente DHCP en segundo plano
udhcpc -i eth0 -b 

echo "---------------------------------------------"
echo " Micro-Linux: Conectividad y Redes en línea. "
echo "---------------------------------------------"
EOF

# ==========================================
# FASE FINAL: Forjando la Imagen Cruda (.img) Universal (BIOS + UEFI)
# ==========================================
echo "[+] Fase Final: Generando Disco Pre-ensamblado (Industrial)..."

# 1. Creación instantánea del bloque lógico
TAMANO_MB=200
echo " -> Reservando bloque de ${TAMANO_MB}MB..."
# Limpiamos rastros anteriores por seguridad
rm -f micro-linux.img 
fallocate -l ${TAMANO_MB}M micro-linux.img

# 2. EL CAMBIO DE PARADIGMA: Particionar el ARCHIVO crudo
echo " -> Trazando tabla GPT universal (vía GUID)..."
sfdisk micro-linux.img > /dev/null 2>&1 << EOF
label: gpt
size=2M, type=21686148-6449-6E6F-744E-656564454649
size=50M, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B
type=0FC63DAF-8483-4772-8E79-3D69D8477DE4
EOF

# 3. Conectar al hipervisor de bloques
echo " -> Conectando unidad virtual al sistema..."
# El Kernel ahora lee las particiones de forma nativa al conectar
LOOPDEV=$(losetup -fP --show micro-linux.img)

# Breve respiro para que el sistema de archivos genere los nodos en /dev/
sleep 2

# 4. Formatear la partición EFI (p2) en FAT32 y la raíz (p3) en EXT4
echo " -> Formateando en FAT32 y EXT4..."
mkfs.vfat -F 32 ${LOOPDEV}p2 > /dev/null 2>&1 || { echo "[ERROR] Fallo formato FAT32"; exit 1; }
mkfs.ext4 ${LOOPDEV}p3 > /dev/null 2>&1 || { echo "[ERROR] Fallo formato EXT4"; exit 1; }

# 5. Extraer Huella Digital (PARTUUID) de la partición raíz (p3)
HUELLA_UNICA=$(blkid -s PARTUUID -o value ${LOOPDEV}p3)
echo " -> Identidad criptografica forjada: $HUELLA_UNICA"

# 6. Volcar la anatomia del sistema
echo " -> Migrando el sistema operativo..."
mkdir -p /mnt/img
mount ${LOOPDEV}p3 /mnt/img || { echo "[ERROR] Fallo montaje raiz"; exit 1; }

cp -a initramfs/* /mnt/img/
mkdir -p /mnt/img/{proc,sys,dev,boot,tmp,var}

mkdir -p /mnt/img/boot/efi
mount ${LOOPDEV}p2 /mnt/img/boot/efi || { echo "[ERROR] Fallo montaje EFI"; exit 1; }

cp bzImage /mnt/img/boot/kernel

# 7. Instalar Motores de Arranque (MBR y UEFI)
echo " -> Instalando Motores de Arranque (MBR y UEFI)..."
grub-install --target=i386-pc --boot-directory=/mnt/img/boot $LOOPDEV > /dev/null 2>&1
grub-install --target=x86_64-efi --efi-directory=/mnt/img/boot/efi --boot-directory=/mnt/img/boot --removable $LOOPDEV > /dev/null 2>&1

# 8. Escribir el mapa de configuración de GRUB
cat > /mnt/img/boot/grub/grub.cfg << EOF
set timeout=5
set default=0

menuentry "Micro-Linux (Asentamiento Definitivo Autonomo)" {
    linux /boot/kernel root=PARTUUID=$HUELLA_UNICA rw rootwait init=/init console=tty0
}
EOF

# 9. Sellar la unidad con seguridad absoluta
echo " -> Sellando imagen y destruyendo el puente logico..."
sync
sleep 1
umount /mnt/img/boot/efi
umount /mnt/img
losetup -d $LOOPDEV
rmdir /mnt/img

echo "--------------------------------------------------------"
echo " ¡PROCESO COMPLETADO EXITOSAMENTE! "
echo " Tu disco duro virtual es: micro-linux.img (${TAMANO_MB}MB)"
echo " Listo para BIOS Legacy y UEFI."
echo "--------------------------------------------------------"
