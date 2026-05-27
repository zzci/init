#!/build/bin/busybox/sh

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

if [ -f "$WORK/init.sh" ]; then
    sh "$WORK/init.sh"
fi

# Toggle services via ZSRV_<key>[=<bool|name>] env vars. Runs after init.sh
# so deployment-time env vars are the final authority over what init.sh set up.
# value: true/1/yes/on/empty -> enable using suffix as name
#        false/0/no/off      -> disable: move run/<name>.conf to run/.disabled/<name>.conf
#        other               -> enable using value as service name (for names with -, .)
for var in $(env | grep '^ZSRV_' | cut -d= -f1); do
    eval "value=\$$var"
    case "$value" in
        false|FALSE|False|0|no|NO|off|OFF)
            name=${var#ZSRV_}
            if [ -f "/.init/services/run/$name.conf" ]; then
                mkdir -p /.init/services/run/.disabled
                mv "/.init/services/run/$name.conf" "/.init/services/run/.disabled/$name.conf"
                echo "[$DATE] disabled service via env: $name"
            fi
            continue
            ;;
        ""|true|TRUE|True|1|yes|YES|on|ON)
            name=${var#ZSRV_}
            ;;
        *)
            name="$value"
            ;;
    esac
    if [ -f "/.init/services/run/$name.conf" ]; then
        continue
    fi
    if [ -f "/.init/services/$name.conf" ]; then
        cp -a "/.init/services/$name.conf" "/.init/services/run/$name.conf"
        echo "[$DATE] enabled service via env: $name"
    else
        echo "[$DATE] service config not found: $name"
    fi
done

echo "[$DATE] start supervisord"
exec tini -s -- /build/bin/supervisord -c "$INITCONF"
