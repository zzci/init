#!/build/bin/busybox/sh

export PATH=/build/bin:/build/bin/busybox:$PATH

WORK=/work/.init
INITCONF=/.init/init.conf
DATE=$(date +"%Y-%m-%d %R:%S")

mkdir -p /.init/services/run /tmp
mkdir -p "$WORK"

if [ ! -d "$WORK" ]; then
    echo "[$DATE] Can not create work dir.."
    exit 1
fi

if [ -f "$WORK/init.conf" ]; then
    INITCONF="$WORK/init.conf"
fi

if [ -d /build/services ]; then
    cp -a /build/services/* /.init/services/
fi

if [ -d "$WORK/services" ]; then
    cp -a "$WORK/services"/* /.init/services/
fi

# Enable services via ZSRV_<key>[=<bool|name>] env vars
# value: true/1/yes/on/empty -> enable using suffix as name
#        false/0/no/off      -> skip
#        other               -> use value as service name (for names with -, .)
for var in $(env | grep '^ZSRV_' | cut -d= -f1); do
    eval "value=\$$var"
    case "$value" in
        ""|true|TRUE|True|1|yes|YES|on|ON)
            name=${var#ZSRV_}
            ;;
        false|FALSE|False|0|no|NO|off|OFF)
            continue
            ;;
        *)
            name="$value"
            ;;
    esac
    if [ -f "/.init/services/$name.conf" ]; then
        cp -a "/.init/services/$name.conf" "/.init/services/run/$name.conf"
        echo "[$DATE] enabled service via env: $name"
    else
        echo "[$DATE] service config not found: $name"
    fi
done

if [ -f "$WORK/init.sh" ]; then
    sh "$WORK/init.sh"
fi

echo "[$DATE] start supervisord"
exec tini -s -- /build/bin/supervisord -c "$INITCONF"
