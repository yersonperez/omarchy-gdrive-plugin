#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "📦 Instalando omarchy-gdrive-plugin..."
echo ""

# 1. Verificar dependencias
for cmd in rclone fusermount3 systemctl; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "❌ Falta: $cmd"
    echo "   Instala con: omarchy pkg add rclone fuse3"
    exit 1
  fi
done

if ! command -v omarchy-shell &>/dev/null; then
  echo "⚠️  omarchy-shell no encontrado, se omitirá el rescan automático"
fi

# 2. Pedir credenciales OAuth
echo "🔐 Configuración OAuth de Google Drive"
echo "   Crea un cliente OAuth 'Desktop app' en https://console.cloud.google.com/"
echo "   APIS & Services → Credentials → Create Credentials → OAuth client ID → Desktop app"
echo ""
read -rp "Google OAuth Client ID: " CLIENT_ID
read -rsp "Google OAuth Client Secret: " CLIENT_SECRET
echo ""

if [[ -z "$CLIENT_ID" || -z "$CLIENT_SECRET" ]]; then
  echo "❌ Client ID y Client Secret son obligatorios"
  exit 1
fi

# 3. Configurar rclone
echo "⚙️  Configurando rclone..."
mkdir -p ~/.config/rclone
rclone config create gdrive: drive \
  client_id="$CLIENT_ID" \
  client_secret="$CLIENT_SECRET" \
  scope="drive" \
  --config ~/.config/rclone/rclone.conf

# 4. Autorizar (abre navegador)
echo "🌐 Abriendo navegador para autorizar Google Drive..."
if ! rclone config reconnect gdrive: --config ~/.config/rclone/rclone.conf; then
  echo "❌ Falló la autorización. Ejecuta manualmente:"
  echo "   rclone config reconnect gdrive:"
  exit 1
fi

# 5. Crear punto de montaje
mkdir -p ~/GoogleDrive

# 6. Instalar plugin
echo "📁 Instalando plugin en ~/.config/omarchy/plugins/yerson.gdrive/..."
mkdir -p ~/.config/omarchy/plugins/yerson.gdrive
cp -r "$REPO_DIR/plugin/"* ~/.config/omarchy/plugins/yerson.gdrive/

# 7. Instalar servicio systemd
echo "🔧 Instalando servicio systemd..."
mkdir -p ~/.config/systemd/user
sed "s|{{HOME}}|$HOME|g" "$REPO_DIR/systemd/rclone-gdrive.service.template" \
  > ~/.config/systemd/user/rclone-gdrive.service

# 8. Habilitar servicio
systemctl --user daemon-reload
systemctl --user enable --now rclone-gdrive.service

# 9. Bookmark en Nautilus
if ! grep -q "GoogleDrive" ~/.config/gtk-3.0/bookmarks 2>/dev/null; then
  mkdir -p ~/.config/gtk-3.0
  echo "file://$HOME/GoogleDrive GoogleDrive" >> ~/.config/gtk-3.0/bookmarks
fi

# 10. Recargar shell
if command -v omarchy-shell &>/dev/null; then
  echo "🔄 Recargando Omarchy shell..."
  omarchy-shell shell rescanPlugins || true
fi

# 11. Añadir a shell.json si no está
if command -v python3 &>/dev/null && [[ -f ~/.config/omarchy/shell.json ]]; then
  python3 - "$HOME" << 'PYEOF'
import json
from pathlib import Path
shell_path = Path.home() / ".config" / "omarchy" / "shell.json"
try:
    data = json.loads(shell_path.read_text(encoding="utf-8"))
    right = data.get("bar", {}).get("right", [])
    ids = [e.get("id") if isinstance(e, dict) else None for e in right]
    if "yerson.gdrive" not in ids:
        # Insertar después de omarchy.tailscale si existe, si no al final antes de power
        insert_at = len(right)
        for i, e in enumerate(right):
            if isinstance(e, dict) and e.get("id") == "omarchy.tailscale":
                insert_at = i + 1
                break
        right.insert(insert_at, {"id": "yerson.gdrive"})
        data["bar"]["right"] = right
        shell_path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print("📌 Añadido yerson.gdrive a shell.json")
    else:
        print("📌 yerson.gdrive ya está en shell.json")
except Exception as e:
    print(f"⚠️  No se pudo actualizar shell.json: {e}")
PYEOF
fi

echo ""
echo "✅ ¡Listo! El icono 󰊶 aparece en la barra."
echo "   Click izquierdo: panel | Click derecho: refresh | Click medio: toggle mount"
echo "   Teclas en panel: j/k navegar, Enter abrir, r refresh, m toggle, l re-autorizar"
echo ""
echo "   Verifica: systemctl --user status rclone-gdrive.service"
echo "             ls ~/GoogleDrive"
