#!/bin/bash

# ==========================================
# FASE A: Seguridad y Limpieza
# ==========================================
echo "--- Iniciando construcción de Micro-Linux ---"

# 1. Comprobación de prerrequisitos (Materias primas)
if [ ! -f "busybox" ] || [ ! -f "bzImage" ]; then
    echo "[ERROR CRÍTICO] No se encuentran los archivos maestros 'busybox' o 'bzImage'."
    echo "Asegúrate de haberlos copiado a este directorio."
    exit 1
fi

# 2. Limpieza de construcciones previas (Saneamiento del taller)
echo "[+] Limpiando el entorno de trabajo..."
rm -rf initramfs isofiles initramfs.cpio.gz micro-linux.iso

# ==========================================
# FASE B: El Corazón del Sistema
# ==========================================
# 3. Crear estructura del Initramfs
echo "[+] Creando estructura de directorios en RAM..."
mkdir -p initramfs/{bin,sbin,etc,proc,sys,usr/bin,usr/sbin,dev}

# 4. Instalar BusyBox y automatizar funciones
echo "[+] Instalando BusyBox y forjando enlaces simbólicos..."
cp busybox initramfs/bin/busybox
chmod +x initramfs/bin/busybox

cd initramfs/bin
for prog in $(./busybox --list); do
    ln -s busybox $prog
done
cd ../..

# 5. Crear el script 'init' (PID 1)
echo "[+] Escribiendo el script de inicialización (init)..."
cat > initramfs/init << 'EOF'
#!/bin/sh

# a. Montar sistemas de archivos virtuales
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev

# b. Mensaje de bienvenida
echo "---------------------------------------------"
echo " ¡Bienvenido a Micro-Linux Automatizado! "
echo " Boot completado con éxito. "
echo "---------------------------------------------"

# c. Lanzar shell interactiva
exec /bin/sh
EOF

# Hacer ejecutable el init
chmod +x initramfs/init

# ==========================================
# FASE C: Empaquetado y GRUB
# ==========================================
# 6. Empaquetar el Initramfs (cpio + gzip)
echo "[+] Empaquetando la estructura en initramfs.cpio.gz..."
cd initramfs
find . -print0 | cpio --null -ov --format=newc | gzip -9 > ../initramfs.cpio.gz
cd ..

# 7. Preparar estructura para la ISO y copiar componentes
echo "[+] Ensamblando el disco final (ISO)..."
mkdir -p isofiles/boot/grub

# Renombramos el artefacto de compilación (bzImage) a 'kernel' por estandarización
cp bzImage isofiles/boot/kernel
cp initramfs.cpio.gz isofiles/boot/initramfs.cpio.gz


# 8. Escribir el mapa de configuración de GRUB
echo "[+] Generando mapa de arranque (grub.cfg)..."
cat > isofiles/boot/grub/grub.cfg << 'EOF'
set timeout=5
set default=0

menuentry "Micro-Linux (Automated RAM Mode)" {
    echo "Cargando el Kernel..."
    linux /boot/kernel console=tty0
    echo "Cargando el sistema de archivos..."
    initrd /boot/initramfs.cpio.gz
}
EOF

# 9. Generar la imagen ISO final
echo "[+] Fundiendo la imagen micro-linux.iso..."
grub-mkrescue -o micro-linux.iso isofiles/ > /dev/null 2>&1

echo "---------------------------------------------"
echo "¡CADENA DE MONTAJE FINALIZADA!"
echo "Tu sistema operativo ha sido empaquetado en: micro-linux.iso"
echo "---------------------------------------------"
echo "Para probarlo usa: qemu-system-x86_64 -cdrom micro-linux.iso -m 1024 -boot d"
