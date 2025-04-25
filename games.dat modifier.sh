#!/bin/bash
chmod 777 "$0"

CONFIG_FILE="/opt/rgbpi/ui/config.ini"
DATA_SOURCE=$(grep '^data_source' "$CONFIG_FILE" | cut -d= -f2 | xargs)
GAMES_DAT="/media/$DATA_SOURCE/dats/games.dat"
BACKUP_FILE="${GAMES_DAT}.backup"

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
setterm --clear --cursor off --foreground black --blank 0 > /dev/tty0
sync
pkill -f rgbpiui.pyc
/opt/rgbpi/autostart.sh > /dev/null 2>&1 &