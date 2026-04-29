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
menuentry "Micro-Linux (Modular V2)" {
    linux /boot/kernel console=tty0
    initrd /boot/initramfs.cpio.gz
}
EOF

grub-mkrescue -o micro-linux.iso isofiles/ > /dev/null 2>&1

echo "--- ¡ISO Generada con éxito! ---"
echo "Prueba con: qemu-system-x86_64 -cdrom micro-linux.iso -m 1024 -boot d"
