#!/bin/bash
# =============================================================================
# ARCH LINUX + HYPRLAND INSTALLATION SCRIPT - FASE 1
# Script para ejecutar desde el entorno live de Arch Linux
# =============================================================================

set -e

echo "==========================================="
echo "ARCH LINUX + HYPRLAND - FASE 1"
echo "Configuración inicial y particionado"
echo "==========================================="

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_step() {
    echo -e "${BLUE}[PASO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[AVISO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Función para preguntar al usuario
ask_user() {
    local question="$1"
    local default="$2"
    local response
    
    if [ -n "$default" ]; then
        read -p "$question [$default]: " response
        response=${response:-$default}
    else
        read -p "$question: " response
    fi
    
    echo "$response"
}

print_step "Verificando conexión a internet..."
if ping -c 1 archlinux.org &> /dev/null; then
    print_success "Conexión a internet OK"
else
    print_error "Sin conexión a internet. Verifica la configuración de red."
    exit 1
fi

print_step "Configurando teclado español..."
loadkeys es
print_success "Teclado configurado"

print_step "Sincronizando reloj del sistema..."
timedatectl set-ntp true
print_success "Reloj sincronizado"

print_step "Actualizando lista de mirrors..."
pacman -Sy --noconfirm
print_success "Mirrors actualizados"

print_step "Mostrando discos disponibles:"
lsblk
echo ""

# Configuración de disco
DISK=$(ask_user "¿Qué disco quieres usar? (por defecto /dev/sda)" "/dev/sda")

if [ ! -b "$DISK" ]; then
    print_error "El disco $DISK no existe"
    exit 1
fi

print_warning "¡ATENCIÓN! Esto borrará TODOS los datos en $DISK"
CONFIRM=$(ask_user "¿Continuar? (sí/no)" "no")

if [ "$CONFIRM" != "sí" ] && [ "$CONFIRM" != "si" ] && [ "$CONFIRM" != "yes" ]; then
    print_error "Instalación cancelada por el usuario"
    exit 1
fi

print_step "Particionando disco $DISK..."

# Crear tabla de particiones GPT
parted $DISK --script mklabel gpt

# Crear partición EFI (512MB)
parted $DISK --script mkpart primary fat32 1MiB 513MiB
parted $DISK --script set 1 esp on

# Crear partición raíz (resto del espacio)
parted $DISK --script mkpart primary ext4 513MiB 100%

print_success "Particionado completado"

# Variables de particiones
EFI_PARTITION="${DISK}1"
ROOT_PARTITION="${DISK}2"

print_step "Formateando particiones..."

# Formatear partición EFI
mkfs.fat -F32 "$EFI_PARTITION"
print_success "Partición EFI formateada"

# Formatear partición raíz
mkfs.ext4 -F "$ROOT_PARTITION"
print_success "Partición raíz formateada"

print_step "Montando particiones..."

# Montar partición raíz
mount "$ROOT_PARTITION" /mnt

# Crear y montar directorio boot
mkdir /mnt/boot
mount "$EFI_PARTITION" /mnt/boot

print_success "Particiones montadas"

print_step "Instalando sistema base..."
pacstrap /mnt base linux linux-firmware networkmanager sudo nano git \
    pipewire wireplumber pipewire-audio pipewire-pulse mesa \
    xf86-video-vmware virtualbox-guest-utils polkit

print_success "Sistema base instalado"

print_step "Generando fstab..."
genfstab -U /mnt >> /mnt/etc/fstab
print_success "fstab generado"

print_step "Copiando script de fase 2 al sistema instalado..."

cat > /mnt/phase2.sh << 'EOFSCRIPT'
#!/bin/bash
# =============================================================================
# ARCH LINUX + HYPRLAND INSTALLATION SCRIPT - FASE 2
# Script para ejecutar dentro del chroot
# =============================================================================

set -e

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step() {
    echo -e "${BLUE}[PASO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

ask_user() {
    local question="$1"
    local default="$2"
    local response
    
    if [ -n "$default" ]; then
        read -p "$question [$default]: " response
        response=${response:-$default}
    else
        read -p "$question: " response
    fi
    
    echo "$response"
}

echo "==========================================="
echo "ARCH LINUX + HYPRLAND - FASE 2"
echo "Configuración del sistema"
echo "==========================================="

print_step "Configurando zona horaria..."
ln -sf /usr/share/zoneinfo/Europe/Madrid /etc/localtime
hwclock --systohc
print_success "Zona horaria configurada"

print_step "Configurando idioma..."
sed -i 's/#es_ES.UTF-8 UTF-8/es_ES.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo 'LANG=es_ES.UTF-8' > /etc/locale.conf
echo 'KEYMAP=es' > /etc/vconsole.conf
print_success "Idioma configurado"

print_step "Configurando hostname..."
HOSTNAME=$(ask_user "Nombre del equipo" "archlinux")
echo "$HOSTNAME" > /etc/hostname

cat > /etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain   $HOSTNAME
EOF
print_success "Hostname configurado: $HOSTNAME"

print_step "Instalando GRUB..."
pacman -S --noconfirm grub efibootmgr
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
print_success "GRUB instalado"

print_step "Configurando contraseña de root..."
echo "Establece una contraseña para root:"
passwd

print_step "Creando usuario..."
USERNAME=$(ask_user "Nombre de usuario" "usuario")
useradd -m -G wheel -s /bin/bash "$USERNAME"
echo "Establece una contraseña para $USERNAME:"
passwd "$USERNAME"

print_step "Configurando sudo..."
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
print_success "Sudo configurado"

print_step "Habilitando servicios..."
systemctl enable NetworkManager
systemctl enable vboxservice
print_success "Servicios habilitados"

print_step "Creando script de fase 3..."
cat > /home/$USERNAME/phase3.sh << 'EOFPHASE3'
#!/bin/bash
# =============================================================================
# ARCH LINUX + HYPRLAND INSTALLATION SCRIPT - FASE 3
# Script para ejecutar después del primer reinicio como usuario normal
# =============================================================================

set -e

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step() {
    echo -e "${BLUE}[PASO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

echo "==========================================="
echo "ARCH LINUX + HYPRLAND - FASE 3"
echo "Instalación de Hyprland"
echo "==========================================="

print_step "Actualizando sistema..."
sudo pacman -Syu --noconfirm
print_success "Sistema actualizado"

print_step "Instalando Hyprland y componentes..."
sudo pacman -S --noconfirm hyprland hyprpaper xdg-desktop-portal-hyprland \
    waybar wofi kitty sddm firefox thunar grim slurp wl-clipboard \
    brightnessctl pamixer ttf-jetbrains-mono noto-fonts noto-fonts-emoji

print_success "Hyprland instalado"

print_step "Configurando SDDM..."
sudo systemctl enable sddm

sudo mkdir -p /etc/sddm.conf.d
sudo tee /etc/sddm.conf.d/hyprland.conf << EOF
[Theme]
Current=breeze

[Wayland]
SessionDir=/usr/share/wayland-sessions
EOF

print_success "SDDM configurado"

print_step "Creando configuración de Hyprland..."
mkdir -p ~/.config/hypr

tee ~/.config/hypr/hyprland.conf << 'EOF'
# Monitor configuration
monitor=,preferred,auto,1

# Input configuration
input {
    kb_layout = es
    kb_variant =
    kb_model =
    kb_options =
    kb_rules =
    
    follow_mouse = 1
    touchpad {
        natural_scroll = no
    }
    sensitivity = 0
}

# General settings
general {
    gaps_in = 5
    gaps_out = 10
    border_size = 2
    col.active_border = rgba(33ccffee) rgba(00ff99ee) 45deg
    col.inactive_border = rgba(595959aa)
    layout = dwindle
}

# Decoration
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

# Animations
animations {
    enabled = yes
    bezier = myBezier, 0.05, 0.9, 0.1, 1.05
    animation = windows, 1, 7, myBezier
    animation = windowsOut, 1, 7, default, popin 80%
    animation = border, 1, 10, default
    animation = borderangle, 1, 8, default
    animation = fade, 1, 7, default
    animation = workspaces, 1, 6, default
}

# Layout
dwindle {
    pseudotile = yes
    preserve_split = yes
}

# Window rules
windowrule = float, ^(kitty)$
windowrule = center, ^(kitty)$
windowrule = size 800 600, ^(kitty)$

# Key bindings
$mainMod = SUPER

bind = $mainMod, Q, exec, kitty
bind = $mainMod, C, killactive,
bind = $mainMod, M, exit,
bind = $mainMod, E, exec, thunar
bind = $mainMod, V, togglefloating,
bind = $mainMod, R, exec, wofi --show drun
bind = $mainMod, P, pseudo,
bind = $mainMod, J, togglesplit,
bind = $mainMod, F, exec, firefox

# Move focus
bind = $mainMod, left, movefocus, l
bind = $mainMod, right, movefocus, r
bind = $mainMod, up, movefocus, u
bind = $mainMod, down, movefocus, d

# Switch workspaces
bind = $mainMod, 1, workspace, 1
bind = $mainMod, 2, workspace, 2
bind = $mainMod, 3, workspace, 3
bind = $mainMod, 4, workspace, 4
bind = $mainMod, 5, workspace, 5
bind = $mainMod, 6, workspace, 6
bind = $mainMod, 7, workspace, 7
bind = $mainMod, 8, workspace, 8
bind = $mainMod, 9, workspace, 9
bind = $mainMod, 0, workspace, 10

# Move active window to workspace
bind = $mainMod SHIFT, 1, movetoworkspace, 1
bind = $mainMod SHIFT, 2, movetoworkspace, 2
bind = $mainMod SHIFT, 3, movetoworkspace, 3
bind = $mainMod SHIFT, 4, movetoworkspace, 4
bind = $mainMod SHIFT, 5, movetoworkspace, 5
bind = $mainMod SHIFT, 6, movetoworkspace, 6
bind = $mainMod SHIFT, 7, movetoworkspace, 7
bind = $mainMod SHIFT, 8, movetoworkspace, 8
bind = $mainMod SHIFT, 9, movetoworkspace, 9
bind = $mainMod SHIFT, 0, movetoworkspace, 10

# Screenshot
bind = , Print, exec, grim -g "$(slurp)" - | wl-copy

# Audio
bind = , XF86AudioRaiseVolume, exec, pamixer -i 5
bind = , XF86AudioLowerVolume, exec, pamixer -d 5
bind = , XF86AudioMute, exec, pamixer -t

# Mouse bindings
bindm = $mainMod, mouse:272, movewindow
bindm = $mainMod, mouse:273, resizewindow

# Autostart
exec-once = waybar
exec-once = hyprpaper
EOF

print_success "Configuración de Hyprland creada"

print_step "Configurando Waybar..."
mkdir -p ~/.config/waybar

tee ~/.config/waybar/config << 'EOF'
{
    "layer": "top",
    "position": "top",
    "height": 30,
    "spacing": 4,
    "modules-left": ["hyprland/workspaces"],
    "modules-center": ["hyprland/window"],
    "modules-right": ["pulseaudio", "network", "cpu", "memory", "clock"],
    
    "hyprland/workspaces": {
        "disable-scroll": true,
        "all-outputs": true,
        "format": "{icon}",
        "format-icons": {
            "1": "",
            "2": "",
            "3": "",
            "4": "",
            "5": "",
            "urgent": "",
            "focused": "",
            "default": ""
        }
    },
    
    "hyprland/window": {
        "format": "{}",
        "max-length": 50
    },
    
    "clock": {
        "format": "{:%H:%M - %d/%m/%Y}",
        "tooltip-format": "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>"
    },
    
    "cpu": {
        "format": "  {usage}%",
        "tooltip": false
    },
    
    "memory": {
        "format": "  {}%"
    },
    
    "network": {
        "format-wifi": "  {signalStrength}%",
        "format-ethernet": "  Connected",
        "format-linked": "  {ifname} (No IP)",
        "format-disconnected": "⚠  Disconnected",
        "format-alt": "{ifname}: {ipaddr}/{cidr}"
    },
    
    "pulseaudio": {
        "format": "{icon} {volume}%",
        "format-bluetooth": "{icon} {volume}% ",
        "format-bluetooth-muted": " {icon}",
        "format-muted": " Muted",
        "format-source": "{volume}% ",
        "format-source-muted": "",
        "format-icons": {
            "headphone": "",
            "hands-free": "",
            "headset": "",
            "phone": "",
            "portable": "",
            "car": "",
            "default": ["", "", ""]
        },
        "on-click": "pavucontrol"
    }
}
EOF

tee ~/.config/waybar/style.css << 'EOF'
* {
    border: none;
    border-radius: 0;
    font-family: "JetBrains Mono", monospace;
    font-weight: bold;
    font-size: 13px;
    min-height: 0;
}

window#waybar {
    background-color: rgba(43, 48, 59, 0.9);
    border-bottom: 3px solid rgba(100, 114, 125, 0.5);
    color: #ffffff;
    transition-property: background-color;
    transition-duration: .5s;
}

button {
    box-shadow: inset 0 -3px transparent;
    border: none;
    border-radius: 0;
}

#workspaces button {
    padding: 0 5px;
    background-color: transparent;
    color: #ffffff;
}

#workspaces button:hover {
    background: rgba(0, 0, 0, 0.2);
}

#workspaces button.focused {
    background-color: #64727D;
    box-shadow: inset 0 -3px #ffffff;
}

#workspaces button.urgent {
    background-color: #eb4d4b;
}

#mode {
    background-color: #64727D;
    border-bottom: 3px solid #ffffff;
}

#clock,
#battery,
#cpu,
#memory,
#disk,
#temperature,
#backlight,
#network,
#pulseaudio,
#custom-media,
#tray,
#mode,
#idle_inhibitor,
#mpd {
    padding: 0 10px;
    color: #ffffff;
}

#window,
#workspaces {
    margin: 0 4px;
}

#clock {
    background-color: #64727D;
}

#battery {
    background-color: #ffffff;
    color: #000000;
}

#battery.charging, #battery.plugged {
    color: #ffffff;
    background-color: #26A65B;
}

@keyframes blink {
    to {
        background-color: #ffffff;
        color: #000000;
    }
}

#battery.critical:not(.charging) {
    background-color: #f53c3c;
    color: #ffffff;
    animation-name: blink;
    animation-duration: 0.5s;
    animation-timing-function: linear;
    animation-iteration-count: infinite;
    animation-direction: alternate;
}

#cpu {
    background-color: #2ecc71;
    color: #000000;
}

#memory {
    background-color: #9b59b6;
}

#disk {
    background-color: #964B00;
}

#backlight {
    background-color: #90b1b1;
}

#network {
    background-color: #2980b9;
}

#network.disconnected {
    background-color: #f53c3c;
}

#pulseaudio {
    background-color: #f1c40f;
    color: #000000;
}

#pulseaudio.muted {
    background-color: #90b1b1;
    color: #2a5c45;
}

#tray {
    background-color: #2980b9;
}

#tray > .passive {
    -gtk-icon-effect: dim;
}

#tray > .needs-attention {
    -gtk-icon-effect: highlight;
    background-color: #eb4d4b;
}

#idle_inhibitor {
    background-color: #2d3748;
}

#idle_inhibitor.activated {
    background-color: #ecf0f1;
    color: #2d3748;
}

#mpd {
    background-color: #66cc99;
    color: #2a5c45;
}

#mpd.disconnected {
    background-color: #f53c3c;
}

#mpd.stopped {
    background-color: #90b1b1;
}

#mpd.paused {
    background-color: #51a37a;
}
EOF

print_success "Waybar configurado"

print_step "Configurando fondo de pantalla..."
mkdir -p ~/.config/hypr

# Crear un fondo de pantalla simple con colores
tee ~/.config/hypr/hyprpaper.conf << 'EOF'
preload = ~/.config/hypr/wallpaper.jpg
wallpaper = ,~/.config/hypr/wallpaper.jpg
EOF

# Crear un fondo de pantalla simple
convert -size 1920x1080 gradient:blue-purple ~/.config/hypr/wallpaper.jpg 2>/dev/null || {
    # Si ImageMagick no está disponible, crear un archivo de color sólido
    echo "Descargando fondo de pantalla de ejemplo..."
    curl -s -o ~/.config/hypr/wallpaper.jpg "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=1920&h=1080&fit=crop&crop=entropy&cs=tinysrgb" || {
        # Si no hay internet, crear un archivo vacío
        touch ~/.config/hypr/wallpaper.jpg
    }
}

print_success "Fondo de pantalla configurado"

print_step "Configurando Wofi (lanzador de aplicaciones)..."
mkdir -p ~/.config/wofi

tee ~/.config/wofi/config << 'EOF'
width=600
height=400
location=center
show=drun
prompt=Aplicaciones
filter_rate=100
allow_markup=true
no_actions=true
halign=fill
orientation=vertical
content_halign=fill
insensitive=true
allow_images=true
image_size=40
gtk_dark=true
EOF

tee ~/.config/wofi/style.css << 'EOF'
window {
margin: 0px;
border: 2px solid #1e1e2e;
background-color: #181825;
border-radius: 10px;
}

#input {
margin: 5px;
border: 2px solid #313244;
color: #cdd6f4;
background-color: #1e1e2e;
border-radius: 10px;
}

#inner-box {
margin: 5px;
border: none;
background-color: #181825;
border-radius: 10px;
}

#outer-box {
margin: 5px;
border: none;
background-color: #181825;
border-radius: 10px;
}

#scroll {
margin: 0px;
border: none;
}

#text {
margin: 5px;
border: none;
color: #cdd6f4;
}

#entry:selected {
background-color: #313244;
border-radius: 10px;
}

#text:selected {
color: #cdd6f4;
}
EOF

print_success "Wofi configurado"

echo ""
echo "==========================================="
echo "¡INSTALACIÓN COMPLETADA!"
echo "==========================================="
echo ""
echo "Hyprland está instalado y configurado."
echo "Reinicia el sistema para usar SDDM y Hyprland."
echo ""
echo "Atajos de teclado principales:"
echo "  Super + Q      : Terminal (kitty)"
echo "  Super + R      : Lanzador de aplicaciones (wofi)"
echo "  Super + E      : Explorador de archivos (thunar)"
echo "  Super + F      : Firefox"
echo "  Super + C      : Cerrar ventana"
echo "  Super + V      : Alternar ventana flotante"
echo "  Super + M      : Salir de Hyprland"
echo "  Super + 1-9    : Cambiar workspace"
echo "  Print          : Captura de pantalla"
echo ""
echo "Para reiniciar: sudo reboot"
echo ""

EOFPHASE3

chown $USERNAME:$USERNAME /home/$USERNAME/phase3.sh
chmod +x /home/$USERNAME/phase3.sh

print_success "Script de fase 3 creado en /home/$USERNAME/phase3.sh"

echo ""
echo "==========================================="
echo "FASE 2 COMPLETADA"
echo "==========================================="
echo ""
echo "El sistema base está configurado."
echo "Saldrás del chroot y podrás reiniciar."
echo ""
echo "Después del reinicio:"
echo "1. Inicia sesión como $USERNAME"
echo "2. Ejecuta: ./phase3.sh"
echo "3. Reinicia para usar Hyprland"
echo ""

EOFSCRIPT

chmod +x /mnt/phase2.sh

print_success "Script de fase 2 copiado"

echo ""
echo "==========================================="
echo "FASE 1 COMPLETADA"
echo "==========================================="
echo ""
echo "Ahora ejecuta los siguientes comandos:"
echo "1. arch-chroot /mnt"
echo "2. ./phase2.sh"
echo "3. exit"
echo "4. umount -R /mnt"
echo "5. reboot"
echo ""
echo "Después del reinicio, ejecuta ./phase3.sh como usuario normal"
echo ""
