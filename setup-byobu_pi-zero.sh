#!/bin/bash
# Byobu Pi Zero 2 W Setup Script
# setup-byobu_pi-zero.sh
set -e

echo "🚀 Setting up Byobu for Pi Zero 2 W..."

# 1. Install Byobu if not present
if ! command -v byobu &> /dev/null; then
    echo "📦 Installing Byobu..."
    sudo apt update
    sudo apt install -y byobu bc
fi

# 2. Ensure directories exist
mkdir -p ~/.byobu/bin

# 3. Create the main status script
cat > ~/.byobu/bin/10_pi_status << 'EOF'
#!/bin/bash
# Pi Zero 2 W combined status

# Temperature
temp=$(vcgencmd measure_temp 2>/dev/null | cut -d= -f2 | cut -d\' -f1 2>/dev/null)
[ -z "$temp" ] && temp="N/A"

# CPU frequency
freq=$(vcgencmd measure_clock arm 2>/dev/null | cut -d= -f2 2>/dev/null)
if [ -n "$freq" ]; then
    freq_mhz=$((freq / 1000000))
else
    freq_mhz="?"
fi

# Memory
mem_used=$(free -m 2>/dev/null | awk '/^Mem:/{print $3}')
mem_total=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')
if [ -n "$mem_used" ] && [ -n "$mem_total" ] && [ "$mem_total" -gt 0 ]; then
    mem_pct=$((mem_used * 100 / mem_total))
else
    mem_pct="?"
fi

# WiFi
wifi=""
if iwconfig wlan0 2>/dev/null | grep -q "ESSID" 2>/dev/null; then
    quality=$(iwconfig wlan0 2>/dev/null | grep "Link Quality" | awk -F'=' '{print $2}' | cut -d'/' -f1)
    if [ -n "$quality" ]; then
        wifi=" 📶${quality}%"
    fi
fi

# Throttling
throttle=""
if vcgencmd get_throttled 2>/dev/null | grep -q "0x0" 2>/dev/null; then
    throttle=" ✓"
else
    throttle=" ⚠️"
fi

echo "🌡${temp} ⚡${freq_mhz}MHz 🧠${mem_pct}%${wifi}${throttle}"
EOF

chmod +x ~/.byobu/bin/10_pi_status

# 4. Create statusrc
cat > ~/.byobu/statusrc << 'EOF'
# Pi Zero 2 W optimized status
STATUS_SCRIPTS="pi_status"
MONITORED_SCRIPTS="pi_status"
STATUS_REFRESH=3
BYOBU_DISABLE_CJK=1
EOF

# 5. Setup Byobu to auto-start
if [ ! -f ~/.byobu/disable-autolaunch ]; then
    echo "🔧 Enabling Byobu auto-start..."
    echo "byobu" >> ~/.bashrc
fi

# 6. Use tmux backend (lighter)
echo "🔄 Setting tmux backend..."
byobu-select-backend -t tmux 2>/dev/null || echo "tmux" > ~/.byobu/backend

# 7. Verify
echo ""
echo "✅ Setup complete! Testing script:"
~/.byobu/bin/10_pi_status

echo ""
echo "📌 To apply:"
echo "   - Press F5 to reload status bar"
echo "   - Or restart: byobu kill-server && byobu"

# 8. Optional extras
read -p "Install additional monitoring tools? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo apt install -y htop iotop iftop
    echo "✅ Additional tools installed: htop, iotop, iftop"
fi