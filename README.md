# omarchy-gdrive-plugin

Widget de barra para [Omarchy](https://omarchy.org) que integra **Google Drive** como Dropbox: montaje FUSE, uso de espacio, archivos recientes, toggle montar/desmontar y notificaciones de cambios.

## Características

- **Montaje automático** vía `rclone` + `systemd` user service (`Type=notify`)
- **Panel en la barra** con estado, cuota, toggle y lista de archivos recientes
- **Archivos recientes** navegables con teclado (`j`/`k`/`Enter`/`Esc`) y apertura en Nautilus
- **Notificaciones** cada 60 s: detecta archivos nuevos/eliminados y avisa en la Shell
- **Re-autorización** integrada: botón "Conectar Google Drive" → terminal flotante

## Requisitos

- Omarchy (Arch-based, Hyprland, Quickshell)
- `rclone` ≥ 1.75 — `omarchy pkg add rclone`
- `fuse3` — `omarchy pkg add fuse3`
- `nautilus` (para abrir archivos)
- Cuenta Google + proyecto en Google Cloud Console

## Instalación rápida

```bash
git clone https://github.com/yersonperez/omarchy-gdrive-plugin.git
cd omarchy-gdrive-plugin
chmod +x scripts/install.sh
./scripts/install.sh
```

El script te pedirá **Client ID** y **Client Secret** de tu cliente OAuth (ver [Configuración OAuth](#configuración-oauth)).
Hace todo automáticamente: configura `rclone`, instala el plugin en `~/.config/omarchy/plugins/yerson.gdrive/`, genera el servicio systemd, lo habilita y recarga la shell.

## Instalación manual

```bash
# 1. Plugin
mkdir -p ~/.config/omarchy/plugins/yerson.gdrive
cp -r plugin/* ~/.config/omarchy/plugins/yerson.gdrive/

# 2. Servicio systemd
mkdir -p ~/.config/systemd/user
sed "s|{{HOME}}|$HOME|g" systemd/rclone-gdrive.service.template \
  > ~/.config/systemd/user/rclone-gdrive.service

# 3. rclone (ver Configuración OAuth)
rclone config create gdrive: drive \
  client_id="TU_CLIENT_ID" \
  client_secret="TU_CLIENT_SECRET" \
  scope="drive"
rclone config reconnect gdrive:

# 4. Activar
mkdir -p ~/GoogleDrive
systemctl --user daemon-reload
systemctl --user enable --now rclone-gdrive.service

# 5. Bookmark Nautilus (opcional)
echo "file://$HOME/GoogleDrive GoogleDrive" >> ~/.config/gtk-3.0/bookmarks

# 6. Recargar shell
omarchy-shell shell rescanPlugins
```

## Configuración OAuth

Google bloquea el `client_id` compartido de rclone. Debes crear tu propio cliente OAuth.

### 1. Google Cloud Console

1. Abre https://console.cloud.google.com/ → selecciona o crea un proyecto.
2. **APIs & Services → Library** → busca **"Google Drive API"** → **Enable**.
3. **APIs & Services → OAuth consent screen** → **Create**:
   - User Type: **External**
   - App name: `Omarchy Google Drive` (o el que quieras)
   - Support email / Developer contact: tu email
   - Scopes: añade `.../auth/drive` (acceso completo a Drive) → **Save**
   - **Test users → Add users** → añade tu email (ej. `tu@gmail.com`). Sin esto verás `403 access_denied`.
   - Save and Continue hasta el final.

### 2. Crear credenciales

1. **APIs & Services → Credentials → + Create Credentials → OAuth client ID**
2. **Application type: Desktop app** ← importante (no "Web application").
   - Name: `Omarchy rclone`
3. **Create** → copia **Client ID** (`...apps.googleusercontent.com`) y **Client Secret** (`GOCSPX-...`).

> Desktop app usa loopback `http://127.0.0.1:53682/` automáticamente. "Web application" requiere configurar redirect URIs.

### 3. Verificar

```bash
rclone about gdrive:
rclone lsl gdrive: --max-depth 1
```

### 4. (Opcional) Publicar la app

Para no añadir test users manualmente: **OAuth consent screen → Publish App**. Requiere verificación de Google (días/semanas). Para uso personal, deja en **Testing** con test users.

## Uso

| Acción | Cómo |
|--------|------|
| Abrir panel | Click izquierdo en 󰊶 |
| Refrescar | Click derecho en el icono · tecla `r` en panel |
| Montar / Desmontar | Click medio · toggle en panel · tecla `m` |
| Navegar archivos | `j` / `k` o `↑` / `↓`, `Enter` abre en Nautilus |
| Re-autorizar | Click en "Conectar Google Drive" · tecla `l` |
| Cerrar panel | `Esc` |

El icono se atenúa al 60 % cuando está desmontado y usa color urgente si el espacio está ≥ 95 % lleno.

### Notificaciones de cambios

Cada `refreshIntervalSec` segundos (default 60, configurable en `~/.config/omarchy/shell.json`) el plugin compara el listado de Drive con el snapshot anterior (`~/.local/state/omarchy/gdrive-snapshot.json`). Si detecta archivos **nuevos** o **eliminados**, muestra una notificación nativa en la Shell con el glifo 󰊶.

## Personalización

En `~/.config/omarchy/shell.json`, dentro del objeto del plugin:

```json
{"id": "yerson.gdrive", "refreshIntervalSec": 30}
```

`refreshIntervalSec`: 10–3600 s, default 60.

## Solución de problemas

| Síntoma | Solución |
|---------|----------|
| `invalid_grant: maybe token expired?` | `rclone config reconnect gdrive:` |
| `Access blocked: this app's request is invalid` | Usa tu propio Client ID/Secret (no el compartido de rclone) |
| `redirect_uri_mismatch` | Crea el cliente como **Desktop app**, no "Web application" |
| `403 access_denied` | Añade tu email en OAuth consent screen → Test users |
| Servicio en `failed` | `journalctl --user -u rclone-gdrive.service -f` |
| No monta al iniciar sesión | `systemctl --user enable rclone-gdrive.service` |
| Panel no aparece | `omarchy-shell shell rescanPlugins` |
| Archivos no abren | Verifica que `~/GoogleDrive` esté montado y Nautilus instalado |

## Estructura

```
omarchy-gdrive-plugin/
├── plugin/                               # Widget (se instala en ~/.config/omarchy/plugins/yerson.gdrive/)
│   ├── manifest.json
│   ├── Panel.qml
│   ├── Service.qml
│   ├── Model.js
│   └── status.py
├── systemd/
│   └── rclone-gdrive.service.template    # Plantilla con {{HOME}}
├── scripts/
│   └── install.sh                        # Instalador interactivo
└── .github/workflows/validate.yml        # CI
```

## Seguridad

**Nunca subas** `client_secret` ni `token` a repos públicos. `~/.config/rclone/rclone.conf` es local y no se incluye en este repo. El `install.sh` pide credenciales interactivamente y las guarda solo en tu máquina.

## Licencia

MIT — ver [LICENSE](LICENSE).
