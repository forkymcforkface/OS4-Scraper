#!/bin/bash
set -e

chmod 777 "$0"


SCRIPT_DIR="$(dirname "$(realpath "$0")")"
ZIP_DIR="$SCRIPT_DIR"
EXTRACT_PATH="/opt/rgbpi/ui/data"

# Write the Python UI
cat << 'EOF' > /tmp/extract_ui.py
import os
import sys
import zipfile
import pygame
import time

zip_dir = os.getenv('ZIP_DIR')
extract_to = os.getenv('EXTRACT_PATH')
scraper_update_text = os.getenv('SCRAPER_UPDATE_TEXT')

pygame.init()
screen = pygame.display.set_mode((320, 240))
pygame.display.set_caption(scraper_update_text)
pygame.mouse.set_visible(False)

font = pygame.font.SysFont(None, 24)
white = (255, 255, 255)
black = (0, 0, 0)
green = (0, 255, 0)

def display_text(msg):
    screen.fill(black)
    text_surface = font.render(msg, True, white)
    text_rect = text_surface.get_rect(center=(160, 120))
    screen.blit(text_surface, text_rect)
    pygame.display.update()

def display_progress(percent, zip_name):
    screen.fill(black)
    msg = f"{zip_name}: {percent}%"
    text_surface = font.render(msg, True, white)
    text_rect = text_surface.get_rect(center=(160, 100))
    pygame.draw.rect(screen, green, (60, 180, int(200 * (percent / 100)), 10))
    screen.blit(text_surface, text_rect)
    pygame.display.update()

# Step 1: Extract all zip files
pygame.event.pump()
display_progress(0, "Initializing")
pygame.time.wait(100)

zip_files = [f for f in os.listdir(zip_dir) if f.lower().endswith('.zip')]

for zip_file in zip_files:
    zip_path = os.path.join(zip_dir, zip_file)
    with zipfile.ZipFile(zip_path, 'r') as zipf:
        all_files = [f for f in zipf.infolist() if not f.is_dir()]
        total_files = len(all_files)

        for i, member in enumerate(all_files):
            target_path = os.path.join(extract_to, member.filename)

            if os.path.exists(target_path):
                if os.path.getsize(target_path) == member.file_size:
                    percent = int(((i + 1) / total_files) * 100)
                    display_progress(percent, os.path.splitext(zip_file)[0])
                    continue

            zipf.extract(member, path=extract_to)
            percent = int(((i + 1) / total_files) * 100)
            display_progress(percent, os.path.splitext(zip_file)[0])

display_progress(100, "All Zips Done")
time.sleep(3)
os.sync()

pygame.quit()
EOF

# Export variables for Python
export ZIP_DIR="$ZIP_DIR"
export EXTRACT_PATH="$EXTRACT_PATH"
export SCRAPER_UPDATE_TEXT="Scraper Update"

# Run Python logic
python3 /tmp/extract_ui.py
rm -f /tmp/extract_ui.py

CONFIG_FILE="/opt/rgbpi/ui/config.ini"
DATA_SOURCE=$(grep '^data_source' "$CONFIG_FILE" | cut -d= -f2 | xargs)
MOUNT_POINT="/media/$DATA_SOURCE"
GAMES_DAT="$MOUNT_POINT/dats/games.dat"
BACKUP_FILE="${GAMES_DAT}.backup"
cp "$MOUNT_POINT/dats/favorites.dat" "$MOUNT_POINT/dats/favorites.dat.backup"
sync
# update list
cd /opt/rgbpi/ui

python3 -c "
import sys
sys.path.append('/opt/rgbpi/ui')
import cglobals, rtk, utils
cglobals.mount_point = '$MOUNT_POINT'
rtk.cfg_scrap_region = 'usa'
rtk.path_rgbpi_scraper = '/opt/rgbpi/ui/data/scraper'
utils.load_scraper_db()
utils.scan_games(do_scrap=True)
" >> /root/logs/rtk.log 2>&1

sleep 1
sync
cp "$MOUNT_POINT/dats/favorites.dat.backup" "$MOUNT_POINT/dats/favorites.dat"

# Normalize games.dat (fill empty Id fields with Name)
if [[ ! -f "$GAMES_DAT" ]]; then
    echo "File not found: $GAMES_DAT"
    exit 1
fi

cp "$GAMES_DAT" "$BACKUP_FILE"

python3 - <<EOF
import csv

input_file = "$BACKUP_FILE"
output_file = "$GAMES_DAT"

with open(input_file, newline='', encoding='utf-8') as f:
    reader = list(csv.reader(f, quotechar='"'))
    header = reader[0]
    data = reader[1:]

    id_index = header.index("Id") if "Id" in header else -1
    name_index = header.index("Name") if "Name" in header else -1

    if id_index != -1 and name_index != -1:
        for row in data:
            if row[id_index].strip() == "":
                row[id_index] = row[name_index]

with open(output_file, 'w', newline='', encoding='utf-8') as f:
    writer = csv.writer(f, quoting=csv.QUOTE_ALL)
    writer.writerow(header)
    writer.writerows(data)
EOF

sync

# Add SD card permissions fix
grep -q 'chmod 777' /opt/rgbpi/autostart.sh || sed -i '1a find /media/sd ! -perm 0777 -exec chmod 777 {} + 2>/dev/null &' /opt/rgbpi/autostart.sh

# Reload OS4 UI without reboot
pkill -f rgbpiui.pyc
setterm --clear --cursor off --foreground black --blank 0 > /dev/tty0
/opt/rgbpi/autostart.sh > /dev/null 2>&1 &

exit 0