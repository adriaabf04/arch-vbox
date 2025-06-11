#!/bin/bash
# =============================================================================
# SCRIPT DE INSTALACIÓN AUTOMÁTICA: ARCH LINUX + HYPRLAND PARA VIRTUALBOX
# =============================================================================

set -e  # Salir si hay algún error

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función para logging
log() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# =============================================================================
# FASE 1: PREPARACIÓN DEL SISTEMA LIVE
# =============================================================================

fase1_preparacion() {
    log "Iniciando Fase 1: Preparación del sistema live"
    
    # Verificar conexión a internet
    if ! ping -c 1 archlinux.org > /dev/null 2>&1; then
        error "No hay conexión a internet. Verifica la configuración de red."
    fi
    success "Conexión a internet verificada"
    
    # Configurar teclado español
    loadkeys es
    success "Teclado configurado en español"
    
    # Sincronizar reloj
    timedatectl set-ntp true
    success "Reloj sincronizado"
    
    # Actualizar keyring
    pacman -Sy --noconfirm archlinux-keyring
    success "Keyring actualizado"
}

# =============================================================================
# FASE 2: PARTICIONADO AUTOMÁTICO
# =============================================================================

fase2_particionado() {
    log "Iniciando Fase 2: Particionado automático"
    
    DISK="/dev/sda"
    
    # Verificar que el disco existe
    if [ ! -b "$DISK" ]; then
        error "Disco $DISK no encontrado"
    fi
    
    warning "¡ATENCIÓN! Se va a particionar completamente $DISK"
    warning "Todos los datos se perderán. Presiona Enter para continuar o Ctrl+C para cancelar"
    read
    
    # Limpiar disco y crear tabla de particiones GPT
    wipefs -af "$DISK"
    parted "$DISK" --script mklabel gpt
    
    # Crear particiones
    parted "$DISK" --script mkpart ESP fat32 1MiB 513MiB
    parted "$DISK" --script set 1 esp on
    parted "$DISK" --script mkpart primary ext4 513MiB 100%
    
    success "Particiones creadas"
    
    # Formatear particiones
    mkfs.fat -F32 "${DISK}1"
    mkfs.ext4 -F "${DISK}2"
    
    success "Particiones formateadas"
    
    # Montar particiones
    mount "${DISK}2" /mnt
    mkdir -p /mnt/boot
    mount "${DISK}1" /mnt/boot
    
    success "Particiones montadas"
}

# =============================================================================
# FASE 3: INSTALACIÓN DEL SISTEMA BASE
# =============================================================================

fase3_sistema_base() {
    log "Iniciando Fase 3: Instalación del sistema base"
    
    # Actualizar mirrors para España
    cat > /etc/pacman.d/mirrorlist << 'EOF'
Server = https://mirrors.kernel.org/archlinux/$repo/os/$arch
Server = https://archlinux.mirror.wearetriple.com/$repo/os/$arch
Server = https://mirror.cj2.nl/archlinux/$repo/os/$arch
EOF
    
    # Instalar sistema base con paquetes para Hyprland
    log "Instalando paquetes base (esto puede tardar varios minutos)..."
    pacstrap /mnt base linux linux-firmware networkmanager sudo nano git \
        pipewire wireplumber pipewire-audio pipewire-pulse mesa \
        xf86-video-vmware virtualbox-guest-utils polkit grub efibootmgr
    
    success "Sistema base instalado"
    
    # Generar fstab
    genfstab -U /mnt >> /mnt/etc/fstab
    success "fstab generado"
}

# =============================================================================
# FASE 4: CONFIGURACIÓN DEL SISTEMA
# =============================================================================

fase4_configuracion() {
    log "Iniciando Fase 4: Configuración del sistema"
    
    # Crear script de configuración para chroot
    cat > /mnt/config_chroot.sh << 'CHROOT_EOF'
#!/bin/bash
set -e

# Configurar zona horaria
ln -sf /usr/share/zoneinfo/Europe/Madrid /etc/localtime
hwclock --systohc

# Configurar idioma
sed -i 's/#es_ES.UTF-8 UTF-8/es_ES.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo 'LANG=es_ES.UTF-8' > /etc/locale.conf
echo 'KEYMAP=es' > /etc/vconsole.conf

# Configurar hostname
echo 'arch-hyprland' > /etc/hostname

# Configurar hosts
cat > /etc/hosts << 'EOF'
127.0.0.1   localhost
::1         localhost
127.0.1.1   arch-hyprland.localdomain   arch-hyprland
EOF

# Configurar usuario y contraseñas
echo "Configurando contraseña de root (usa: arch123)"
echo 'root:arch123' | chpasswd

# Crear usuario
useradd -m -G wheel -s /bin/bash usuario
echo 'usuario:usuario123' | chpasswd

# Configurar sudo
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Instalar bootloader
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Habilitar servicios
systemctl enable NetworkManager
systemctl enable vboxservice

echo "Configuración del sistema completada"
CHROOT_EOF

    # Ejecutar configuración en chroot
    chmod +x /mnt/config_chroot.sh
    arch-chroot /mnt /config_chroot.sh
    rm /mnt/config_chroot.sh
    
    success "Sistema configurado"
}

# =============================================================================
# FUNCIÓN PRINCIPAL PARA FASE 1-4 (PRE-REBOOT)
# =============================================================================

instalar_sistema_base() {
    log "=== INSTALACIÓN AUTOMÁTICA DE ARCH LINUX ==="
    log "Esta instalación incluirá:"
    log "- Arch Linux base"
    log "- Configuración para VirtualBox"
    log "- Preparación para Hyprland"
    
    fase1_preparacion
    fase2_particionado
    fase3_sistema_base
    fase4_configuracion
    
    success "¡Instalación del sistema base completada!"
    warning "El sistema se reiniciará en 10 segundos..."
    warning "Después del reinicio, ejecuta la segunda parte del script"
    
    # Crear script para post-instalación
    cat > /mnt/home/usuario/install_hyprland.sh << 'POST_EOF'
#!/bin/bash
# =============================================================================
# FASE 5: INSTALACIÓN POST-REBOOT - HYPRLAND
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

log "=== INSTALACIÓN DE HYPRLAND ==="

# Actualizar sistema
sudo pacman -Syu --noconfirm

# Instalar Hyprland y dependencias
log "Instalando Hyprland y aplicaciones..."
sudo pacman -S --noconfirm hyprland hyprpaper xdg-desktop-portal-hyprland \
    waybar wofi kitty sddm firefox thunar grim slurp wl-clipboard \
    brightnessctl pamixer ttf-jetbrains-mono noto-fonts

# Configurar SDDM
sudo mkdir -p /etc/sddm.conf.d
sudo tee /etc/sddm.conf.d/hyprland.conf > /dev/null << 'EOF'
[Theme]
Current=breeze

[Wayland]
SessionDir=/usr/share/wayland-sessions
EOF

sudo systemctl enable sddm

# Crear configuraciones
mkdir -p ~/.config/{hypr,waybar}

# Configuración de Hyprland
tee ~/.config/hypr/hyprland.conf > /dev/null << 'EOF'
monitor=,preferred,auto,1

input {
    kb_layout = es
    follow_mouse = 1
    touchpad { natural_scroll = no }
    sensitivity = 0
}

general {
    gaps_in = 5
    gaps_out = 10
    border_size = 2
    col.active_border = rgba(33ccffee) rgba(00ff99ee) 45deg
    col.inactive_border = rgba(595959aa)
    layout = dwindle
}

decoration {
    rounding = 10
    blur {
        enabled = true
        size = 3
        passes = 1
    }
    drop_shadow = yes
    shadow_range = 4
    shadow_render_power = 3
    col.shadow = rgba(1a1a1aee)
}

animations {
    enabled = yes
    bezier = myBezier, 0.05, 0.9, 0.1, 1.05
    animation = windows, 1, 7, myBezier
    animation = windowsOut, 1, 7, default, popin 80%
    animation = border, 1, 10, default
    animation = fade, 1, 7, default
    animation = workspaces, 1, 6, default
}

dwindle {
    pseudotile = yes
    preserve_split = yes
}

$mainMod = SUPER

bind = $mainMod, Q, exec, kitty
bind = $mainMod, C, killactive,
bind = $mainMod, M, exit,
bind = $mainMod, E, exec, thunar
bind = $mainMod, V, togglefloating,
bind = $mainMod, R, exec, wofi --show drun
bind = $mainMod, F, exec, firefox

bind = $mainMod, left, movefocus, l
bind = $mainMod, right, movefocus, r
bind = $mainMod, up, movefocus, u
bind = $mainMod, down, movefocus, d

bind = $mainMod, 1, workspace, 1
bind = $mainMod, 2, workspace, 2
bind = $mainMod, 3, workspace, 3
bind = $mainMod, 4, workspace, 4
bind = $mainMod, 5, workspace, 5

bind = $mainMod SHIFT, 1, movetoworkspace, 1
bind = $mainMod SHIFT, 2, movetoworkspace, 2
bind = $mainMod SHIFT, 3, movetoworkspace, 3
bind = $mainMod SHIFT, 4, movetoworkspace, 4
bind = $mainMod SHIFT, 5, movetoworkspace, 5

bindm = $mainMod, mouse:272, movewindow
bindm = $mainMod, mouse:273, resizewindow

exec-once = waybar
exec-once = hyprpaper
EOF

# Configuración de Waybar
tee ~/.config/waybar/config > /dev/null << 'EOF'
{
    "layer": "top",
    "position": "top",
    "height": 30,
    "modules-left": ["hyprland/workspaces"],
    "modules-center": ["hyprland/window"],
    "modules-right": ["pulseaudio", "network", "cpu", "memory", "clock"],
    
    "hyprland/workspaces": {
        "disable-scroll": true,
        "format": "{icon}",
        "format-icons": {
            "urgent": "",
            "focused": "",
            "default": ""
        }
    },
    
    "clock": { "format": "{:%H:%M - %d/%m/%Y}" },
    "cpu": { "format": "  {usage}%" },
    "memory": { "format": "  {}%" },
    "network": {
        "format-wifi": "  {signalStrength}%",
        "format-ethernet": "  Connected",
        "format-disconnected": "  Disconnected"
    },
    "pulseaudio": {
        "format": "{icon} {volume}%",
        "format-muted": " Muted",
        "format-icons": ["", "", ""]
    }
}
EOF

# Estilo de Waybar
tee ~/.config/waybar/style.css > /dev/null << 'EOF'
* {
    font-family: "JetBrains Mono", monospace;
    font-size: 14px;
    min-height: 0;
}

window#waybar {
    background: rgba(43, 48, 59, 0.9);
    border-bottom: 3px solid rgba(100, 114, 125, 0.5);
    color: #ffffff;
}

#workspaces button {
    padding: 0 5px;
    background: transparent;
    color: #ffffff;
    border: none;
}

#workspaces button.focused {
    background: #64727D;
}

#clock, #cpu, #memory, #network, #pulseaudio {
    padding: 0 10px;
    margin: 0 5px;
}
EOF

# Configurar fondo de pantalla
echo 'preload = /usr/share/pixmaps/archlinux-logo.png' > ~/.config/hypr/hyprpaper.conf
echo 'wallpaper = ,/usr/share/pixmaps/archlinux-logo.png' >> ~/.config/hypr/hyprpaper.conf

success "¡Hyprland instalado y configurado!"
log "Credenciales del sistema:"
log "  Usuario: usuario | Contraseña: usuario123"
log "  Root: root | Contraseña: arch123"
log ""
log "Atajos básicos de Hyprland:"
log "  Super + Q: Terminal"
log "  Super + R: Lanzador de apps"
log "  Super + E: Explorador de archivos"
log "  Super + F: Firefox"
log "  Super + C: Cerrar ventana"
log "  Super + M: Salir"
log ""
log "El sistema se reiniciará para iniciar SDDM..."
sleep 5
sudo reboot
POST_EOF

    chmod +x /mnt/home/usuario/install_hyprland.sh
    
    sleep 10
    umount -R /mnt
    reboot
}

# =============================================================================
# EJECUCIÓN PRINCIPAL
# =============================================================================

# Verificar si estamos en el sistema live de Arch
if [ ! -f /etc/arch-release ]; then
    error "Este script debe ejecutarse desde el ISO live de Arch Linux"
fi

# Verificar si ya estamos en un sistema instalado
if [ -d /home ]; then
    error "Parece que ya tienes un sistema instalado. Este script es para instalación limpia."
fi

log "¡Bienvenido al instalador automático de Arch Linux + Hyprland!"
log "Este proceso:"
log "1. Particionará completamente /dev/sda"
log "2. Instalará Arch Linux base"
log "3. Configurará el sistema para VirtualBox"
log "4. Preparará la instalación de Hyprland"
log ""
warning "¡TODOS LOS DATOS EN /dev/sda SE PERDERÁN!"
warning "Presiona Enter para continuar o Ctrl+C para cancelar"
read

instalar_sistema_base