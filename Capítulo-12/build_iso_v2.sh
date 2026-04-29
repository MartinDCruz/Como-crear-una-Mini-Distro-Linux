#!/bin/bash

echo "--- Iniciando Cadena de Montaje V2 (Modular) ---"

# ==========================================
# FASE 1: Preparación y Saneamiento
# ==========================================
echo "[+] Fase 1: Limpiando el entorno..."
rm -rf initramfs isofiles initramfs.cpio.gz micro-linux.iso

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
# FASE 6: HERRAMIENTAS DE ASENTAMIENTO
# ==========================================
echo "[+] Fase 6: Inyectando el instalador del sistema..."

cat > initramfs/usr/sbin/instalar-sistema << 'EOF'
#!/bin/sh
echo "--------------------------------------------------------"
echo " INICIANDO ASENTAMIENTO DEL SISTEMA EN /dev/sda"
echo "--------------------------------------------------------"

echo "[+] Fase 1: Forjando la Tabla de Particiones..."
echo -e "n\np\n1\n\n\nw" | fdisk /dev/sda > /dev/null 2>&1
sleep 1

echo "[+] Fase 2: Formateando en EXT2 (Estandar BusyBox)..."
mkfs.ext2 /dev/sda1 > /dev/null 2>&1

echo "[+] Fase 3: Migrando la anatomia del sistema..."
mkdir -p /mnt/disco
mount /dev/sda1 /mnt/disco

cp -a /bin /sbin /etc /usr /root /home /init /mnt/disco/
mkdir -p /mnt/disco/proc /mnt/disco/sys /mnt/disco/dev /mnt/disco/boot

umount /mnt/disco

echo "--------------------------------------------------------"
echo " ASENTAMIENTO COMPLETADO CON EXITO."
echo " Escribe 'reboot' y elige la opcion de Disco Duro en GRUB."
echo "--------------------------------------------------------"
EOF

# Sellar la herramienta con permisos de ejecución
chmod +x initramfs/usr/sbin/instalar-sistema

# ==========================================
# FASE FINAL: Empaquetado y Fundición
# ==========================================
echo "[+] Fase Final: Empaquetando y generando ISO..."
cd initramfs
find . -print0 | cpio --null -ov --format=newc | gzip -9 > ../initramfs.cpio.gz
cd ..

mkdir -p isofiles/boot/grub
cp bzImage isofiles/boot/kernel
cp initramfs.cpio.gz isofiles/boot/initramfs.cpio.gz

cat > isofiles/boot/grub/grub.cfg << 'EOF'
set timeout=5
set default=0

menuentry "Micro-Linux (Modo Volatil en RAM)" {
    linux /boot/kernel console=tty0
    initrd /boot/initramfs.cpio.gz
}

menuentry "Micro-Linux (Arranque Nativo desde Disco Duro)" {
    linux /boot/kernel root=/dev/sda1 rw init=/init console=tty0
}
EOF

grub-mkrescue -o micro-linux.iso isofiles/ > /dev/null 2>&1

echo "--- ¡ISO Generada con éxito! ---"
